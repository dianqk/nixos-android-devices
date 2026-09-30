#!/usr/bin/env python3
"""Exercise the actual Sheng BCB transaction against a 4 MiB fixture."""
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
TEXT = (REPO / "devices/sheng/ab-recovery.sh").read_text()
FUNCTION = TEXT[TEXT.index("clear_boot_request() {"):TEXT.index("operation_lock() {")]
TAIL = bytes(n % 251 for n in range(4194304 - 32))


class Bcb(unittest.TestCase):
    def check(self, command, *, allowed, cleared=False, capacity=4194304, wrong_type=False):
        with tempfile.TemporaryDirectory(dir=REPO / "tmp") as directory:
            root = Path(directory)
            fixture = root / "misc.img"
            before = (command.ljust(32, b'\0') + TAIL)[:capacity]
            fixture.write_bytes(before)
            function = FUNCTION.replace("target=/dev/disk/by-partlabel/misc", "target=" + shlex.quote(str(fixture)))
            function = function.replace('test -b "$target"', 'test -f "$target"')
            function = function.replace("/tmp/sheng-bcb.", str(root / "snapshot."))
            kind = "wrong" if wrong_type else "82acc91f-357c-4a68-9c8f-689e1b1a23a1"
            prelude = f'''
set -eu
fail() {{ echo "$*" >&2; exit 1; }}
check_ufs_partition() {{ :; }}
check_ufs_disk() {{ :; }}
parent_disk() {{ echo /dev/sda; }}
sfdisk() {{ test "$*" = '--verify /dev/sda'; }}
blockdev() {{ stat -c %s {shlex.quote(str(fixture))}; }}
readlink() {{
 case "$2" in
  /sys/class/block/*) echo /sys/devices/platform/soc@0/1d84000.ufshc/host0/block/sda/sda11 ;;
  *) command readlink "$@" ;;
 esac
}}
blkid() {{
 case "$3" in PART_ENTRY_NAME) echo misc ;; PART_ENTRY_TYPE) echo {kind} ;; *) exit 1 ;; esac
}}
'''
            result = subprocess.run(["sh", "-c", prelude + function + "\nclear_boot_request"], capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, allowed, result.stderr)
            expected = bytes(32) + before[32:] if cleared else before
            self.assertEqual(fixture.read_bytes(), expected)

    def test_recovery_with_and_without_residual_bytes(self):
        self.check(b"boot-recovery", allowed=True, cleared=True)
        self.check(b"boot-recovery\0oader", allowed=True, cleared=True)

    def test_empty_command_preserves_residual_bytes(self):
        self.check(bytes(8) + b"-bootloader", allowed=True)

    def test_unknown_or_unterminated_command_is_rejected(self):
        self.check(b"unknown", allowed=False)
        self.check(b"boot-recovery!!!", allowed=False)

    def test_wrong_capacity_or_type_is_rejected(self):
        self.check(b"boot-recovery", allowed=False, capacity=1048576)
        self.check(b"boot-recovery", allowed=False, wrong_type=True)


if __name__ == "__main__":
    unittest.main()
