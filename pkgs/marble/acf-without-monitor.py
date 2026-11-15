# SPDX-License-Identifier: MIT
"""Drop the ACF_SEC_TYPE_MONITOR sections of an Awinic ACF file.

Stock HyperOS ships aw882xx_acf.bin (header v1, 96-byte directory entries)
with one register profile per scene and one monitor section per amplifier.
The monitor sections configure the vendor HAL's battery/temperature monitor,
which the mainline aw88261 driver does not implement. The output keeps the
header (with the new directory size and count), the remaining directory
entries in order and their data, packed after the directory.
"""
import struct
import sys

HEADER_SIZE = 80
ENTRY_SIZE = 96
ACF_SEC_TYPE_MONITOR = 10

source, target = sys.argv[1:]
data = open(source, "rb").read()
directory_size, count, directory_offset, header_version = struct.unpack_from(
    "<IIII", data, 52
)
if header_version != 0x01000000 or directory_offset != HEADER_SIZE:
    sys.exit("unexpected ACF header")
if directory_size != count * ENTRY_SIZE:
    sys.exit("unexpected ACF directory size")

entries = [
    bytearray(data[directory_offset + i * ENTRY_SIZE : directory_offset + (i + 1) * ENTRY_SIZE])
    for i in range(count)
]
kept = [e for e in entries if struct.unpack_from("<I", e, 28)[0] != ACF_SEC_TYPE_MONITOR]
offset = HEADER_SIZE + len(kept) * ENTRY_SIZE
payload = []
for entry in kept:
    size, old_offset = struct.unpack_from("<II", entry, 32)
    if old_offset + size > len(data):
        sys.exit("ACF section outside the file")
    payload.append(data[old_offset : old_offset + size])
    struct.pack_into("<I", entry, 36, offset)
    offset += size

header = bytearray(data[:HEADER_SIZE])
struct.pack_into("<II", header, 52, len(kept) * ENTRY_SIZE, len(kept))
with open(target, "wb") as output:
    output.write(bytes(header) + b"".join(kept) + b"".join(payload))
