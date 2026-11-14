#!/usr/bin/env python3
"""Exercise real gadget TTY open/close callbacks with allocation and port failures.

Pass a kernel tree with the evaluated patch queue applied. The host-side fakes
check cleanup, reference counts and lock balance; they do not emulate USB IRQs
or prove the absence of port lifetime races.
"""

import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


def function(source, name):
    match = re.search(
        r"(?m)^static (?:int|void) " + re.escape(name) + r"\([^;]*?\)\s*\{",
        source,
        re.S,
    )
    if not match:
        raise ValueError(f"missing source function: {name}")
    opening = source.index("{", match.start())
    depth = 0
    tokens = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*.*?\*/|//[^\n]*|[{}]'
    for token in re.finditer(tokens, source[opening:], re.S):
        if token.group() == "{":
            depth += 1
        elif token.group() == "}":
            depth -= 1
            if depth == 0:
                return source[match.start():opening + token.end()] + "\n"
    raise ValueError(f"unterminated source function: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    source = (args.source / "drivers/usb/gadget/function/u_serial.c").read_text()
    fixture = Path(__file__).with_suffix(".c").read_text()
    marker = "/* @USB_SERIAL_FUNCTIONS@ */"
    if fixture.count(marker) != 1:
        raise ValueError("invalid fixture marker")
    fixture = fixture.replace(marker, "\n".join(
        function(source, name)
        for name in ["gs_open", "gs_close_flush_done", "gs_close"]
    ))
    with tempfile.TemporaryDirectory(prefix="usb-serial-") as directory:
        source_path = Path(directory) / "lifecycle.c"
        executable = Path(directory) / "lifecycle"
        source_path.write_text(fixture)
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
            "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
            "-Wno-unused-parameter", str(source_path), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
