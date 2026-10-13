#!/usr/bin/env python3
"""Replace the charging UKI without deleting the previous image first.

The caller verifies the mounted ESP identity and available space. Keep this
file outside systemd-boot extraFiles, which deletes old files before copying.
"""
import os
from pathlib import Path
import shutil
import sys
import tempfile


def install(source: Path, esp: Path):
    directory = esp / "EFI/android-devices"
    directory.mkdir(parents=True, exist_ok=True)
    dest = directory / "charger.efi"
    fd, temporary = tempfile.mkstemp(prefix=".charger-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "wb") as out, source.open("rb") as src:
            shutil.copyfileobj(src, out)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, dest)
        dfd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: install-charger.py IMAGE VERIFIED_ESP_MOUNT")
    install(Path(sys.argv[1]), Path(sys.argv[2]))
