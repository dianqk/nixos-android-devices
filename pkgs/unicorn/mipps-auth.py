#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Unicorn profile for the pinned ianchb/xiaomi-mipps-auth implementation.

Unicorn has one 32-byte BQ gauge; sheng's dual-gauge sequence is inappropriate.
The adapter seeds, keys, HMAC and VDM handshake are reused from upstream.
"""
import argparse
import csv
import errno
import fcntl
import glob
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import random
import runpy
import secrets
import subprocess
import time

LOG = logging.getLogger("unicorn-mipps-auth")
DIAGNOSTICS = (
    "firmware_generation", "service_up", "authentic", "pd_verifed",
    "real_type", "adapter_id", "adapter_svid", "pdo2", "apdo_max",
    "fastchg_mode", "quick_charge_type", "sport_mode", "fb_blank_state",
    "bq2597x_chip_ok", "bq2597x_slave_chip_ok", "bq2597x_bus_voltage",
    "bq2597x_bus_current", "bq2597x_slave_bus_current",
)
# A probe of this group timed out on the installed firmware. Keep routine
# sampling from probing unverified nodes and quarantining the shared channel.
EXTENDED_DIAGNOSTICS = (
    "bq2597x_battery_voltage",
    "master_smb1396_online", "master_smb1396_iin", "slave_smb1396_online",
    "slave_smb1396_iin", "connector_temp", "die_temperature",
    "slave_die_temperature", "thermal_temp",
)


class SessionChanged(RuntimeError):
    pass


class UnsupportedAdapter(RuntimeError):
    pass


class UsbManager:
    """Use the same serialized USB manager as interactive mode requests."""
    def call(self, method, *arguments):
        reply = subprocess.run([
            os.environ.get("USB_SIGNALLER_BUSCTL", "busctl"), "--system", "--json=short",
            "call", "com.meego.usb_moded", "/com/meego/usb_moded",
            "com.meego.usb_moded", method, *arguments,
        ], check=True, capture_output=True, text=True, timeout=4)
        return json.loads(reply.stdout)["data"][0]

    def status(self):
        return self.call("get_status")

    def request(self, mode):
        self.call("set_mode", "s", mode)


class Device:
    def __init__(self, root, sysfs=Path("/sys")):
        self.root = Path(root)
        self.sysfs = Path(sysfs)
        self.usb = self.sysfs / "class/power_supply/qcom-battmgr-usb"

    def battery_supply(self):
        supplies = self.sysfs / "class/power_supply"
        for name in ("qcom-battmgr-bat", "battery"):
            candidate = supplies / name
            if candidate.is_dir():
                return candidate
        for candidate in sorted(supplies.glob("*")):
            try:
                if (candidate / "type").read_text().strip() == "Battery":
                    return candidate
            except OSError:
                continue
        return supplies / "qcom-battmgr-bat"

    def read(self, name):
        return (self.root / name).read_text(encoding="ascii").strip()

    def write(self, name, value):
        (self.root / name).write_text(str(value) + "\n", encoding="ascii")

    def discover_xiaomi(self, token, timeout=3, sleep=time.sleep, manager=None):
        """Opt-in discovery for a known charger; never change the power role."""
        partners = sorted((self.sysfs / "class/typec").glob("port*-partner"))
        if token is None or len(partners) != 1:
            raise SessionChanged("no unique Type-C partner for discovery")
        port = partners[0].with_name(partners[0].name.removesuffix("-partner"))
        role = port / "data_role"
        usb_type = (self.usb / "usb_type").read_text()
        if not any(t in usb_type for t in ("[PD]", "[PD_PPS]", "[PD_DRP]")):
            raise UnsupportedAdapter("data role discovery requires a PD connection")
        if "[sink]" not in (port / "power_role").read_text():
            raise UnsupportedAdapter("data role discovery requires the phone to remain a power sink")
        manager = manager or UsbManager()
        status = manager.status()
        if status.get("busy") != "false":
            raise UnsupportedAdapter("USB manager busy; deferring role discovery")
        original_mode = status.get("desired_mode", "developer_mode")
        original = role.read_text().strip()
        changed = "[device]" in original
        found = False
        try:
            if self.session() != token:
                raise SessionChanged("session changed before data role discovery")
            if changed:
                LOG.info("requesting host data role for explicitly enabled Xiaomi discovery")
                manager.request("host_mode")
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                current = self.session()
                # Discovery may add attributes and change the partner ctime.
                # The firmware generation and actual partner inode must match.
                if current is None or current[:4] != token[:4]:
                    raise SessionChanged("USB partner or ADSP changed during discovery")
                if changed:
                    status = manager.status()
                    if status.get("desired_mode") == "host_mode" and status.get("busy") == "false" and status.get("last_error"):
                        raise UnsupportedAdapter("USB role discovery failed: " + status["last_error"])
                    if status.get("busy") != "false" or status.get("actual_mode") != "host_mode":
                        sleep(0.1)
                        continue
                if int(self.read("adapter_svid"), 16) == 0x2717:
                    LOG.info("Xiaomi adapter discovered after host data role request")
                    found = True
                    return current
                sleep(0.1)
            raise UnsupportedAdapter("host data role did not reveal a Xiaomi SVID")
        finally:
            if changed and not found:
                current = self.session()
                if current is not None and current[:4] == token[:4]:
                    status = manager.status()
                    # Do not overwrite a user mode change or a busy manager.
                    if status.get("desired_mode") == "host_mode" and status.get("busy") == "false":
                        manager.request(original_mode)

    def session(self):
        if self.read("service_up") != "1" or (self.usb / "online").read_text().strip() != "1":
            return None
        partners = sorted((self.sysfs / "class/typec").glob("port*-partner"))
        if len(partners) != 1:
            return None
        stat = partners[0].stat()
        return (str(self.root.resolve()), self.read("firmware_generation"),
                str(partners[0].resolve()), stat.st_ino, stat.st_ctime_ns)

    def blank_state(self):
        # drm_atomic_helper_update_legacy_modeset_state updates connector->dpms
        # from the CRTC active state for atomic clients too. Never infer this
        # from an idle timeout, session lock, or requested backlight brightness.
        connectors = sorted((self.sysfs / "class/drm").glob("card*-DSI-*/dpms"))
        if len(connectors) != 1:
            return 0  # Unknown is conservatively treated as screen on.
        try:
            return int(connectors[0].read_text().strip() == "Off")
        except OSError:
            return 0


def load_upstream(path):
    # run_name is not __main__, so importing never executes upstream's CLI.
    import types
    return types.SimpleNamespace(**runpy.run_path(str(path)))


def authenticate(device, upstream, token, sleep=time.sleep, allow_data_role_swap=False):
    sync_display = False
    display_blank = None

    def check():
        nonlocal display_blank
        if token is None or device.session() != token:
            raise SessionChanged("USB partner or ADSP generation changed")
        if sync_display:
            blank = device.blank_state()
            if blank != display_blank:
                device.write("fb_blank_state", blank)
                display_blank = blank
                if device.session() != token:
                    raise SessionChanged("session changed during display update")

    def read(_root, name):
        check()
        value = device.read(name)
        check()
        return value

    def write(_root, name, value):
        check()
        device.write(name, value)
        check()

    # Upstream functions resolve these globals in their original module dict.
    namespace = upstream.send_vdm.__globals__
    namespace["read_node"] = read
    namespace["write_node"] = write
    root = str(device.root)
    check()
    svid = int(read(root, "adapter_svid"), 16)
    pdo2 = int(read(root, "pdo2"), 16)
    if pdo2 == 0:
        raise UnsupportedAdapter("waiting for a Xiaomi adapter with source PDOs")
    if svid == 0 and allow_data_role_swap:
        token = device.discover_xiaomi(token)
        svid = int(read(root, "adapter_svid"), 16)
    if svid != upstream.XIAOMI_SVID:
        raise UnsupportedAdapter("Xiaomi SVID unavailable; host data role discovery is opt-in")

    sync_display = True
    write(root, "sport_mode", "0")
    write(root, "verify_process", "1")
    try:
        # Do not trust a flag left over from an earlier service or cable session.
        write(root, "pd_verifed", "0")
        write(root, "authentic", "0")
        challenge = secrets.token_hex(32)
        write(root, "verify_digest", challenge)
        sleep(1.4)
        reply = read(root, "verify_digest")
        expected = [hmac.new(bytes.fromhex(key), bytes.fromhex(challenge),
                             hashlib.sha256).hexdigest() for key in upstream.FG_KEYS]
        if reply.lower() == challenge:
            raise RuntimeError("master gauge returned the challenge unchanged instead of an authentication digest")
        if len(reply) != 64 or not any(hmac.compare_digest(reply.lower(), x) for x in expected):
            raise RuntimeError("master gauge digest verification failed")
        write(root, "authentic", "1")

        # Only an identified Xiaomi adapter reaches the VDM handshake. Never
        # change the data role on a computer/ordinary PD connection.
        index = random.randrange(len(upstream.SEEDS))
        for cmd in (1, 2, 3):
            upstream.send_vdm(root, cmd, timeout=3, settle=upstream.ANDROID_CMD_SETTLE[cmd])
        upstream.send_vdm(root, 4, upstream.SEEDS[index], timeout=3, settle=0.5)
        challenge = secrets.token_hex(16)
        _, reply = upstream.send_vdm(root, 5, challenge, timeout=3, settle=0.5)
        adapter_id = upstream.normalize_adapter_id(read(root, "adapter_id"))
        if adapter_id is None:
            raise RuntimeError("adapter ID is missing or malformed")
        digest = hmac.new(bytes.fromhex(upstream.KEYS[index]),
                          bytes.fromhex(challenge + adapter_id), hashlib.sha256).hexdigest()
        if len(reply) != 32 or not hmac.compare_digest(reply.lower(), digest[:32]):
            raise RuntimeError("adapter digest verification failed")
        # No positive adapter result is sent before both digest checks pass.
        upstream.send_vdm(root, 6, "01000000", timeout=3, wait=False, settle=0.1)
        upstream.send_vdm(root, 8, digest[32:], timeout=3)
        upstream.send_vdm(root, 7, "01000000", timeout=3, wait=False, settle=0.1)
        write(root, "pd_verifed", "1")
        if read(root, "pd_verifed") != "1":
            raise RuntimeError("firmware did not confirm adapter authentication")
        LOG.info("protocol authentication succeeded; input power is measured separately")
    except Exception:
        # Clear only the current session; never write a stale result to a new cable.
        for name in ("pd_verifed", "authentic"):
            try:
                write(root, name, "0")
            except (OSError, SessionChanged):
                pass
        raise
    finally:
        try:
            write(root, "verify_process", "0")
        except (OSError, SessionChanged):
            pass
    return token


def save_verified_session(path, token):
    if path is None:
        return
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
        with temporary.open("w", encoding="ascii") as output:
            os.chmod(temporary, 0o600)
            json.dump(list(token), output)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def has_verified_session(path, token):
    if path is None or token is None:
        return False
    try:
        return json.loads(Path(path).read_text(encoding="ascii")) == list(token)
    except (OSError, ValueError):
        return False


class Controller:
    def __init__(self, allow_data_role_swap=False, receipt=None):
        self.allow_data_role_swap = allow_data_role_swap
        self.receipt = receipt
        self.token = None
        self.authenticated = False
        self.next_attempt = 0
        self.attempts = 0
        self.blank = None
        self.wait_reason = None

    def step(self, device, upstream, now):
        token = device.session() if device else None
        if token != self.token:
            self.token = token
            # Only reuse a result recorded after our own digest checks, for
            # this exact partner and firmware session. Firmware flags alone
            # are insufficient evidence of a previous successful handshake.
            self.authenticated = has_verified_session(self.receipt, token)
            self.next_attempt = now
            self.attempts = 0
            self.blank = None
            self.wait_reason = None
        if token is None:
            return
        # Also resubmit actual display state after firmware restart.
        blank = device.blank_state()
        if blank != self.blank:
            device.write("fb_blank_state", blank)
            device.write("sport_mode", 0)
            self.blank = blank
        if self.authenticated:
            if device.read("pd_verifed") == "1" and device.read("authentic") == "1":
                return
            self.authenticated = False
            self.next_attempt = now
        if now < self.next_attempt:
            return
        try:
            verified = authenticate(device, upstream, token, allow_data_role_swap=self.allow_data_role_swap)
            self.token = verified
            save_verified_session(self.receipt, verified)
            self.authenticated = True
            self.attempts = 0
            self.wait_reason = None
        except UnsupportedAdapter as exc:
            # Discovery may finish after the USB online event. Do not mark an
            # attach permanently attempted, or nudge an ordinary PD data role.
            self.next_attempt = now + 10
            reason = str(exc)
            if reason != self.wait_reason:
                LOG.info("authentication pending: %s (adapter_svid=%s, pdo2=%s)",
                         reason, device.read("adapter_svid"), device.read("pdo2"))
                self.wait_reason = reason
        except (OSError, RuntimeError, subprocess.SubprocessError, upstream.UnsupportedChargerError, ValueError) as exc:
            self.attempts += 1
            self.next_attempt = now + min(60, 5 * 2 ** min(self.attempts, 4))
            LOG.warning("authentication attempt %d failed: %s", self.attempts, exc)


def find_device(root=None):
    candidates = [root] if root else glob.glob("/sys/devices/platform/pmic-glink/*/xiaomi")
    for candidate in candidates:
        if (Path(candidate) / "firmware_generation").exists():
            return Device(candidate)
    return None


def read_error(exc):
    code = exc.errno
    # TextIO can surface an EAGAIN read as BlockingIOError without errno.
    if code is None and isinstance(exc, BlockingIOError):
        code = errno.EAGAIN
    return f"error:{code}" if code is not None else f"error:{type(exc).__name__}:{exc}"


def diagnostics(device, extended=False):
    result = {"timestamp": time.time()}
    timed_out = False
    for name in DIAGNOSTICS + EXTENDED_DIAGNOSTICS:
        if name in EXTENDED_DIAGNOSTICS and not extended:
            result[name] = "not-probed"
            continue
        if timed_out:
            result[name] = "skipped:previous-timeout"
            continue
        try:
            result[name] = device.read(name)
        except OSError as exc:
            result[name] = read_error(exc)
            timed_out = exc.errno == errno.ETIMEDOUT
    for supply, nodes in ((device.usb, ("online", "usb_type", "voltage_now", "current_now")),
                          (device.battery_supply(), ("capacity", "temp"))):
        for name in nodes:
            try:
                result[name] = (supply / name).read_text().strip()
            except OSError as exc:
                result[name] = read_error(exc)
    try:
        # USB input telemetry in microvolts/microamps; never use battery power.
        result["usb_input_watts"] = int(result["voltage_now"]) * int(result["current_now"]) / 1e12
    except ValueError:
        result["usb_input_watts"] = "unavailable"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", default=os.environ.get("XIAOMI_MIPPS_UPSTREAM"))
    parser.add_argument("--sysfs")
    parser.add_argument("--allow-data-role-swap", action="store_true",
                        help="allow host data role discovery on a known Xiaomi charger; may interrupt USB data")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--daemon", action="store_true")
    mode.add_argument("--diagnose", action="store_true", help="read-only JSON snapshot")
    mode.add_argument("--sample", action="store_true", help="read-only CSV input telemetry to stdout")
    parser.add_argument("--extended", action="store_true",
                        help="also probe firmware-dependent nodes; a timeout can temporarily block authentication")
    parser.add_argument("--duration", type=float, default=300)
    parser.add_argument("--interval", type=float, default=2)
    args = parser.parse_args()
    if args.interval <= 0 or args.duration <= 0:
        parser.error("duration and interval must be positive")
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(message)s")
    if args.diagnose or args.sample:
        device = find_device(args.sysfs)
        if device is None:
            parser.error("Unicorn Xiaomi sysfs interface not found")
        if args.diagnose:
            print(json.dumps(diagnostics(device, args.extended), indent=2))
        else:
            import sys
            deadline = time.monotonic() + args.duration
            row = diagnostics(device, args.extended)
            writer = csv.DictWriter(sys.stdout, fieldnames=list(row))
            writer.writeheader()
            while True:
                writer.writerow(row)
                sys.stdout.flush()
                if time.monotonic() >= deadline:
                    break
                time.sleep(args.interval)
                row = diagnostics(device, args.extended)
        return
    if not args.upstream:
        parser.error("--upstream is required for authentication")
    # Serialise whole handshakes, including invocations outside systemd.
    lock_path = Path("/run/xiaomi-mipps-auth/unicorn.lock")
    lock_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_file = lock_path.open("a")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error("another Unicorn authenticator is running")
    upstream = load_upstream(args.upstream)
    receipt = lock_path.with_name("verified-session.json")
    if not args.daemon:
        device = find_device(args.sysfs)
        if device is None:
            parser.error("Unicorn Xiaomi sysfs interface not found")
        try:
            verified = authenticate(device, upstream, device.session(), allow_data_role_swap=args.allow_data_role_swap)
            save_verified_session(receipt, verified)
        except UnsupportedAdapter as exc:
            parser.exit(2, f"authentication pending: {exc}\n")
        return
    LOG.info("Unicorn: single 32-byte gauge; sport mode disabled; display follows DRM DPMS")
    controller = Controller(args.allow_data_role_swap, receipt)
    while True:
        try:
            controller.step(find_device(args.sysfs), upstream, time.monotonic())
        except (OSError, ValueError) as exc:
            LOG.warning("waiting for charging firmware: %s", exc)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
