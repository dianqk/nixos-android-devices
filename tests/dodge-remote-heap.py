#!/usr/bin/env python3
"""Check the SM8750 ADSP heap reservation and optional historical fault PFN."""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, help="kernel source tree")
parser.add_argument("--dtb", type=Path, help="compiled Dodge DTB")
parser.add_argument("--console", type=Path, help="old private pstore console; not checked into Git")
parser.add_argument("--fault-pfn", type=lambda text: int(text, 0), help="PFN identified in the fault stack")
args = parser.parse_args()
if not args.source and not args.dtb:
    parser.error("--source or --dtb required")
if (args.console is None) != (args.fault_pfn is None):
    parser.error("--console and --fault-pfn must be supplied together")
if args.source:
    text = (args.source / "arch/arm64/boot/dts/qcom/sm8750.dtsi").read_text()
    block = re.search(r"adsp_rpc_remote_heap_mem: adsp-rpc-remote-heap \{(.*?)\n\s*\};", text, re.S)
    assert block, "Missing ADSP remote heap"
    assert re.search(r"\bno-map;", block[1]), "ADSP heap must not be in the linear map"
    assert not re.search(r"\breusable;", block[1]), "DSP-owned pages must not return to Linux/CMA"
    assert re.search(r"size\s*=\s*<0x0\s+0xc00000>", block[1]), "Unexpected remote-heap size"
if args.dtb:
    node = "/reserved-memory/adsp-rpc-remote-heap"
    subprocess.run(["fdtget", str(args.dtb), node, "no-map"], check=True, stdout=subprocess.DEVNULL)
    result = subprocess.run(["fdtget", str(args.dtb), node, "reusable"], capture_output=True)
    assert result.returncode != 0, "Compiled DTB still makes the heap reusable"
if args.console:
    text = args.console.read_text()
    match = re.search(r"OF: reserved mem: (0x[0-9a-f]+)\.\.(0x[0-9a-f]+)[^\n]*adsp-rpc-remote-heap", text)
    assert match, "No original boot heap range captured"
    start, end = (int(value, 16) for value in match.groups())
    assert "map reusable adsp-rpc-remote-heap" in match[0], "Expected the original faulty reservation"
    pa = args.fault_pfn << 12  # Matched Dodge kernel uses 4KiB pages.
    assert start <= pa <= end, "Fault PFN lies outside the DSP-owned heap: hypothesis not confirmed"
    print(f"Historical fault PA {pa:#x} is inside ADSP heap {start:#x}..{end:#x}")
print("PASS: ADSP remote heap is no-map, non-reusable, with unchanged 12MiB reservation")
