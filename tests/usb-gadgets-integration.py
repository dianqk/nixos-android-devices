"""Runs only inside the disposable NixOS VM with dummy_hcd."""
import fcntl
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

ROOT = Path("/sys/kernel/config/usb_gadget")
BUS = ["busctl", "--json=short", "call", "com.meego.usb_moded", "/com/meego/usb_moded", "com.meego.usb_moded"]
assert Path("/sys/class/udc/dummy_udc.0").exists()


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def wait(predicate, seconds=15):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for emulated USB state")


def status():
    return json.loads(run(*BUS, "get_status"))["data"][0]


def mode(name, failure=False):
    run(*BUS, "set_mode", "s", name)
    def complete():
        state = status()
        return state if state.get("desired_mode") == name and state.get("busy") == "false" and (
            state.get("last_error") if failure else state.get("actual_mode") == name) else None
    try:
        result = wait(complete, 25)
    except AssertionError:
        raise AssertionError(f"Mode {name} did not complete: {status()}") from None
    if not failure:
        assert not result["last_error"], result
    return result


def usb_device():
    return next((p for p in Path("/sys/bus/usb/devices").glob("*")
                 if (p / "serial").exists() and (p / "serial").read_text().strip() == "usb-gadget-test"), None)


def child_device(class_name):
    device = usb_device()
    if device is None:
        return None
    return next((p for p in Path("/sys/class", class_name).glob("*")
                 if str(device.resolve()) + "/" in str(p.resolve())), None)


wait(lambda: status().get("actual_mode") == "developer_mode")
mode("hid_touch_mode")
event = wait(lambda: next((p for p in Path("/sys/class/input").glob("event*")
                           if usb_device() and str(usb_device().resolve()) + "/" in str(p.resolve())), None))
raw = wait(lambda: child_device("hidraw"))
run("udevadm", "settle")
assert "uaccess" in run("udevadm", "info", "--query=property", "--name=/dev/" + raw.name)
with open("/dev/" + raw.name, "r+b", buffering=0) as device:
    feature = bytearray([2, 0])
    fcntl.ioctl(device.fileno(), 0xc0024807, feature, True)
    assert feature == bytes([2, 10]), feature
fd = os.open("/dev/input/" + event.name, os.O_RDONLY | os.O_NONBLOCK)
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.connect("/run/usb-signaller/touch.sock")
    replies = client.makefile("rb")
    for contacts in [[{"id": 0, "x": 1234, "y": 5678}, {"id": 7, "x": 90, "y": 100}],
                     [{"id": 0, "x": 1400, "y": 5800}], []]:
        client.sendall((json.dumps({"contacts": contacts}) + "\n").encode())
        assert json.loads(replies.readline())["ok"]
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as other:
        other.connect("/run/usb-signaller/touch.sock")
        assert not json.loads(other.recv(4096))["ok"]
    client.sendall(b'{"contacts":[{"id":0,"x":-1,"y":10}]}\n')
    assert not json.loads(replies.readline())["ok"]
    events = b""
    until = time.monotonic() + 2
    while time.monotonic() < until:
        if select.select([fd], [], [], 0.1)[0]:
            events += os.read(fd, 65536)
    values = [(typ, code, value) for _, _, typ, code, value in struct.iter_unpack("llHHi", events)]
    assert (3, 0x35, 1234) in values, values  # ABS_MT_POSITION_X
    assert (3, 0x36, 5678) in values, values
    assert (3, 0x39, -1) in values, values   # ABS_MT_TRACKING_ID lift-off
    replies.close()
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.connect("/run/usb-signaller/touch.sock")
    client.sendall(b'{"contacts":[{"id":2,"x":3210,"y":4321}]}\n')
    assert json.loads(client.recv(4096))["ok"]
# Closing a controller while it holds a contact must generate a lift-off.
events = b""
until = time.monotonic() + 2
while time.monotonic() < until:
    if select.select([fd], [], [], 0.1)[0]:
        events += os.read(fd, 65536)
values = [(typ, code, value) for _, _, typ, code, value in struct.iter_unpack("llHHi", events)]
assert (3, 0x35, 3210) in values and (3, 0x39, -1) in values, values
os.close(fd)
print("PASS native touchscreen enumeration, feature query and evdev multitouch", flush=True)

mode("mass_storage_mode")
disk = wait(lambda: child_device("block"))
payload = b"usb-gadget-writeback" * 32
with open("/dev/" + disk.name, "r+b", buffering=0) as device:
    device.seek(8 * 1024 * 1024)
    device.write(payload)
    os.fsync(device.fileno())
mode("charging_only")
image = Path("/var/lib/usb/disk.img")
with image.open("rb") as file:
    file.seek(8 * 1024 * 1024)
    assert file.read(len(payload)) == payload
settings = json.loads(Path("/run/test-gadgets.json").read_text())
settings["storage"]["readOnly"] = True
Path("/run/test-gadgets.json").write_text(json.dumps(settings))
mode("mass_storage_mode")
disk = wait(lambda: child_device("block"))
assert (disk / "ro").read_text().strip() == "1"
mode("charging_only")
loop = run("losetup", "--find", "--show", str(image))
try:
    mode("mass_storage_mode", failure=True)
    assert not (ROOT / "usb-signaller-storage").exists()
finally:
    run("losetup", "-d", loop)
print("PASS storage writeback, readonly and loop-attachment rejection", flush=True)

# dummy_hcd intentionally lacks isochronous endpoints. Exercise actual
# configfs setup and failed-bind rollback, not fake video streaming success.
for _ in range(2):
    mode("developer_mode")
    state = mode("uvc_mode", failure=True)
    # Descriptor creation must finish: only the UDC bind should reject ISO.
    assert "os error 16" in state["last_error"], state
    assert state["actual_mode"] == "developer_mode", state
    assert not (ROOT / "usb-signaller-uvc").exists()
print("PASS UVC configfs failure cleanup and NCM rollback (dummy_hcd has no ISO)", flush=True)

for _ in range(3):
    mode("mtp_ffs_mode")
    mode("hid_touch_mode")
    mode("developer_mode")
assert "Result=success" in run("systemctl", "show", "usb-signaller-mtp-mode", "-p", "Result")
mode("hid_touch_mode")
run("systemctl", "kill", "--signal=SIGKILL", "usb-signaller-touch-mode")
wait(lambda: status().get("busy") == "false" and status().get("actual_mode") == "charging_only"
     and "backend stopped" in status().get("last_error", ""))
assert not (ROOT / "usb-signaller-touch").exists()
time.sleep(1)
assert run("systemctl", "show", "usb-signaller-touch-mode", "-p", "MainPID", "--value") == "0"
mode("hid_touch_mode")  # Explicit retry is still possible after the fault.
mode("charging_only")
assert not list(ROOT.iterdir())
print("PASS MTP/touch/NCM transitions and final cleanup", flush=True)
