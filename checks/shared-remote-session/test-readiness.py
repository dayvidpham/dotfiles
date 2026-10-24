"""Given compositor startup outcomes, readiness should be bounded and truthful."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

WRAPPER = sys.argv.pop(1)


class ReadinessTests(unittest.TestCase):
    def run_case(self, behavior, stale=False):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "wayland-1")
            notified = Path(tmp) / "ready"
            notify = Path(tmp) / "notify"
            notify.write_text(f"#!{sys.executable}\nfrom pathlib import Path\nPath({str(notified)!r}).touch()\n")
            notify.chmod(0o755)
            if stale:
                with socket.socket(socket.AF_UNIX) as sock:
                    sock.bind(path)
            if behavior == "success":
                code = "import socket,time,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(); time.sleep(.25)"
            elif behavior == "death":
                code = "raise SystemExit(23)"
            else:
                code = "import time; time.sleep(10)"
            result = subprocess.run([sys.executable, WRAPPER, "--socket", path,
                                     "--timeout", ".5", "--notify", str(notify), "--",
                                     sys.executable, "-c", code, path],
                                    capture_output=True, text=True, timeout=4)
            return result, notified.exists()

    def test_listening_socket_success(self):
        result, notified = self.run_case("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(notified)

    def test_child_death_never_notifies(self):
        result, notified = self.run_case("death")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("child exited", result.stderr)
        self.assertFalse(notified)

    def test_stale_bound_socket_is_not_readiness(self):
        result, notified = self.run_case("timeout", stale=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("readiness timeout", result.stderr)
        self.assertFalse(notified)

    def test_signal_shutdown_kills_term_ignoring_child(self):
        with tempfile.TemporaryDirectory() as tmp:
            pidfile = Path(tmp) / 'pid'
            code = ('import os,signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                    f'pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(30)')
            process = subprocess.Popen([sys.executable, WRAPPER, '--socket', str(Path(tmp) / 'missing'),
                                        '--timeout', '20', '--notify', '/unused', '--',
                                        sys.executable, '-c', code])
            try:
                deadline = time.monotonic() + 3
                while not pidfile.exists() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(pidfile.exists())
                pid = int(pidfile.read_text())
                process.terminate()
                process.wait(timeout=4)
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_absent_socket_times_out(self):
        result, notified = self.run_case("timeout")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("readiness timeout", result.stderr)
        self.assertFalse(notified)


unittest.main()
