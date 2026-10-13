#!/usr/bin/env python3
"""Align an unchanged arm64 Image behind a legacy bootloader entry offset.

The direct-boot wrapper preserves x0-x3 and branches to the embedded Image.
It is not an EFI executable; use the original Image for UEFI boot.
Based on the packaging approach suggested by Will Deacon and Ard Biesheuvel:
https://lore.kernel.org/all/20251006-arm64-text-offset-v1-1-bf0e8a27383b@oss.qualcomm.com/
"""

import argparse
import gzip
from pathlib import Path
import struct

ALIGNMENT = 2 * 1024 * 1024


def wrap_image(image, load_offset):
    if not 0 < load_offset < ALIGNMENT or load_offset % 4096:
        raise ValueError("load offset must be a nonzero 4 KiB multiple below 2 MiB")
    if len(image) < 64 or image[56:60] != b"ARM\x64":
        raise ValueError("input is not an arm64 Image")
    text_offset, image_size, flags = struct.unpack_from("<QQQ", image, 8)
    if text_offset != 0 or image_size < len(image) or flags & 1:
        raise ValueError("expected a zero-offset little-endian Image with a valid memory size")
    padding = ALIGNMENT - load_offset
    header = bytearray(padding)
    # B immediate: branch from wrapper offset zero to the real kernel header.
    # No stack, memory relocation or scratch register is needed.
    struct.pack_into("<IIQQQ", header, 0,
                     0x14000000 | (padding // 4), 0xD503201F,
                     load_offset, image_size + padding, flags)
    header[56:60] = b"ARM\x64"
    return header + image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--load-offset", type=lambda v: int(v, 0), required=True)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.input.read_bytes()
    compressed = source.startswith(b"\x1f\x8b")
    if compressed:
        source = gzip.decompress(source)
    result = wrap_image(source, args.load_offset)
    if compressed:
        result = gzip.compress(result, mtime=0)
    args.output.write_bytes(result)


if __name__ == "__main__":
    main()
