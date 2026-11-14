"""USB HID touchscreen reports and a single-writer local JSON-lines API."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import select
import socket
import struct
import sys
import time

CONTACTS = 10
MAX_COORD = 32767
REPORT_LENGTH = 64
SOCKET = "/run/usb-signaller/touch.sock"
# linux/usb/g_hid.h: 72-byte ABI, including its explicit compatibility padding.
WRITE_GET_REPORT = 0x40486742


def descriptor():
    report = bytearray.fromhex("05 0d 09 04 a1 01 85 01")
    for _ in range(CONTACTS):
        report += bytes.fromhex(
            "09 22 a1 02 "  # Finger collection
            "09 42 15 00 25 01 75 01 95 01 81 02 "  # Tip Switch
            "75 07 95 01 81 03 "  # padding
            "09 51 15 00 25 09 75 08 95 01 81 02 "  # Contact ID
            "05 01 15 00 26 ff 7f 75 10 95 01 "
            "09 30 81 02 09 31 81 02 "  # absolute X/Y
            "05 0d c0"
        )
    report += bytes.fromhex(
        "09 54 15 00 25 0a 75 08 95 01 81 02 "  # Contact Count
        "09 56 15 00 27 ff ff 00 00 75 10 95 01 "
        "55 0c 66 01 10 81 02 "  # Scan Time, 100 microseconds
        "55 00 65 00 "
        "85 02 09 55 15 00 25 0a 75 08 95 01 b1 02 c0"
    )
    return bytes(report)


def feature_report():
    return struct.pack("=BBH64s4x", 2, 0, 2, bytes([2, CONTACTS]))


def integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{label} must be an integer in {low}..{high}")
    return value


class TouchState:
    def __init__(self):
        self.active = {}

    def frame(self, message, timestamp=None):
        if not isinstance(message, dict) or set(message) != {"contacts"}:
            raise ValueError('Expected {"contacts": [{"id": 0, "x": 0, "y": 0}, ...]}')
        contacts = message["contacts"]
        if not isinstance(contacts, list) or len(contacts) > CONTACTS:
            raise ValueError("contacts must be a list of at most ten contacts")
        new = {}
        for contact in contacts:
            if not isinstance(contact, dict) or set(contact) != {"id", "x", "y"}:
                raise ValueError("Each contact must have exactly id, x and y")
            ident = integer(contact["id"], 0, 9, "id")
            if ident in new:
                raise ValueError("Duplicate contact id")
            new[ident] = (integer(contact["x"], 0, MAX_COORD, "x"),
                          integer(contact["y"], 0, MAX_COORD, "y"))
        # Fixed slots let us include lift-off at its last position in the same
        # frame as newly pressed contacts. Count includes those lift-off records.
        records = bytearray()
        included = self.active.keys() | new.keys()
        for ident in range(CONTACTS):
            x, y = new.get(ident, self.active.get(ident, (0, 0)))
            records += struct.pack("<BBHH", int(ident in new), ident, x, y)
        ticks = int(time.monotonic() * 10000) if timestamp is None else timestamp
        # Valid records must precede unused records for Contact Count parsing.
        ordered = b"".join(records[i * 6:(i + 1) * 6] for i in sorted(included))
        ordered += bytes((CONTACTS - len(included)) * 6)
        result = bytes([1]) + ordered + struct.pack("<BH", len(included), ticks & 65535)
        self.active = new
        return result


def write_report(fd, report, timeout=0.5):
    deadline = time.monotonic() + timeout
    while True:
        try:
            if os.write(fd, report) != len(report):
                raise OSError("Short HID report write")
            return
        except BlockingIOError:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([], [fd], [], remaining)[1]:
                raise TimeoutError("USB host is not accepting touch reports")


def serve(device, group, ready, stopping):
    import grp
    state = TouchState()
    fd = os.open(device, os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client = None
    buffer = bytearray()
    path = Path(SOCKET)
    try:
        fcntl.ioctl(fd, WRITE_GET_REPORT, feature_report())
        path.unlink(missing_ok=True)
        server.bind(str(path))
        os.chmod(path, 0o660)
        os.chown(path, 0, grp.getgrnam(group).gr_gid)
        server.listen(4)
        server.setblocking(False)
        ready()
        while not stopping():
            readers, _, _ = select.select([server] + ([client] if client else []), [], [], 0.1)
            if client is not None and client in readers:
                try:
                    chunk = client.recv(4096)
                    if not chunk:
                        raise EOFError()
                    buffer.extend(chunk)
                    if len(buffer) > 16384:
                        raise ValueError("Touch request exceeds 16 KiB")
                    while b"\n" in buffer:
                        line, _, tail = buffer.partition(b"\n")
                        buffer[:] = tail
                        try:
                            # On write failure close the session; keep the new state
                            # so finally can send releases for a partially sent frame.
                            report = state.frame(json.loads(line))
                        except (ValueError, TypeError) as error:
                            client.sendall((json.dumps({"ok": False, "error": str(error)}) + "\n").encode())
                            continue
                        write_report(fd, report)
                        client.sendall(b'{"ok":true}\n')
                except (EOFError, OSError, ValueError, TimeoutError):
                    try:
                        write_report(fd, state.frame({"contacts": []}))
                    except (OSError, TimeoutError):
                        pass  # Detach may already have removed the endpoint.
                    client.close()
                    client = None
                    buffer.clear()
            if server in readers:
                incoming, _ = server.accept()
                incoming.settimeout(0.5)
                if client is not None:
                    try:
                        incoming.sendall(b'{"ok":false,"error":"Touch session busy"}\n')
                    except OSError:
                        pass
                    finally:
                        incoming.close()
                else:
                    client = incoming
                    buffer.clear()
    finally:
        try:
            write_report(fd, state.frame({"contacts": []}))
        except (OSError, TimeoutError):
            pass
        if client is not None:
            client.close()
        server.close()
        path.unlink(missing_ok=True)
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description="Send native USB touchscreen frames (coordinates 0..32767)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("stream", help="Read JSON contact frames from stdin; keep stdin open to hold contacts")
    click = sub.add_parser("tap", help="Press and release one touch contact")
    click.add_argument("x", type=int)
    click.add_argument("y", type=int)
    sub.add_parser("release", help="Send an empty frame in a new session")
    args = parser.parse_args()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(SOCKET)
        replies = client.makefile("rb")

        def send(frame):
            client.sendall((json.dumps(frame) + "\n").encode())
            response = json.loads(replies.readline())
            if not response.get("ok"):
                raise RuntimeError(response.get("error", "Touch request failed"))

        if args.command == "stream":
            for line in sys.stdin:
                send(json.loads(line))
                print('{"ok":true}', flush=True)
        elif args.command == "tap":
            send({"contacts": [{"id": 0, "x": args.x, "y": args.y}]})
            time.sleep(0.05)
        send({"contacts": []})


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(str(error))
