#!/usr/bin/env python3
"""
opencode-db-vacuum.py — compact OpenCode's SQLite database.

Reclaims freelist space left behind by row deletion (e.g. the V2 migration's
"Clearing old events" phase) by rebuilding the database with VACUUM INTO,
verifying the result, then swapping it in atomically. The original file is
NEVER modified or deleted by this script; after the swap it remains alongside
as a .bak that you remove manually once satisfied.

Pipeline (full run):
  1. preflight   read-only checks: quiet system, free space, size prediction
  2. checkpoint  fold any -wal content into the main file (needs quiet system)
  3. compact     VACUUM INTO <db dir>/opencode.db.compact-<ts>   (slow: hours)
  4. verify      integrity_check + schema equality + per-table row counts
  5. swap        rename-only: db -> .bak, compact -> db  (atomic, instant)
  6. restart     opencode2 service start + /api/health check

Usage:
  opencode-db-vacuum.py --dry-run          # report only, writes nothing at all
  opencode-db-vacuum.py                    # full pipeline
  opencode-db-vacuum.py --verify-only F    # verify an existing compact file
  opencode-db-vacuum.py --swap F           # resume: preflight, verify F, swap, restart
  opencode-db-vacuum.py --swap F --no-restart   # same, but leave the service down

--swap picks up a run whose compact file already exists (for example after a
verify failure that turned out to be benign). It re-verifies F against the db
before touching anything. The swap is rename-only, so F must sit on the same
filesystem as the db.

Before a full run you MUST have:
  * every opencode / opencode2 session closed (TUIs, `run`, agents — the
    script aborts if it sees any opencode process, including this harness)
  * the background service stopped:  opencode2 service stop
  * run it from a plain terminal, not from inside an opencode session
"""

import argparse
import json
import os
import signal
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

GiB = 1024**3
EXIT_OK = 0
EXIT_PREFLIGHT = 2
EXIT_VACUUM = 3
EXIT_VERIFY = 4
EXIT_SWAP = 5

# opencode binary names whose running processes mean "not quiet"
# (v1 `opencode`, v2 `opencode2`, plus the bun-compiled .exe variants)
OPENCODE_NAMES = {"opencode", "opencode.exe", "opencode2", "opencode2.exe"}

STATE_DIR = Path.home() / ".local/state/opencode"
DATA_DIR = Path.home() / ".local/share/opencode"
DEFAULT_DB = DATA_DIR / "opencode.db"

# free-space rule: predicted final size * this factor + buffer
SPACE_FACTOR = 1.25
SPACE_BUFFER = 5 * GiB


def now_str():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def ts_str():
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def human(n):
    x = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(x) < 1024:
            return f"{x:.1f} {unit}"
        x /= 1024
    return f"{x:.1f} PiB"


def elapsed(t0):
    s = int(time.time() - t0)
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return (f"{h}h " if h else "") + (f"{m}m " if m else "") + f"{sec}s"


class Log:
    """Print to stdout and (optionally) append to a log file."""

    def __init__(self, path=None):
        self.path = path

    def __call__(self, msg=""):
        line = f"[{now_str()}] {msg}"
        print(line, flush=True)
        if self.path:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(line + "\n")


# ---------------------------------------------------------------- quiet check

def opencode_processes():
    """Return {pid: cmdline} for every running opencode-ish process (not us)."""
    found = {}
    me = os.getpid()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == me:
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        args = [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]
        if not args:
            continue
        basenames = {os.path.basename(a).lower() for a in args}
        if basenames & OPENCODE_NAMES:
            found[pid] = " ".join(args)[:160]
    return found


def service_probe():
    """Best-effort probe of the registered background service. Report-only."""
    info = STATE_DIR / "service.json"
    try:
        data = json.loads(info.read_text())
    except Exception:
        return "no service.json (unregistered)"
    for key in ("url", "port"):
        if key in data:
            url = str(data[key])
            host, _, port = url.removeprefix("http://").partition(":")
            try:
                with socket.create_connection((host or "127.0.0.1", int(port)), timeout=1):
                    return f"service answering at {url}"
            except Exception:
                continue
    pid = data.get("pid")
    if pid and Path(f"/proc/{pid}").exists():
        return f"service pid {pid} alive"
    return "service.json present, not answering"


# ----------------------------------------------------------------- sqlite bit

def open_ro(path):
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30, isolation_level=None)


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def read_meta(path, log=None):
    con = open_ro(path)
    try:
        cur = con.cursor()
        page_size = cur.execute("PRAGMA page_size").fetchone()[0]
        page_count = cur.execute("PRAGMA page_count").fetchone()[0]
        freelist = cur.execute("PRAGMA freelist_count").fetchone()[0]
        journal = cur.execute("PRAGMA journal_mode").fetchone()[0]
        auto_vacuum = cur.execute("PRAGMA auto_vacuum").fetchone()[0]
    finally:
        con.close()
    return {
        "page_size": page_size,
        "page_count": page_count,
        "freelist_count": freelist,
        "journal_mode": journal,
        "auto_vacuum": auto_vacuum,
    }


def table_names(path):
    con = open_ro(path)
    try:
        rows = con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        return [r[0] for r in rows]
    finally:
        con.close()


def count_rows(path, table):
    con = open_ro(path)
    try:
        return con.execute(f"SELECT COUNT(*) FROM {quote_ident(table)}").fetchone()[0]
    finally:
        con.close()


# ------------------------------------------------------------------ preflight

def preflight(db, check_space=True):
    """All read-only. Returns list of (name, passed, detail) plus a report.

    check_space=False skips the free-space gate (a rename-only --swap writes
    no new file); the size figures are still reported.
    """
    checks = []

    def add(name, ok, detail=""):
        checks.append((name, ok, detail))
        return ok

    add("sqlite >= 3.27 (VACUUM INTO)", sqlite3.sqlite_version_info >= (3, 27, 0),
        sqlite3.sqlite_version)
    add("database exists", db.is_file(), str(db))

    procs = opencode_processes()
    add("no opencode/opencode2 processes running", not procs,
        f"{len(procs)} found: {procs}" if procs else service_probe())

    meta = read_meta(db)
    wal = Path(str(db) + "-wal")
    wal_size = wal.stat().st_size if wal.exists() else 0
    live = (meta["page_count"] - meta["freelist_count"]) * meta["page_size"]
    predicted = live + wal_size
    free = os.statvfs(str(db.parent)).f_bavail * os.statvfs(str(db.parent)).f_frsize
    needed = int(predicted * SPACE_FACTOR) + SPACE_BUFFER

    if check_space:
        add("free space on db filesystem", free >= needed,
            f"free {human(free)}, needed {human(needed)} (predicted final {human(predicted)})")
    add("freelist sanity", 0 <= meta["freelist_count"] <= meta["page_count"],
        f"freelist {meta['freelist_count']}/{meta['page_count']} pages")

    report = {
        "checks": checks,
        "meta": meta,
        "wal_size": wal_size,
        "file_size": db.stat().st_size if db.is_file() else 0,
        "live": live,
        "predicted_final": predicted,
        "free": free,
        "needed": needed,
        "reclaimable": meta["freelist_count"] * meta["page_size"],
    }
    return report


def print_report(rep, log):
    log("== preflight (read-only) ==")
    for name, ok, detail in rep["checks"]:
        log(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if detail else ""))
    m = rep["meta"]
    log(f"  db file            {human(rep['file_size'])}")
    log(f"  journal mode       {m['journal_mode']}   auto_vacuum={m['auto_vacuum']}")
    log(f"  live data          {human(rep['live'])}")
    log(f"  reclaimable        {human(rep['reclaimable'])} "
        f"({100 * m['freelist_count'] / max(1, m['page_count']):.1f}% of file)")
    log(f"  un-checkpointed WAL {human(rep['wal_size'])}")
    log(f"  predicted final    {human(rep['predicted_final'])}")


# ------------------------------------------------------------------ pipeline

def checkpoint_wal(db, log):
    wal = Path(str(db) + "-wal")
    if not wal.exists() or wal.stat().st_size == 0:
        log("  WAL already empty — nothing to checkpoint")
        return
    log(f"  folding {human(wal.stat().st_size)} of WAL into the main file")
    con = sqlite3.connect(str(db), timeout=120, isolation_level=None)
    try:
        result = con.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        log(f"  wal_checkpoint(TRUNCATE) -> {result}")
    finally:
        con.close()


def do_vacuum(src, dst, predicted, log):
    """VACUUM INTO dst. Never writes to src. Returns final size or None."""
    stop = threading.Event()

    def monitor():
        while not stop.wait(15):
            try:
                size = dst.stat().st_size
            except OSError:
                continue
            pct = min(100.0, 100.0 * size / max(1, predicted))
            log(f"  compacting... {human(size)}  (~{pct:.0f}% of predicted {human(predicted)})")

    t = threading.Thread(target=monitor, daemon=True)
    t.start()
    t0 = time.time()
    target = str(dst).replace("'", "''")
    try:
        try:
            con = open_ro(src)
            try:
                con.execute(f"VACUUM INTO '{target}'")
            finally:
                con.close()
        except sqlite3.OperationalError:
            # read-only connection refused VACUUM INTO; system is quiet, so a
            # read-write connection is safe (VACUUM INTO still never writes src)
            log("  read-only connection could not run VACUUM INTO; retrying read-write")
            con = sqlite3.connect(str(src), timeout=120, isolation_level=None)
            try:
                con.execute(f"VACUUM INTO '{target}'")
            finally:
                con.close()
    except Exception as e:
        log(f"  VACUUM FAILED: {e}")
        log(f"  original untouched; partial output left at {dst} (safe to delete)")
        return None
    finally:
        stop.set()
    size = dst.stat().st_size
    log(f"  compacted to {human(size)} in {elapsed(t0)}")
    return size


def do_verify(orig, compact, log):
    """Returns True if compact is a faithful, integral copy."""
    ok = True

    log("== verify: integrity_check on compact file ==")
    t0 = time.time()
    con = open_ro(compact)
    try:
        rows = con.execute("PRAGMA integrity_check").fetchall()
    finally:
        con.close()
    if rows == [("ok",)]:
        log(f"  ok ({elapsed(t0)})")
    else:
        ok = False
        log(f"  INTEGRITY FAIL ({elapsed(t0)}): {rows[:10]}")

    log("== verify: schema equality (user objects only) ==")

    # Compare only user-defined objects, the same filter table_names() uses.
    # SQLite's own sqlite_* entries are not part of what VACUUM preserves:
    #   * sqlite_sequence is created the first time any AUTOINCREMENT table
    #     exists and is never dropped, but VACUUM rebuilds the schema from the
    #     live CREATE statements and skips it on purpose. So it is absent from
    #     the copy whenever no current table uses AUTOINCREMENT, and SQLite
    #     recreates it on demand. Comparing it produced a false verify failure.
    #   * sqlite_autoindex_* carry no sql of their own; they are implied by the
    #     UNIQUE / PRIMARY KEY clauses in the table sql compared here.
    def schema(p):
        con = open_ro(p)
        try:
            return con.execute(
                "SELECT type, name, sql FROM sqlite_master"
                " WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
            ).fetchall()
        finally:
            con.close()

    s1, s2 = schema(orig), schema(compact)
    if s1 == s2:
        log(f"  ok ({len(s1)} entries)")
    else:
        ok = False
        only_orig = [x for x in s1 if x not in s2]
        only_compact = [x for x in s2 if x not in s1]
        log(f"  SCHEMA MISMATCH: only in original: {only_orig[:5]}"
            f"  only in compact: {only_compact[:5]}")

    log("== verify: per-table row counts (original vs compact) ==")
    for table in table_names(orig):
        c1 = count_rows(orig, table)
        c2 = count_rows(compact, table)
        if c1 == c2:
            log(f"  [PASS] {table:32s} {c1:>12,}")
        else:
            ok = False
            log(f"  [FAIL] {table:32s} orig={c1:,} compact={c2:,}")
    return ok


def do_swap(db, compact, ts, log):
    """Rename-only swap. db -> .bak, compact -> db. Needs a quiet system."""
    procs = opencode_processes()
    if procs:
        log(f"  ABORT: opencode processes appeared: {procs}")
        return None
    # Every guard runs BEFORE the first rename, so a refusal leaves both files
    # exactly where they were.
    if not compact.is_file():
        log(f"  ABORT: compact file missing: {compact}")
        return None
    if compact.resolve() == db.resolve():
        log("  ABORT: compact path is the database itself")
        return None
    if compact.stat().st_dev != db.stat().st_dev:
        log(f"  ABORT: {compact.name} is on a different filesystem than {db.name}; "
            "rename cannot cross filesystems, move it next to the db first")
        return None
    compact_wal = Path(str(compact) + "-wal")
    if compact_wal.exists() and compact_wal.stat().st_size > 0:
        log(f"  ABORT: {compact_wal.name} is non-empty; the compact file was opened "
            "read-write and holds un-checkpointed changes")
        return None

    wal = Path(str(db) + "-wal")
    shm = Path(str(db) + "-shm")
    bak = db.with_name(f"{db.name}.pre-vacuum-{ts}.bak")

    # Block Ctrl-C / SIGTERM across the rename sequence so it cannot split.
    blocked = {signal.SIGINT, signal.SIGTERM}
    signal.pthread_sigmask(signal.SIG_BLOCK, blocked)
    try:
        # Move any stale -wal/-shm aside FIRST so the fresh db never lands
        # next to a WAL that belongs to the old file.
        if wal.exists():
            wal.rename(bak.with_name(bak.name + "-wal"))
        if shm.exists():
            shm.rename(bak.with_name(bak.name + "-shm"))
        db.rename(bak)
        compact.rename(db)
        # Sidecars of the compact file exist only if it was ever opened in WAL
        # mode, and the guard above proved the -wal is empty. Drop them so
        # they cannot be mistaken for live state later.
        for side in (compact_wal, Path(str(compact) + "-shm")):
            if side.exists():
                side.unlink()
        os.sync()
    finally:
        signal.pthread_sigmask(signal.SIG_UNBLOCK, blocked)
    log(f"  swapped: {db.name} <- {compact.name}; original kept as {bak.name}")
    return bak


def restart_service(log):
    exe = None
    for candidate in ("opencode2",):
        exe = subprocess.run(["sh", "-c", f"command -v {candidate}"], capture_output=True, text=True)
        if exe.returncode == 0:
            break
    if not exe or exe.returncode != 0:
        log("  opencode2 not on PATH; start the service manually when ready")
        return
    log("== restart: opencode2 service start ==")
    try:
        r = subprocess.run(["opencode2", "service", "start"], timeout=180,
                           capture_output=True, text=True)
        log(f"  service start: rc={r.returncode} {(r.stdout or r.stderr).strip()[:200]}")
    except Exception as e:
        log(f"  service start failed: {e}")
        return
    try:
        h = subprocess.run(["opencode2", "api", "get", "/api/health"], timeout=60,
                           capture_output=True, text=True)
        log(f"  health: rc={h.returncode} {(h.stdout or h.stderr).strip()[:200]}")
    except Exception as e:
        log(f"  health check failed: {e} (start it manually and check your sessions)")


def land(db, compact, ts, before, restart, log, step_swap, step_restart):
    """Tail shared by the full pipeline and --swap: swap, restart, summary."""
    log(f"== {step_swap}: swap (rename-only) ==")
    bak = do_swap(db, compact, ts, log)
    if bak is None:
        return EXIT_SWAP

    log(f"== {step_restart}: restart service ==")
    if restart:
        restart_service(log)
    else:
        log("  skipped (--no-restart); start it yourself: opencode2 service start")

    after = db.stat().st_size
    log("== summary ==")
    log(f"  before : {human(before)}")
    log(f"  after  : {human(after)}")
    log(f"  backup : {bak}  ({human(bak.stat().st_size)}) — delete it manually once you are happy:")
    log(f"           rm '{bak}'{'*' if (Path(str(bak) + '-wal').exists() or Path(str(bak) + '-shm').exists()) else ''}")
    log("  open opencode, confirm your sessions are there, then reclaim the space")
    return EXIT_OK


# ----------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Compact OpenCode's SQLite DB via VACUUM INTO + atomic swap.")
    ap.add_argument("--db", type=Path, default=None,
                    help=f"database path (default: $OPENCODE_DB or {DEFAULT_DB})")
    ap.add_argument("--dest", type=Path, default=None,
                    help="directory for the compact file (default: same as db)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true",
                      help="read-only report; writes nothing at all")
    mode.add_argument("--verify-only", type=Path, metavar="COMPACT",
                      help="verify an existing compact file against the db, then exit")
    mode.add_argument("--swap", type=Path, metavar="COMPACT",
                      help="skip checkpoint and vacuum: verify an existing compact file, "
                           "then swap it in and restart the service")
    ap.add_argument("--no-restart", action="store_true",
                    help="after the swap, do not start the opencode2 service")
    args = ap.parse_args()

    db = args.db
    if db is None:
        env = os.environ.get("OPENCODE_DB")
        if env and env != ":memory:":
            db = Path(env) if os.path.isabs(env) else DATA_DIR / env
        else:
            db = DEFAULT_DB

    ts = ts_str()
    log = Log(None if args.dry_run else db.parent / f"vacuum-{ts}.log")

    mode_name = ("dry-run" if args.dry_run else "verify-only" if args.verify_only
                 else "swap" if args.swap else "full")
    log(f"opencode-db-vacuum  db={db}  mode={mode_name}")

    rep = preflight(db, check_space=args.swap is None)
    print_report(rep, log)

    if args.dry_run:
        log("dry run complete — nothing was written")
        return EXIT_OK

    if args.verify_only:
        log(f"== verify-only: {db} vs {args.verify_only} ==")
        return EXIT_OK if do_verify(db, args.verify_only, log) else EXIT_VERIFY

    failed = [name for name, ok, _ in rep["checks"] if not ok]
    if failed:
        log(f"ABORT (preflight): {failed}")
        log("Close every opencode/opencode2 session, run `opencode2 service stop`, then retry.")
        return EXIT_PREFLIGHT

    try:
        os.nice(10)
    except OSError:
        pass

    if args.swap:
        compact = args.swap
        if not compact.is_file():
            log(f"ABORT: compact file not found: {compact}")
            return EXIT_PREFLIGHT
        if compact.resolve() == db.resolve():
            log("ABORT: --swap must name the compact file, not the database itself")
            return EXIT_PREFLIGHT
        log(f"== step 1/3: verify {compact} ==")
        if not do_verify(db, compact, log):
            log(f"VERIFY FAILED: original untouched; {compact} was NOT swapped in")
            return EXIT_VERIFY
        return land(db, compact, ts, rep["file_size"], not args.no_restart, log,
                    "step 2/3", "step 3/3")

    log("== step 1/5: checkpoint WAL ==")
    checkpoint_wal(db, log)

    dest_dir = args.dest if args.dest else db.parent
    dest_dir.mkdir(parents=True, exist_ok=True)
    compact = dest_dir / f"{db.name}.compact-{ts}"
    log(f"== step 2/5: VACUUM INTO {compact} ==")
    log("  (this is the long one — expect roughly the live-data size in I/O)")
    if do_vacuum(db, compact, rep["predicted_final"], log) is None:
        return EXIT_VACUUM

    log("== step 3/5: verify ==")
    if not do_verify(db, compact, log):
        log(f"VERIFY FAILED — original untouched; inspect or delete {compact}")
        return EXIT_VERIFY

    return land(db, compact, ts, rep["file_size"], not args.no_restart, log,
                "step 4/5", "step 5/5")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n[{now_str()}] interrupted — original database untouched. "
              f"Any partial compact-*.db file is safe to delete.")
        sys.exit(130)
