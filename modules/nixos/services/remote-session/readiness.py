"""Supervise the shared compositor; notify only after its socket accepts connections."""
import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--notify", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    child = subprocess.Popen(command, start_new_session=True)

    def stop_group(sig):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    deadline = time.monotonic() + args.timeout
    ready = False
    try:
        while child.poll() is None and time.monotonic() < deadline:
            with socket.socket(socket.AF_UNIX) as probe:
                probe.settimeout(min(0.1, max(0.001, deadline - time.monotonic())))
                try:
                    probe.connect(args.socket)
                    ready = child.poll() is None
                except OSError:
                    pass
            if ready:
                break
            time.sleep(0.05)
        if not ready:
            reason = "child exited" if child.poll() is not None else "readiness timeout"
            print(json.dumps({"event": "CompositorReadinessFailed", "reason": reason,
                              "socket": args.socket, "module": "remote-session",
                              "action": "Check compositor journal and renderDevice; consumers were not started"}), file=sys.stderr)
            return 1
        subprocess.run([args.notify, "--ready"], check=True)
        return child.wait()
    finally:
        stop_group(signal.SIGTERM)
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            stop_group(signal.SIGKILL)
            child.wait()
        finally:
            # Also reap a private-bus/compositor descendant that outlived its parent.
            stop_group(signal.SIGKILL)


if __name__ == "__main__":
    sys.exit(main())
