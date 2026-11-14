"""Owned configfs gadgets. The Rust manager alone binds/unbinds the UDC."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys
import time

import touch

ROOT = Path("/sys/kernel/config/usb_gadget")
RUN = Path("/run/usb-signaller")
KINDS = {"touch": ("hid.touch", 0x0106), "storage": ("mass_storage.disk", 0x0107),
         "uvc": ("uvc.video", 0x0108)}


def config():
    return json.loads(Path(os.environ.get("USB_GADGET_CONFIG", "/etc/usb-signaller/gadgets.json")).read_text())


def gadget(kind):
    return ROOT / ("usb-signaller-" + kind)


def put(path, value):
    if isinstance(value, bytes):
        path.write_bytes(value)
    else:
        path.write_text(str(value) + "\n")


def link(target, name):
    name.symlink_to(target)


def uvc_format(source):
    return "mjpeg" if source["type"] == "libcamera" else "uncompressed"


def prepare_uvc(function, source):
    fmt = uvc_format(source)
    # One advertised format/size/rate, matching the configured source. UVC
    # hosts are entitled to select every advertised format.
    frame = function / "streaming" / fmt / "video" / "480p"
    frame.mkdir(parents=True)
    for name, value in {"wWidth": 640, "wHeight": 480,
                        "dwMinBitRate": 640 * 480 * 16 * 30,
                        "dwMaxBitRate": 640 * 480 * 16 * 30,
                        "dwMaxVideoFrameBufferSize": 640 * 480 * 2,
                        "dwDefaultFrameInterval": 333333,
                        "dwFrameInterval": 333333}.items():
        put(frame / name, value)
    header = function / "streaming/header/h"
    header.mkdir()
    link(frame.parent, header / "format")
    # f_uvc requires all three descriptor sets even on an HS-only controller.
    # Runtime refuses full-speed links: VGA30 needs high-speed bandwidth.
    for speed in ["fs", "hs", "ss"]:
        link(header, function / "streaming/class" / speed / "h")
    control = function / "control/header/h"
    control.mkdir()
    link(control, function / "control/class/fs/h")
    link(control, function / "control/class/ss/h")
    put(function / "streaming_interval", 1)
    put(function / "streaming_maxpacket", 3072)


def prepare(kind, settings):
    root = gadget(kind)
    root.mkdir()  # Existing or foreign instances must first be cleaned by owner.
    function_name, pid = KINDS[kind]
    strings = root / "strings/0x409"
    strings.mkdir()
    for name, value in {"idVendor": "0x1d6b", "idProduct": hex(pid),
                        "bcdUSB": "0x0200", "max_speed": "high-speed"}.items():
        # configfs calls this attribute max_speed (underscore).
        put(root / name, value)
    for name, value in {"manufacturer": "Linux", "product": "USB " + kind,
                        "serialnumber": settings["serial"]}.items():
        put(strings / name, value)
    if kind == "uvc":
        # UVC uses an Interface Association Descriptor (control + streaming).
        for name, value in {"bDeviceClass": 0xef, "bDeviceSubClass": 2,
                            "bDeviceProtocol": 1}.items():
            put(root / name, value)
    function = root / "functions" / function_name
    function.mkdir()
    if kind == "touch":
        for name, value in {"protocol": 0, "subclass": 0, "report_length": touch.REPORT_LENGTH,
                            "report_desc": touch.descriptor()}.items():
            put(function / name, value)
    elif kind == "storage":
        for name, value in {"removable": 1, "ro": int(settings["storage"]["readOnly"]),
                            "nofua": 0}.items():
            put(function / "lun.0" / name, value)
    else:
        prepare_uvc(function, settings["uvc"])
    configuration = root / "configs/c.1"
    configuration.mkdir()
    description = configuration / "strings/0x409"
    description.mkdir()
    put(description / "configuration", "USB " + kind)
    put(configuration / "MaxPower", 250)
    link(function, configuration / function_name)


def remove_if_present(path):
    try:
        path.unlink() if path.is_symlink() else path.rmdir()
    except FileNotFoundError:
        pass


def cleanup(kind):
    root = gadget(kind)
    if root.exists() and (root / "UDC").read_text().strip():
        raise RuntimeError("Refusing to delete a bound gadget")
    (RUN / (kind + ".ready")).unlink(missing_ok=True)
    if kind == "uvc":
        (RUN / "uvc-source.ready").unlink(missing_ok=True)
    elif kind == "touch":
        Path(touch.SOCKET).unlink(missing_ok=True)
    if not root.exists():
        return
    # configfs attributes and default groups are kernel-owned: never unlink
    # them. Only remove the links/groups this implementation creates.
    configuration = root / "configs/c.1"
    remove_if_present(configuration / KINDS[kind][0])
    remove_if_present(configuration / "strings/0x409")
    remove_if_present(configuration)
    function = root / "functions" / KINDS[kind][0]
    if kind == "uvc" and function.exists():
        for path in ["streaming/class/fs/h", "streaming/class/hs/h", "streaming/class/ss/h",
                     "control/class/fs/h", "control/class/ss/h",
                     "streaming/header/h/format", "streaming/header/h", "control/header/h"]:
            remove_if_present(function / path)
        for fmt in ["uncompressed", "mjpeg"]:
            remove_if_present(function / "streaming" / fmt / "video/480p")
            remove_if_present(function / "streaming" / fmt / "video")
    remove_if_present(function)
    remove_if_present(root / "strings/0x409")
    remove_if_present(root)


def notify(message):
    address = os.environ.get("NOTIFY_SOCKET")
    if address:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.connect("\0" + address[1:] if address.startswith("@") else address)
            sock.sendall(message.encode())


def ready(kind):
    RUN.mkdir(exist_ok=True)
    # Include /proc starttime so a stale file or reused PID cannot imply health.
    start = Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()[19]
    (RUN / (kind + ".ready")).write_text(f"{os.getpid()} {start}\n")
    notify("READY=1")


def hid_node(function):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        dev = function / "dev"
        if dev.exists():
            number = dev.read_text().strip()
            path = Path("/sys/dev/char") / number
            node = Path("/dev") / path.resolve().name
            if node.exists():
                return str(node)
        time.sleep(0.02)
    raise RuntimeError("Owned gadget device node did not appear")


def open_image(filename, read_only):
    path = Path(filename)
    if path.is_symlink():
        raise ValueError("Storage image must not be a symlink")
    fd = os.open(path, (os.O_RDONLY if read_only else os.O_RDWR) | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size < 512 or info.st_size % 512:
            raise ValueError("Storage requires a nonempty regular image aligned to 512 bytes")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Refuse *any* loop attachment, including unmounted devices and offsets.
        result = subprocess.run(["losetup", "--associated", f"/proc/{os.getpid()}/fd/{fd}"],
                                check=True, text=True, capture_output=True)
        if result.stdout.strip():
            raise ValueError("Image is attached to a local loop device")
        return fd
    except BaseException:
        os.close(fd)
        raise


def run(kind, settings):
    stopping = False

    def stop(_sig, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    function = gadget(kind) / "functions" / KINDS[kind][0]
    try:
        if kind == "touch":
            touch.serve(hid_node(function), settings["controlGroup"],
                        lambda: ready(kind), lambda: stopping)
        elif kind == "storage":
            storage = settings["storage"]
            fd = open_image(storage["image"], storage["readOnly"])
            try:
                # Bind the verified inode, not a path another process can replace.
                put(function / "lun.0/file", f"/proc/{os.getpid()}/fd/{fd}")
                ready(kind)
                while not stopping:
                    time.sleep(0.1)
            finally:
                put(function / "lun.0/file", "")
                if not storage["readOnly"]:
                    os.fsync(fd)
                os.close(fd)
        else:
            source = settings["uvc"]
            source_ready = RUN / "uvc-source.ready"
            source_ready.unlink(missing_ok=True)
            args = ["uvc-gadget"]
            if source["type"] == "v4l2":
                args += ["-d", source["device"]]
            elif source["type"] == "libcamera":
                args += ["-c", source["camera"]]
            # Let upstream resolve the video node by the exact configfs owner,
            # not by a potentially ambiguous video device name/index.
            args += ["usb-signaller-uvc/functions/uvc.video"]
            # A patched upstream process notifies after parsing configfs and
            # validating its source, before entering the UVC event loop.
            process = subprocess.Popen(args, env={**os.environ,
                "UVC_READY_FILE": str(source_ready)})
            try:
                deadline = time.monotonic() + 10
                while not stopping:
                    code = process.poll()
                    if code is not None:
                        raise RuntimeError(f"uvc-gadget exited ({code})")
                    if source_ready.exists():
                        ready(kind)
                        break
                    if time.monotonic() > deadline:
                        raise TimeoutError("UVC source did not become ready")
                    time.sleep(0.02)
                while not stopping:
                    speed = Path("/sys/class/udc") / settings["udc"] / "current_speed"
                    if speed.exists() and speed.read_text().strip() in ["full-speed", "low-speed"]:
                        raise RuntimeError("UVC VGA30 requires a USB high-speed connection")
                    if process.poll() is not None:
                        raise RuntimeError("UVC backend exited")
                    time.sleep(0.1)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                source_ready.unlink(missing_ok=True)
    finally:
        (RUN / (kind + ".ready")).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["prepare", "cleanup", "run"])
    parser.add_argument("kind", choices=KINDS)
    args = parser.parse_args()
    if args.action == "cleanup":
        cleanup(args.kind)
    else:
        globals()[args.action](args.kind, config())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
