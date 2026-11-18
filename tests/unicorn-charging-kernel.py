#!/usr/bin/env python3
"""Compile real patched battmgr message paths with deterministic GLINK replies."""
import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


def function(source, name):
    match = re.search(r"(?m)^static [^\n]*\b" + re.escape(name) + r"\(", source)
    if not match:
        raise ValueError(f"missing function {name}")
    start = match.start()
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--headers", type=Path)
    args = parser.parse_args()
    source = (args.source / "drivers/power/supply/qcom_battmgr.c").read_text()
    header = ((args.headers or args.source) / "include/linux/power_supply.h").read_text()
    enums = ""
    for token in ("POWER_SUPPLY_HEALTH_UNKNOWN", "POWER_SUPPLY_USB_TYPE_UNKNOWN",
                  "POWER_SUPPLY_CHARGE_TYPE_UNKNOWN"):
        start = header.rindex("enum", 0, header.index(token))
        enums += header[start:header.index("};", start) + 2] + "\n"
    definitions = source[source.index("#define BATTMGR_CHEMISTRY_LEN"):source.index("static int qcom_battmgr_request(")]
    names = ["qcom_battmgr_request", "qcom_battmgr_bat_prop_to_fw",
             "qcom_battmgr_bat_prop_from_fw", "qcom_battmgr_unicorn_health",
             "qcom_battmgr_unicorn_usb_type", "qcom_battmgr_request_property",
             "unicorn_xm_transfer", "unicorn_xm_scalar", "unicorn_xm_vdm",
             "unicorn_xm_digest", "unicorn_xm_callback", "qcom_battmgr_notification",
             "qcom_battmgr_sm8350_callback", "qcom_battmgr_callback", "qcom_battmgr_pdr_notify",
             "unicorn_xm_store", "request_vdm_cmd_show", "request_vdm_cmd_store",
             "verify_digest_show", "verify_digest_store"]
    fixture = Path(__file__).with_suffix(".c").read_text()
    fixture = fixture.replace("/* DEFINITIONS */", enums + definitions)
    fixture = fixture.replace("/* FUNCTIONS */", "\n".join(function(source, n) for n in names))
    with tempfile.TemporaryDirectory(prefix="unicorn-charging-tests-") as directory:
        root = Path(directory)
        (root / "test.c").write_text(fixture)
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
            "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
            "-Wno-unused-parameter", "-g", "-O1", "-fsanitize=address,undefined",
            str(root / "test.c"), "-o", str(root / "test")], check=True)
        subprocess.run([str(root / "test")], check=True,
                       env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0"})


if __name__ == "__main__":
    main()
