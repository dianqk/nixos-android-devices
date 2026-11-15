#!/usr/bin/env python3
"""Prepare Marble's stock SSC defaults for the shared registry generator.

The stock sns_reg_config also selects on soc0 platform_subtype_id, which
mkSSCRegistry does not read: files restricted to other subtypes are dropped
and the matching filter is removed. Files without a "config" selector must be
named in --exclude (not registry data, e.g. the Xiaomi light HAL's
lightSensorConfig.json); any other file is copied unchanged.
"""
import argparse
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--platform-subtype-id", required=True)
parser.add_argument("--exclude", action="append", default=[])
args = parser.parse_args()

args.output.mkdir(parents=True)
names = {file.name for file in args.source.glob("*.json")}
missing = set(args.exclude) - names
if missing:
    raise SystemExit(f"excluded files not present: {sorted(missing)}")
for file in sorted(args.source.glob("*.json")):
    if file.name in args.exclude:
        continue
    data = json.loads(file.read_text())
    if "config" not in data:
        raise SystemExit(f"{file.name}: no selector and not excluded")
    subtypes = data["config"].pop("platform_subtype_id", None)
    if subtypes is None:
        shutil.copyfile(file, args.output / file.name)
    elif args.platform_subtype_id in subtypes:
        (args.output / file.name).write_text(json.dumps(data, indent=2) + "\n")
