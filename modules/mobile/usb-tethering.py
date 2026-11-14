#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Own only USB sharing policy; networkd owns addresses and DHCP."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

TABLE = "mobile_usb"
DROPIN = Path("/run/systemd/network/10-mobile-usb.network.d/80-tethering.conf")
SAVED = Path("/run/usb-signaller/tethering-forwarding.json")
NET = Path("/sys/class/net")
PREPARED = Path("/run/usb-signaller/tethering.prepared")
READY = Path("/run/usb-signaller/tethering.ready")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=3, text=True, **kwargs)


def uplink(routes):
    # Main-table effective default route, never the gadget or a multipath guess.
    candidates = [r for r in routes if r.get("dst") == "default" and r.get("type", "unicast") == "unicast"
                  and r.get("dev") not in (None, "usb0", "lo") and not r.get("nexthops")]
    if not candidates:
        return None
    route = min(candidates, key=lambda r: r.get("metric", 0))
    interface = route["dev"]
    if not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,15}", interface):
        raise ValueError("invalid upstream interface")
    return interface


def set_uplink(interface):
    # One nft transaction; there is never an interval allowing both upstreams.
    script = f"flush set inet {TABLE} uplink\n"
    if interface:
        script += f"add element inet {TABLE} uplink {{ {json.dumps(interface)} }}\n"
    run("nft", "-f", "-", input=script)


class Forwarding:
    """Enable per-interface forwarding without changing global ip_forward."""
    def __init__(self, root=Path("/proc/sys/net/ipv4/conf"), receipt=None):
        self.root = root
        self.receipt = receipt
        self.previous = json.loads(receipt.read_text()) if receipt and receipt.exists() else {}

    def save(self):
        if self.receipt:
            self.receipt.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.receipt.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.previous))
            os.replace(temporary, self.receipt)

    def enable(self, interface):
        path = self.root / interface / "forwarding"
        if interface not in self.previous:
            self.previous[interface] = path.read_text().strip()
            self.save()
        path.write_text("1\n")

    def restore(self, interface):
        previous = self.previous.get(interface)
        path = self.root / interface / "forwarding"
        if previous is not None and path.exists() and path.read_text().strip() == "1":
            path.write_text(previous + "\n")
        self.previous.pop(interface, None)
        self.save()

    def close(self):
        for interface in list(self.previous):
            self.restore(interface)


def network_reload():
    run("networkctl", "reload")
    if (NET / "usb0").exists():
        run("networkctl", "reconfigure", "usb0")


def cleanup():
    READY.unlink(missing_ok=True)
    PREPARED.unlink(missing_ok=True)
    try:
        # Close the nft gate even if a saved sysctl receipt is damaged.
        set_uplink(None)
        Forwarding(receipt=SAVED).close()
    finally:
        DROPIN.unlink(missing_ok=True)
        network_reload()


def wait_for_gadget(mac, stopped):
    # NCM registers its netdev only during UDC binding. Preparation must finish
    # first, but forwarding must wait for that exact gadget's interface.
    while not stopped():
        path = NET / "usb0/address"
        if path.exists():
            if path.read_text().strip().lower() != mac.lower():
                raise RuntimeError("usb0 belongs to another device")
            return True
        time.sleep(0.025)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("--mac", default="")
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()
    address = str(ipaddress.ip_interface(args.address).ip)
    cleanup()
    if args.cleanup:
        return
    if not re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", args.mac):
        parser.error("--mac must identify the NCM gadget")
    forwarding = Forwarding(receipt=SAVED)
    stopping = False

    def stop(_sig, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    current = None
    try:
        READY.unlink(missing_ok=True)
        set_uplink(None)
        DROPIN.parent.mkdir(parents=True, exist_ok=True)
        DROPIN.write_text(f"[DHCPServer]\nEmitRouter=yes\nEmitDNS=yes\nDNS={address}\n")
        network_reload()
        PREPARED.parent.mkdir(parents=True, exist_ok=True)
        PREPARED.write_text("ready\n")
        if not wait_for_gadget(args.mac, lambda: stopping):
            return
        forwarding.enable("usb0")
        while not stopping:
            routes = json.loads(run("ip", "-j", "-4", "route", "show", "table", "main", "default", stdout=subprocess.PIPE).stdout)
            selected = uplink(routes)
            if selected != current:
                # Close forwarding before changing kernel policy or restoring an
                # old interface, even when the default route disappears.
                set_uplink(None)
                if current:
                    forwarding.restore(current)
                if selected:
                    forwarding.enable(selected)
                current = selected
            set_uplink(current)
            # Missing upstream is a valid, closed sharing mode; status reports it.
            READY.parent.mkdir(parents=True, exist_ok=True)
            temporary = READY.with_suffix(".tmp")
            temporary.write_text((current or "offline") + "\n")
            os.replace(temporary, READY)
            # Type=simple lets the manager wait for this marker instead of
            # systemctl waiting indefinitely for an internet connection.
            time.sleep(0.5)
    finally:
        READY.unlink(missing_ok=True)
        PREPARED.unlink(missing_ok=True)
        try:
            set_uplink(None)
        finally:
            forwarding.close()
            DROPIN.unlink(missing_ok=True)
            network_reload()


if __name__ == "__main__":
    main()
