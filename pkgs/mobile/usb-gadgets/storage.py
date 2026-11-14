"""Create a new, independent FAT32 USB disk image without replacing files."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def create(path, size_mib):
    if size_mib < 64:
        raise ValueError("FAT32 image must be at least 64 MiB")
    # Create in the same directory and publish atomically without replacement.
    import tempfile
    fd, temporary = tempfile.mkstemp(prefix=".usb-image-", dir=path.parent)
    try:
        os.ftruncate(fd, size_mib * 1024 * 1024)
        os.close(fd)
        fd = -1
        subprocess.run(["mkfs.fat", "-F", "32", "-n", "USB-SHARE", temporary], check=True)
        with open(temporary, "rb") as image:
            os.fsync(image.fileno())
        os.link(temporary, path)
    finally:
        if fd >= 0:
            os.close(fd)
        os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description="Create an independent FAT32 virtual USB disk")
    sub = parser.add_subparsers(dest="command", required=True)
    command = sub.add_parser("create")
    command.add_argument("path", type=Path)
    command.add_argument("--size-mib", type=int, default=2048)
    args = parser.parse_args()
    create(args.path, args.size_mib)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
