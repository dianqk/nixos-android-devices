#!/usr/bin/env python3
"""Compile the actual repeater callbacks with injected I2C/power faults."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
args = parser.parse_args()
source = (args.source / "drivers/phy/phy-nxp-ptn3222.c").read_text()
start = source.index("static int ptn3222_apply_tx_control(")
end = source.index("static const struct phy_ops", start)
callbacks = source[start:end]
fixture = Path(__file__).with_suffix(".c").read_text()
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)
    (path / "callbacks.h").write_text(callbacks)
    (path / "fixture.c").write_text(fixture)
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-I", tmp,
                    str(path / "fixture.c"), "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True)
