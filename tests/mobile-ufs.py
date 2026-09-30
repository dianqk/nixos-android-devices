#!/usr/bin/env python3
"""Exercise the UFS oneshot against files, including missing/failed sysfs writes."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
(repo / "tmp").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="ufs-test-", dir=repo / "tmp") as scratch:
    root = Path(scratch)
    (root / "power").mkdir()
    for name in ("power/control", "clkgate_enable", "clkscale_enable"):
        (root / name).write_text("old\n")
    script = repo / "modules/devices/polaris/ufs-safe-mode.sh"
    subprocess.run(["bash", str(script), str(root)], check=True)
    assert (root / "power/control").read_text() == "on\n"
    assert (root / "clkgate_enable").read_text() == "0\n"
    assert (root / "clkscale_enable").read_text() == "0\n"
    (root / "clkgate_enable").unlink()
    (root / "clkgate_enable").mkdir()
    assert subprocess.run(["bash", str(script), str(root)], capture_output=True).returncode != 0
    (root / "clkscale_enable").unlink()
    # Keep the real bounded loop while substituting elapsed time only.
    result = subprocess.run(["bash", "-c", 'sleep() { :; }; export -f sleep; bash "$1" "$2"',
                             "test", str(script), str(root)], capture_output=True)
    assert result.returncode != 0 and b"30 seconds" in result.stderr
print("PASS: UFS values, write failure, bounded missing-device failure")
