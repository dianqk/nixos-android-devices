#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Execute locked nixpkgs' real extra-files cleanup around the bootstrap hook."""
import ast
import importlib.util
import os
import re
import pathlib
import sys
import tempfile

script, builder = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("bootstrap", script)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)
tree = ast.parse(builder.read_text())
functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ("remove_extra_files", "garbage_collect")]
with tempfile.TemporaryDirectory(prefix="boot-choice-nixos-lifecycle-") as tmp:
    root = pathlib.Path(tmp)
    root.chmod(0o700)
    helper = root / bootstrap.HELPER
    menu = root / bootstrap.MENU
    receipt = root / bootstrap.EVIDENCE[0]
    for path, data in [(helper, b"native B"), (menu, b"native menu B"), (receipt, b"opaque native receipt B")]:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.write_bytes(data)
    original = [p.read_bytes() for p in (helper, menu, receipt)]
    source, entry = root / "source", root / "menu"
    entry.write_bytes(b"Nix menu A")
    tracker = root / "EFI/nixos/.extra-files"
    for generation in ("generation-new", "rollback", "disable"):
        marker = tracker / "loader/entries/other-action.conf"
        marker.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        marker.touch()
        other = root / "loader/entries/other-action.conf"
        other.write_bytes(b"unrelated tracked entry")
        old_entry = root / "loader/entries/nixos-obsolete.conf"
        old_entry.write_bytes(b"old Nix generation")
        ns = {"BOOT_MOUNT_POINT": root, "NIXOS_DIR": pathlib.Path("EFI/nixos"), "BootFileList": list, "Path": pathlib.Path, "os": os, "re": re}
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(builder), "exec"), ns)
        ns["garbage_collect"]([])
        assert not old_entry.exists()
        ns["remove_extra_files"]()
        assert not other.exists()
        source.write_bytes(generation.encode())
        if generation != "disable":
            assert "untouched" in bootstrap.deploy(root, source, entry)
        assert original == [p.read_bytes() for p in (helper, menu, receipt)]
    # Positive absence only, including a symlink receipt; escaped parent refuses.
    receipt.unlink()
    receipt.symlink_to(root / "absent")
    assert "untouched" in bootstrap.deploy(root, source, entry)
    receipt.unlink()
    devices = root / "EFI/android-devices"
    devices.rename(devices.with_name("saved"))
    devices.symlink_to("saved", target_is_directory=True)
    try:
        bootstrap.deploy(root, source, entry)
    except OSError:
        pass
    else:
        raise AssertionError("symlink parent accepted")
print("actual upstream generation GC + extra-files cleanup: update/rollback/disable preserve native helper/menu/receipt; symlink guard passed")
