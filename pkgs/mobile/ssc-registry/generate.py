#!/usr/bin/env python3
"""Select OEM defaults, merge equal groups and split SSC registry references.

The wire/file layout follows Qualcomm SNS JSON and hexagonrpc v0.5.0's
sscregistrygen (https://gitlab.com/sdm845-mainline/hexagonrpc/-/tree/0.5.0).
Conflicting values are errors; input order never chooses hardware policy.
"""
import argparse
import copy
import json
import os
import stat
import tempfile
from pathlib import Path
import re


def wire_order(value):
    """The SSC streaming parser needs owner/type/version before their data."""
    if not isinstance(value, dict):
        return value
    keys = [key for key in ("owner", "type", "ver", "data") if key in value]
    keys += [key for key in value if key not in keys]
    return {key: wire_order(value[key]) for key in keys}


def dumps(value):
    return json.dumps(wire_order(value), separators=(",", ":")) + "\n"


def normalize_state(state):
    """Reorder existing registry fields without replacing calibration values."""
    registry = state / "registry/registry"
    if not registry.is_dir():
        return
    for file in sorted(registry.iterdir()):
        if file.is_symlink() or not file.is_file():
            continue
        original = file.read_text()
        # Newer SSC firmware writes this directory marker beside JSON groups.
        if file.name == "DIR" and original == "DIR":
            continue
        ordered = dumps(json.loads(original))
        if original == ordered:
            continue
        metadata = file.stat()
        fd, temporary = tempfile.mkstemp(prefix=".ssc-order-", dir=registry.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(ordered)
                stream.flush()
                os.fchmod(stream.fileno(), stat.S_IMODE(metadata.st_mode))
                if (metadata.st_uid, metadata.st_gid) != (os.geteuid(), os.getegid()):
                    os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
                os.fsync(stream.fileno())
            os.replace(temporary, file)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def merge(target, incoming, path=""):
    for key, value in incoming.items():
        if key not in target:
            target[key] = copy.deepcopy(value)
        elif target[key] == value:
            continue
        elif isinstance(target[key], dict) and isinstance(value, dict):
            merge(target[key], value, path + key + ".")
        else:
            raise ValueError(f"conflicting registry value: {path}{key}")


def split(name, group, result):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in (".", ".."):
        raise ValueError(f"unsafe registry group: {name!r}")
    fields = {}
    for key, value in group.items():
        if key.startswith("."):
            split(name + key, value, result)
            fields[key[1:]] = {"type": "grp", "ver": "0", "data": ""}
        else:
            fields[key] = value
    if name in result and result[name] != fields:
        raise ValueError(f"conflicting flattened group: {name}")
    result[name] = fields


def generate(source, output, platform, soc_id, version, layout="group"):
    if layout not in ("group", "file-group"):
        raise ValueError(f"unsupported registry layout: {layout}")
    output.mkdir(parents=True, exist_ok=False)
    configs = output / "etc/sensors/config"
    registry = output / "seed/registry/registry"
    configs.mkdir(parents=True)
    registry.mkdir(parents=True)
    groups = {}
    file_groups = {}
    selected = []
    for file in sorted(source.glob("*.json")):
        data = json.loads(file.read_text())
        filters = data.pop("config", {})
        if set(filters) - {"hw_platform", "soc_id"}:
            raise ValueError(f"unsupported selection in {file}")
        if platform not in filters.get("hw_platform", [platform]):
            continue
        if soc_id not in filters.get("soc_id", [soc_id]):
            continue
        merge(groups, data)
        flattened = {}
        for name, group in data.items():
            split(name, group, flattened)
        file_groups[file.name] = flattened
        # Selection is resolved at build time, including on mainline systems
        # whose soc0 hw_platform string differs from the Android bootloader.
        (configs / file.name).write_text(dumps(data))
        selected.append(file.name)
    if not groups:
        raise ValueError("no matching sensor defaults")
    flattened = {}
    for name, group in groups.items():
        split(name, group, flattened)
    if layout == "group":
        for name, fields in sorted(flattened.items()):
            (registry / name).write_text(dumps({name: fields}))
    else:
        parsed = []
        for filename, entries in file_groups.items():
            for name, fields in sorted(entries.items()):
                target = f"{filename}.{name}"
                (registry / target).write_text(dumps({name: fields}))
                parsed.append(target)
        (registry.parent / "parsed_file_list.csv").write_text("\n".join(parsed) + "\n")
        (configs / "json.lst").write_text("\n".join(selected) + "\n")
    sensors = output / "etc/sensors"
    selectors = {"hw_platform": platform, "soc_id": soc_id}
    lines = [f"version={version}"]
    for name, value in selectors.items():
        (sensors / name).write_text(value + "\n")
        lines.append(f"file={name}=/vendor/etc/sensors/{name}")
    lines.append("file=output=/mnt/vendor/persist/sensors/registry/registry")
    if layout == "file-group":
        lines.append("file=input=json.lst")
    # Android property callbacks require a Bionic-only bridge. These optional
    # properties are absent in the observed registry and are not configured.
    (sensors / "sns_reg_config").write_text("\n".join(lines) + "\n")
    (output / "seed/registry/sns_reg_version").write_bytes(f"version={version}\0".encode())
    (output / "selected-configs.json").write_text(json.dumps(selected) + "\n")


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--normalize-state":
        normalize_state(Path(sys.argv[2]))
        sys.exit(0)
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--soc-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--layout", choices=("group", "file-group"), default="group")
    args = parser.parse_args()
    generate(args.source, args.output, args.platform, args.soc_id, args.version, args.layout)
