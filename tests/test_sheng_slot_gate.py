#!/usr/bin/env python3
"""Check boot evidence parsing and fail-closed Sheng GPT identity checks."""
import os
from pathlib import Path
import shlex
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "devices/sheng/slot-gate.sh"
UUID_B = "2deb2024-85f3-2dc9-b275-e002c7377f19"
UUID_A = "3d6cae7d-3d7e-789d-4179-cdeb179401c5"
HARNESS = r'''
fail() { echo "$*" >&2; exit 1; }
readlink() {
  case "$2" in
    /dev/disk/by-partlabel/vbmeta_b) echo /dev/sde47 ;;
    /sys/class/block/sde47) echo "$UFS_PATH" ;;
    *) exit 1 ;;
  esac
}
blkid() {
  case "$3" in
    PART_ENTRY_NAME) echo "$GPT_LABEL" ;;
    PART_ENTRY_UUID) echo "$GPT_UUID" ;;
    *) exit 1 ;;
  esac
}
test() {
  if command test "$1" = -b; then
    command test "$BLOCK_PRESENT" = yes
  else
    command test "$@"
  fi
}
'''


class SlotGate(unittest.TestCase):
    def check(self, args="", bootconfig="", *, valid=True, **overrides):
        env = dict(os.environ, GPT_LABEL="vbmeta_b", GPT_UUID=UUID_B,
                   UFS_PATH="/sys/devices/platform/soc@0/1d84000.ufshc/host0/block/sde/sde47",
                   BLOCK_PRESENT="yes")
        env.update(overrides)
        script = HARNESS + "\n. " + shlex.quote(str(SCRIPT))
        script += "\nsheng_check_boot_slot " + shlex.quote(args) + " " + shlex.quote(bootconfig)
        result = subprocess.run(["sh", "-c", script], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_explicit_slot(self):
        self.check("androidboot.slot_suffix=_b")
        self.check(bootconfig='androidboot.slot_suffix = "_b"')
        self.check("", valid=False)
        self.check("androidboot.slot_suffix=_a", valid=False)
        self.check("androidboot.slot_suffix=_b boot.slot_suffix=_a", valid=False)
        self.check("boot.slot_suffix=_b", 'androidboot.slot_suffix = "_a"', valid=False)

    def test_live_bootloader_vbmeta(self):
        self.check(f"androidboot.vbmeta.device=PARTUUID={UUID_B}")
        self.check(f"androidboot.vbmeta.device=PARTUUID={UUID_B.upper()}")
        self.check(f"androidboot.vbmeta.device=PARTUUID={UUID_A}", valid=False)
        self.check(f"boot.slot_suffix=_a androidboot.vbmeta.device=PARTUUID={UUID_B}", valid=False)
        self.check(f"boot.slot_suffix=_b androidboot.vbmeta.device=PARTUUID={UUID_A}", valid=False)
        self.check(f"androidboot.vbmeta.device=PARTUUID={UUID_B} androidboot.vbmeta.device=PARTUUID={UUID_A}", valid=False)

    def test_invalid_metadata(self):
        for value in ("PARTUUID=", "PARTUUID=../vbmeta_b", "/dev/sde47", "PARTUUID=1234"):
            with self.subTest(value=value):
                self.check(f"boot.slot_suffix=_b androidboot.vbmeta.device={value}", valid=False)
        for overrides in ({"GPT_LABEL": "vbmeta_a"}, {"GPT_UUID": UUID_A},
                          {"UFS_PATH": "/sys/devices/other/block/sde47"},
                          {"BLOCK_PRESENT": "no"}):
            with self.subTest(overrides=overrides):
                self.check(f"androidboot.vbmeta.device=PARTUUID={UUID_B}", valid=False, **overrides)


if __name__ == "__main__":
    unittest.main()
