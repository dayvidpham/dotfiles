#!/usr/bin/env python3
"""clip-sync — bidirectional clipboard reconciler.

Keeps a *local* clipboard (wl-clipboard in this session) and a *peer* clipboard
(clipd over a unix socket) in sync, without feedback loops, using a single
"last agreed content" hash.

Each tick it reads both sides and picks one representation each (non-empty
text/plain, else image/png), then:

    if peer != last:  copy peer -> local,  last = peer
    elif local != last: PUT local -> peer, last = local

Because both sides are compared against the same `last`, a value that arrived
from the peer is not pushed back, and vice versa. Simultaneous changes resolve
last-writer-wins (peer is checked first).

At startup `last` is seeded from the peer if it has content, otherwise from the
local clipboard, so a pre-existing local selection is never pushed at start.

Usage: clip-sync <peer-socket> [interval-seconds]
"""
import base64
import hashlib
import json
import os
import signal
import subprocess
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip import TEXT, PNG, request  # noqa: E402

STOP = threading.Event()
SUPPORTED = (TEXT, PNG)


def wl_paste(mime: str):
    try:
        proc = subprocess.run(
            ["wl-paste", "--no-newline", "--type", mime],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return proc.stdout if proc.returncode == 0 and proc.stdout else None


def wl_copy(mime: str, data: bytes) -> bool:
    try:
        proc = subprocess.run(
            ["wl-copy", "--type", mime],
            input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False
    return proc.returncode == 0


def read_local():
    for mime in SUPPORTED:
        data = wl_paste(mime)
        if data:
            return mime, data
    return None


def read_peer(socket_path: str):
    try:
        status, body = request(socket_path, "GET", "/clip", timeout=10)
    except Exception:
        return None
    if status != 200:
        return None
    obj = json.loads(body)
    mime = obj.get("type", TEXT)
    if mime not in SUPPORTED:
        mime = TEXT
    data = base64.b64decode(obj["data"])
    return (mime, data) if data else None


def write_peer(socket_path: str, mime: str, data: bytes) -> bool:
    body = json.dumps({"type": mime, "data": base64.b64encode(data).decode()}).encode()
    try:
        status, _ = request(socket_path, "PUT", "/clip", body=body, timeout=10)
    except Exception:
        return False
    return status == 200


def digest(item):
    if item is None:
        return None
    mime, data = item
    return hashlib.sha256(mime.encode() + b"\0" + data).digest()


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: clip-sync <peer-socket> [interval-seconds]", file=sys.stderr)
        return 2
    socket_path = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: STOP.set())

    # Seed `last`: peer wins at startup if it has content, else adopt local so we
    # do not clobber the peer with a stale pre-existing local selection.
    peer = read_peer(socket_path)
    local = read_local()
    last = digest(peer) if peer is not None else digest(local)

    while not STOP.is_set():
        peer = read_peer(socket_path)
        local = read_local()
        ph, lh = digest(peer), digest(local)

        if ph is not None and ph != last:
            if wl_copy(peer[0], peer[1]):
                last = ph
        elif lh is not None and lh != last:
            if write_peer(socket_path, local[0], local[1]):
                last = lh

        STOP.wait(interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
