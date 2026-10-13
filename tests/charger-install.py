#!/usr/bin/env python3
"""Exercise atomic UKI replacement and failure preservation without a device."""
import importlib.util
import os
from pathlib import Path
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "modules/mobile/install-charger.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    esp = root / "esp"
    source = root / "new.efi"
    source.write_bytes(b"new UKI" * 4096)
    module.install(source, esp)
    dest = esp / "EFI/android-devices/charger.efi"
    assert dest.read_bytes() == source.read_bytes()
    dest.write_bytes(b"previous complete UKI")
    with patch.object(module.shutil, "copyfileobj", side_effect=OSError("read failure")):
        try:
            module.install(source, esp)
        except OSError:
            pass
        else:
            raise AssertionError("expected copy failure")
    assert dest.read_bytes() == b"previous complete UKI"
    with patch.object(module.os, "fsync", side_effect=OSError("flush failure")):
        try:
            module.install(source, esp)
        except OSError:
            pass
        else:
            raise AssertionError("expected fsync failure")
    assert dest.read_bytes() == b"previous complete UKI"
    assert list(dest.parent.iterdir()) == [dest]
    with patch.object(module.os, "replace", side_effect=OSError("rename failure")):
        try:
            module.install(source, esp)
        except OSError:
            pass
        else:
            raise AssertionError("expected rename failure")
    assert dest.read_bytes() == b"previous complete UKI"
    assert list(dest.parent.iterdir()) == [dest]
    operations = []
    original_fsync, original_replace = os.fsync, os.replace
    def fsync(fd):
        operations.append("fsync")
        original_fsync(fd)
    def replace(src, dst):
        assert dest.read_bytes() == b"previous complete UKI"
        operations.append("replace")
        original_replace(src, dst)
    with patch.object(module.os, "fsync", fsync), patch.object(module.os, "replace", replace):
        module.install(source, esp)
    assert operations == ["fsync", "replace", "fsync"]
    assert dest.read_bytes() == source.read_bytes()
print("charger installer: initial install, atomic replace, copy/flush failure checks passed")
