#!/usr/bin/env python3
"""Provision a verified runtime public address through Linux Bluetooth MGMT."""
import argparse
import os
from pathlib import Path
import re
import socket
import stat
import struct
import sys
import time

INDEX_NONE = 0xFFFF
READ_INDEX_LIST = 0x0003
READ_INFO = 0x0004
READ_UNCONF_INDEX_LIST = 0x0036
READ_CONFIG_INFO = 0x0037
SET_PUBLIC_ADDRESS = 0x0039
PUBLIC_ADDRESS = 2


class IdentityError(Exception):
    pass


def read_identity(filename):
    # A string filename is read only on the device, never during Nix evaluation.
    fd = os.open(filename, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
            raise IdentityError("identity must be a root-owned private regular file")
        data = os.read(fd, 33)
    finally:
        os.close(fd)
    if not re.fullmatch(rb"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\n?", data):
        raise IdentityError("identity must contain one colon-separated public address")
    address = bytes.fromhex(data.decode("ascii").strip().replace(":", ""))
    if not any(address) or address[0] & 1:
        raise IdentityError("identity must be a nonzero unicast public address")
    return address[::-1]  # MGMT bdaddr_t uses controller byte order.


def controller_index(compatible, sysfs=Path("/sys/class/bluetooth")):
    matches = []
    for hci in sysfs.glob("hci*"):
        if not re.fullmatch(r"hci[0-9]+", hci.name):
            continue
        device = (hci / "device").resolve()
        for parent in (device, *device.parents):
            try:
                values = (parent / "of_node/compatible").read_bytes().split(b"\0")
            except FileNotFoundError:
                continue
            if compatible.encode("ascii") in values:
                matches.append(int(hci.name[3:]))
                break
    if len(matches) > 1:
        raise IdentityError("multiple matching Bluetooth controllers")
    return matches[0] if matches else None


class Management:
    def __init__(self, sock, deadline, clock=time.monotonic):
        self.sock, self.deadline, self.clock = sock, deadline, clock

    def request(self, opcode, index=INDEX_NONE, payload=b""):
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise IdentityError("Bluetooth identity deadline expired")
        self.sock.settimeout(remaining)
        self.sock.sendall(struct.pack("<HHH", opcode, index, len(payload)) + payload)
        while True:
            remaining = self.deadline - self.clock()
            if remaining <= 0:
                raise IdentityError("Bluetooth identity deadline expired")
            self.sock.settimeout(remaining)
            frame = self.sock.recv(65541)
            if len(frame) < 6:
                raise IdentityError("short Bluetooth management event")
            event, target, size = struct.unpack_from("<HHH", frame)
            data = frame[6:]
            if size != len(data):
                raise IdentityError("invalid Bluetooth management event length")
            if target != index or event not in (1, 2):
                continue
            if len(data) < 3:
                raise IdentityError("short Bluetooth management command response")
            command, status = struct.unpack_from("<HB", data)
            if command != opcode:
                continue
            if status:
                raise IdentityError(f"Bluetooth management command 0x{opcode:04x} failed (status {status})")
            if event == 2:
                # These synchronous commands complete with CMD_COMPLETE.
                continue
            return data[3:]

    def indices(self, opcode):
        data = self.request(opcode)
        if len(data) < 2:
            raise IdentityError("short Bluetooth controller list")
        count, = struct.unpack_from("<H", data)
        if len(data) != 2 + 2 * count:
            raise IdentityError("invalid Bluetooth controller list")
        return struct.unpack_from(f"<{count}H", data, 2)


def provision(client, index, address, deadline, clock=time.monotonic, sleep=time.sleep):
    def pause():
        remaining = deadline - clock()
        if remaining <= 0:
            raise IdentityError("controller did not finish address configuration before deadline")
        sleep(min(0.2, remaining))

    def verify():
        data = client.request(READ_INFO, index)
        if len(data) < 17:
            raise IdentityError("short Bluetooth controller information")
        if data[:6] != address:
            raise IdentityError("configured controller address does not match identity file")

    # Never change the identity of an already configured controller.
    if index in client.indices(READ_INDEX_LIST):
        verify()
        return
    while index not in client.indices(READ_UNCONF_INDEX_LIST):
        if index in client.indices(READ_INDEX_LIST):
            verify()
            return
        pause()
    config = client.request(READ_CONFIG_INFO, index)
    if len(config) != 10:
        raise IdentityError("invalid Bluetooth configuration information")
    _, supported, missing = struct.unpack("<HII", config)
    if not supported & PUBLIC_ADDRESS or missing != PUBLIC_ADDRESS:
        raise IdentityError("controller requires configuration beyond its public address")
    result = client.request(SET_PUBLIC_ADDRESS, index, address)
    if result != bytes(4):
        raise IdentityError("controller still has missing configuration options")
    # CMD_COMPLETE precedes the asynchronous HCI_CONFIG power-on work. Wait for
    # the configured index and read back the actual address after that work.
    while index not in client.indices(READ_INDEX_LIST):
        pause()
    verify()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity-file", required=True)
    parser.add_argument("--board-compatible", required=True)
    parser.add_argument("--controller-compatible", required=True)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    try:
        if not 0 < args.timeout <= 60:
            raise IdentityError("timeout must be greater than zero and at most 60 seconds")
        board = Path("/proc/device-tree/compatible").read_bytes().split(b"\0")
        if args.board_compatible.encode("ascii") not in board:
            raise IdentityError("identity service does not match this board")
        address = read_identity(args.identity_file)
        deadline = time.monotonic() + args.timeout
        index = controller_index(args.controller_compatible)
        while index is None:
            if time.monotonic() >= deadline:
                raise IdentityError("matching Bluetooth controller did not appear before deadline")
            time.sleep(0.2)
            index = controller_index(args.controller_compatible)
        with socket.socket(socket.AF_BLUETOOTH, socket.SOCK_RAW | socket.SOCK_CLOEXEC,
                           socket.BTPROTO_HCI) as sock:
            sock.bind((INDEX_NONE, 3))  # HCI_CHANNEL_CONTROL
            provision(Management(sock, deadline), index, address, deadline)
        print("Bluetooth public address verified")
    except (IdentityError, OSError, ValueError):
        # Identity bytes and filenames are intentionally absent from errors.
        # Management errors carry only the command/status, never its payload.
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, IdentityError)
              else "Bluetooth identity runtime I/O failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
