#!/usr/bin/env python3
"""Compile and exercise the actual Dodge memory-import helper with host libfdt.

Usage: python3 tests/uboot-dodge-memory.py PATCHED_UBOOT [ABL_DTB]
Set CFLAGS/LDFLAGS when libfdt headers or libraries need explicit paths.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve() / "arch/arm/mach-snapdragon/dodge.c"
with tempfile.TemporaryDirectory(prefix="uboot-dodge-memory-") as directory:
    work = Path(directory)
    (work / "asm").mkdir()
    (work / "asm/sections.h").write_text(
        "#define _start ((void *)dodge_test_image_start)\n"
        "#define __bss_start ((void *)dodge_test_bss_start)\n"
    )
    command = shlex.split(os.environ.get("CC", "cc")) + [
        "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", f"-I{work}",
        f'-DDODGE_HANDOFF_SOURCE="{source}"',
    ]
    command += shlex.split(os.environ.get("CFLAGS", ""))
    command += [str(Path(__file__).with_suffix(".c")), "-o", str(work / "test")]
    command += shlex.split(os.environ.get("LDFLAGS", "")) + ["-lfdt"]
    subprocess.run(command, check=True)
    subprocess.run([str(work / "test"), *sys.argv[2:]], check=True)
