"""Build-time validation/packaging of Aurora's unmodified OEM radio payloads."""
import argparse
import hashlib
from pathlib import Path
import struct


def nvm_tags(data):
    if len(data) not in (10008, 10020) or int.from_bytes(data[:4], "little") != ((len(data) - 4) << 8 | 2):
        raise ValueError("expected Aurora Hamilton type-2 NVM, 10008 or 10020 bytes")
    tags = {}
    pos = 4
    while pos < len(data):
        if pos + 12 > len(data):
            raise ValueError("truncated NVM tag header")
        tag, size, _, _ = struct.unpack_from("<HHII", data, pos)
        pos += 12
        if tag in tags or pos + size > len(data):
            raise ValueError("duplicate or truncated NVM tag")
        tags[tag] = data[pos:pos + size]
        pos += size
    for tag, size in {39: 61, 87: 160, 217: 80, 220: 228, 249: 10}.items():
        if len(tags.get(tag, b"")) != size:
            raise ValueError(f"unexpected NVM tag {tag} length")
    return tags


def ie(kind, data):
    return struct.pack("<II", kind, len(data)) + data + bytes(-len(data) % 4)


def board_container(data, board):
    # The PCI/QMI key is observed on Aurora; no generic board.bin fallback.
    key = (b"bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,"
           b"subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255")
    # Keep board data and regulatory data from the same validated OEM release.
    known_pairs = {
        ("bb4ac221eb966848dd7aa7d31b2dc659d7ff12e651eec363c4ed2b0068867062",
         "237fc60976e5eb383ef0832e67d530d8b032e08e974fbe88a35f25c8c5784210"),
        ("f12339e05373fdaef7a6c548f60d194caf9f846c3be2506f8a0dcd14ac40fb37",
         "a99345e3614b7b5ebb2cc5391a48041f7d49abfb488e29f4a27cf4a8ff269425"),
    }
    if (hashlib.sha256(board).hexdigest(), hashlib.sha256(data).hexdigest()) not in known_pairs:
        raise ValueError("expected a matched Aurora N1 board/REGDB pair")
    magic = b"QCA-ATH12K-BOARD\x00"
    return (magic + bytes(-len(magic) % 4)
            + ie(0, ie(0, key) + ie(1, board))
            + ie(1, ie(0, key) + ie(1, data)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["nvm", "board"])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--bdf", type=Path)
    args = parser.parse_args()
    data = args.input.read_bytes()
    if args.mode == "nvm":
        nvm_tags(data)
    else:
        if args.output is None or args.bdf is None:
            parser.error("board requires an output and --bdf")
        args.output.write_bytes(board_container(data, args.bdf.read_bytes()))


if __name__ == "__main__":
    main()
