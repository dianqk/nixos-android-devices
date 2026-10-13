#!/usr/bin/env python3
"""Exercise the actual ACM gate and getty policy without a USB controller/root."""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import tty
import unittest


HELPER = Path(sys.argv.pop(1)).resolve()


class AcmGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("MOBILE_TEST_TMP"))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state"
        self.marker = self.root / "called.json"
        self.master, self.slave = pty.openpty()
        tty.setraw(self.slave)
        self.addCleanup(os.close, self.master)
        self.addCleanup(os.close, self.slave)
        self.spy = self.root / "getty.py"
        self.spy.write_text(
            "import json, os, pathlib, sys\n"
            "fd = os.open(sys.argv[2], os.O_WRONLY | os.O_NOCTTY)\n"
            "os.write(fd, b'ready\\n'); os.close(fd)\n"
            "pathlib.Path(sys.argv[1]).write_text(json.dumps("
            "{'pid': os.getpid(), 'args': sys.argv[3:]}))\n"
            "sys.exit(17)\n"
        )

    def start(self, command=None, stdio=False):
        if command is None:
            command = [sys.executable, str(self.spy), str(self.marker),
                       os.ttyname(self.slave), "argument with spaces", "$literal", ""]
        process = subprocess.Popen(
            ["bash", str(HELPER), str(self.state), *command],
            stdin=self.slave if stdio else subprocess.DEVNULL,
            stdout=self.slave if stdio else subprocess.DEVNULL,
            stderr=self.slave if stdio else subprocess.PIPE,
            start_new_session=True,
        )

        def cleanup():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            if process.stderr:
                process.stderr.close()
        self.addCleanup(cleanup)
        return process

    def assert_waiting(self, process, duration=1.2):
        time.sleep(duration)
        self.assertIsNone(process.poll())
        self.assertFalse(self.marker.exists())
        self.assertFalse(select.select([self.master], [], [], 0)[0])

    def configured(self):
        self.state.write_text("configured\n")

    def read_until(self, expected, process, timeout=5):
        received = b""
        deadline = time.monotonic() + timeout
        while expected not in received and time.monotonic() < deadline:
            if select.select([self.master], [], [], 0.1)[0]:
                received += os.read(self.master, 4096)
            elif process.poll() is not None:
                break
        self.assertIn(expected, received)
        return received

    def test_missing_and_unconfigured_controller_never_runs_getty(self):
        process = self.start()
        self.assert_waiting(process)
        for state in ["not attached", "powered", "default", "addressed", "suspended"]:
            self.state.write_text(state + "\n")
            self.assert_waiting(process, 1.2)
        self.configured()
        self.assertEqual(process.wait(timeout=5), 17)
        self.assertTrue(self.marker.exists())
        self.assertEqual(process.stderr.read(), b"")

    def test_exec_preserves_pid_arguments_and_exit_status(self):
        self.configured()
        process = self.start()
        self.assertEqual(process.wait(timeout=5), 17)
        record = json.loads(self.marker.read_text())
        self.assertEqual(record["pid"], process.pid)
        self.assertEqual(record["args"], ["argument with spaces", "$literal", ""])
        self.read_until(b"ready\n", process)

    def test_restarted_getty_waits_for_reconnection(self):
        self.configured()
        first = self.start()
        self.assertEqual(first.wait(timeout=5), 17)
        self.read_until(b"ready\n", first)
        self.marker.unlink()
        self.state.unlink()
        restarted = self.start()
        self.assert_waiting(restarted)
        self.configured()
        self.assertEqual(restarted.wait(timeout=5), 17)
        self.assertEqual(json.loads(self.marker.read_text())["pid"], restarted.pid)

    def test_waiter_stops_promptly(self):
        process = self.start()
        self.assert_waiting(process, 0.15)
        started = time.monotonic()
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
        self.assertLess(time.monotonic() - started, 2)
        self.assertFalse(self.marker.exists())

    def login_program(self):
        login = self.root / "login"
        login.write_text(
            "#!" + shutil.which("bash") + "\n"
            "printf '%s\\n' \"$@\" > " + str(self.root / "login-args") + "\n"
        )
        login.chmod(0o755)
        return login

    def test_real_getty_prompt_after_configuration(self):
        login = self.login_program()
        process = self.start([
            "agetty", "--login-program", str(login), "--noissue", "--noclear",
            "-", "115200", "vt100",
        ], stdio=True)
        self.assert_waiting(process)
        self.configured()
        self.read_until(b"login:", process)
        self.assertFalse((self.root / "login-args").exists())
        os.write(self.master, b"demo\n")
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual((self.root / "login-args").read_text().splitlines(), ["--", "demo"])

    def test_real_getty_accepts_tty1_autologin_option_after_positionals(self):
        self.configured()
        login = self.login_program()
        process = self.start([
            "agetty", "--login-program", str(login), "--noissue", "--noclear",
            "-", "115200", "vt100", "--autologin", "demo",
        ], stdio=True)
        self.read_until(b"automatic login", process)
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual((self.root / "login-args").read_text().splitlines(), ["-f", "--", "demo"])


if __name__ == "__main__":
    unittest.main()
