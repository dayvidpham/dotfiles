#!/usr/bin/env python3
"""Opt-in real user-manager proof; NEVER uses production audio/client units.

Run: python3 checks/remote-audio-client/inert-lifecycle.py
Only unique dsh-audio-test-* transient units and inert Python flock holders run.
Requires systemd-run/systemctl on PATH and an existing user manager. No activation.
"""
import concurrent.futures
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid


def record(root, **event):
    fd = os.open(root / "events.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, (json.dumps(event) + "\n").encode())
    finally:
        os.close(fd)


def fixture(root, role, fail):
    with (root / "sound.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            record(root, event="Overlap", role=role, pid=os.getpid())
            return 99
        record(root, event="Started", role=role, pid=os.getpid())
        if fail:
            return 23
        signal.alarm(120)  # hard upper bound even if the runner is interrupted
        signal.pause()
    return 0


def wait_until(predicate, description, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.025)
    raise AssertionError("Timed out: " + description)


class Scenario:
    def __init__(self, root, name):
        self.root = root / name
        self.root.mkdir()
        self.prefix = "dsh-audio-test-" + uuid.uuid4().hex
        self.parent = self.prefix + "-parent.service"
        self.recv = self.prefix + "-recv.service"
        self.scope = self.prefix + "-moonlight.scope"
        self.launchers = []
        self.outputs = []

    def run(self, *args, check=True):
        record(self.root, event="Command", argv=list(args))
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        record(self.root, event="Result", status=result.returncode,
               stdout=result.stdout, stderr=result.stderr)
        if check and result.returncode:
            raise AssertionError((args, result.returncode, result.stderr))
        return result

    def active(self, unit):
        return self.run("systemctl", "--user", "is-active", unit, check=False).returncode == 0

    def events(self):
        path = self.root / "events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def count(self, role):
        return sum(e.get("event") == "Started" and e.get("role") == role for e in self.events())

    def begin(self):
        self.run("systemd-run", "--user", "--unit=" + self.parent,
                 "--property=Type=exec", "--", "sleep", "120")
        self.run("systemd-run", "--user", "--unit=" + self.recv,
                 "--property=Type=exec", "--property=Restart=always", "--property=RestartSec=0.1",
                 "--property=PartOf=" + self.parent, "--property=Conflicts=" + self.scope,
                 "--", sys.executable, str(Path(__file__).resolve()), "--fixture", str(self.root), "Receiver")
        wait_until(lambda: self.count("Receiver") >= 1, "receiver acquires sound lock")

    def moonlight(self, fail=False):
        argv = ["systemd-run", "--user", "--scope", "--collect", "--unit=" + self.scope,
                "--expand-environment=no", "--property=Conflicts=" + self.recv,
                "--property=After=" + self.recv, "--", sys.executable,
                str(Path(__file__).resolve()), "--fixture", str(self.root), "Moonlight"]
        if fail:
            argv.append("fail")
        record(self.root, event="Command", argv=argv)
        output = (self.root / ("scope-%d.log" % len(self.launchers))).open("w")
        self.outputs.append(output)
        launcher = subprocess.Popen(argv, stdout=output, stderr=subprocess.STDOUT)
        self.launchers.append(launcher)
        return launcher

    def ready(self):
        wait_until(lambda: self.count("Moonlight") >= 1, "Moonlight acquires sound lock")
        assert self.active(self.scope)
        assert not self.active(self.recv)

    def close(self):
        # Only exact names created by THIS instance. Inactive transient units may
        # already be collected; stop's missing-unit error is therefore expected.
        self.run("systemctl", "--user", "stop", self.scope, self.recv, self.parent, check=False)
        for launcher in self.launchers:
            launcher.wait(timeout=10)
        for output in self.outputs:
            output.close()
        for unit in [self.scope, self.recv, self.parent]:
            assert not self.active(unit), "Fixture still active: " + unit
        for event in self.events():
            assert event.get("event") != "Overlap", event
            if event.get("event") == "Started":
                proc = Path("/proc") / str(event["pid"])
                # Zombies are no longer running and hold no sound lock.
                if proc.exists():
                    state = (proc / "stat").read_text().split(") ", 1)[1].split()[0]
                    assert state == "Z", "Fixture process remains: " + str(proc)
        record(self.root, event="CleanupVerified")


def main():
    root = Path(tempfile.mkdtemp(prefix="dsh-audio-test-"))
    print("Inert systemd evidence:", root, flush=True)
    scenarios = []
    try:
        def scenario(name):
            test = Scenario(root, name)
            scenarios.append(test)
            test.begin()
            return test

        test = scenario("duplicate-and-reverse")
        first = test.moonlight()
        test.ready()
        duplicate = test.moonlight()
        assert duplicate.wait(timeout=10) != 0, "Duplicate scope accepted"
        assert test.active(test.scope)
        test.run("systemctl", "--user", "start", test.recv)
        wait_until(lambda: test.count("Receiver") >= 2, "reverse transition acquires lock")
        assert test.active(test.recv) and not test.active(test.scope)
        first.wait(timeout=10)

        test = scenario("parent-restart")
        test.moonlight()
        test.ready()
        test.run("systemctl", "--user", "restart", test.parent)
        assert test.active(test.scope) and not test.active(test.recv)
        time.sleep(0.3)  # exceed RestartSec; stopped receiver must not retry
        assert test.count("Receiver") == 1

        test = scenario("receiver-crash-retry")
        test.run("systemctl", "--user", "kill", "--kill-whom=main", "--signal=KILL", test.recv)
        wait_until(lambda: test.count("Receiver") >= 2, "receiver restart after crash")
        test.moonlight()
        test.ready()
        time.sleep(0.3)
        assert not test.active(test.recv)

        for fail in [False, True]:
            test = scenario("client-failure" if fail else "client-exit")
            launcher = test.moonlight(fail)
            wait_until(lambda: test.count("Moonlight") >= 1, "client started")
            if not fail:
                test.run("systemctl", "--user", "stop", test.scope)
            status = launcher.wait(timeout=10)
            if fail:
                assert status != 0
            time.sleep(0.3)
            assert not test.active(test.recv), "ROC restored after client exit"
            assert test.count("Receiver") == 1

        for iteration in range(8):
            test = scenario("simultaneous-%d" % iteration)
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                launch = pool.submit(test.moonlight)
                restart = pool.submit(test.run, "systemctl", "--user", "restart", test.recv, check=False)
                launcher = launch.result()
                restart.result()
            # Conflicting simultaneous jobs may cancel one another. Either winner
            # is valid; a live receiver and scope together is never valid.
            time.sleep(0.3)
            assert not (test.active(test.recv) and test.active(test.scope))
            if launcher.poll() is not None:
                launcher.wait(timeout=10)
        print("PASS: duplicates, both transitions, parent restart, crash/retry, exit/failure, 8 simultaneous starts", flush=True)
    finally:
        errors = []
        for test in scenarios:
            try:
                test.close()
            except Exception as error:
                errors.append((test.prefix, repr(error)))
        if errors:
            raise AssertionError(("Fixture cleanup/overlap failed", errors, str(root)))
        print("PASS: exact-unit cleanup verified; no fixture processes remain", flush=True)


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "--fixture":
        sys.exit(fixture(Path(sys.argv[2]), sys.argv[3], len(sys.argv) > 4))
    elif len(sys.argv) == 4 and sys.argv[1] == "--fixture":
        sys.exit(fixture(Path(sys.argv[2]), sys.argv[3], False))
    else:
        main()
