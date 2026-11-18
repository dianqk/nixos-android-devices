#!/usr/bin/env python3
"""Console-only side keys; desktop sessions should own their own key policy."""
import argparse
import fcntl
import logging
import os
from pathlib import Path
import selectors
import signal
import struct
import subprocess
import time

KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_POWER = 114, 115, 116
DEVICES = {"pmic_pwrkey", "pmic_resin", "gpio-keys"}
EVENT = struct.Struct("@llHHi")
TIOCLINUX = 0x541C


class KeyPolicy:
    def __init__(self, volume, toggle_screen, poweroff, long_press=3.0):
        self.volume, self.toggle_screen, self.poweroff = volume, toggle_screen, poweroff
        self.long_press = long_press
        self.power_down = None
        self.power_fired = False
        self.volume_down = {}
        self.repeat_at = None

    def reset(self):
        # Lost events/disconnects must never turn a lost release into shutdown.
        self.power_down = None
        self.power_fired = False
        self.volume_down.clear()
        self.repeat_at = None

    def event(self, code, value, now):
        if code == KEY_POWER and (self.toggle_screen is not None or self.poweroff is not None):
            if value == 1 and self.power_down is None:
                self.power_down, self.power_fired = now, False
            elif value == 0 and self.power_down is not None:
                elapsed = now - self.power_down
                fired = self.power_fired
                self.power_down = None
                self.power_fired = False
                if not fired:
                    if elapsed >= self.long_press:
                        if self.poweroff is not None:
                            self.poweroff()
                    elif self.toggle_screen is not None:
                        self.toggle_screen()
        elif self.volume is not None and code in (KEY_VOLUMEUP, KEY_VOLUMEDOWN):
            if value == 1 and code not in self.volume_down:
                self.volume_down[code] = now
                self.repeat_at = now + 0.4
                self.volume(code == KEY_VOLUMEUP)
            elif value == 0:
                self.volume_down.pop(code, None)
                if not self.volume_down:
                    self.repeat_at = None
        # Kernel autorepeat is ignored: these GPIO/PMIC devices do not all
        # advertise EV_REP. One bounded timer supplies consistent repetition.

    def tick(self, now):
        if self.poweroff is not None and self.power_down is not None and not self.power_fired:
            if now - self.power_down >= self.long_press:
                self.power_fired = True
                self.poweroff()
        if self.volume_down and self.repeat_at is not None and now >= self.repeat_at:
            if len(self.volume_down) == 1:
                self.volume(KEY_VOLUMEUP in self.volume_down)
            self.repeat_at = now + 0.15


class ConsoleScreen:
    def __init__(self):
        self.fd = os.open("/dev/tty0", os.O_RDWR | os.O_NOCTTY)
        # VESA_POWERDOWN (3) becomes FB_BLANK_POWERDOWN (4) in the VT layer.
        fcntl.ioctl(self.fd, TIOCLINUX, b"\x0a\x03")

    def blanked(self):
        return fcntl.ioctl(self.fd, TIOCLINUX, bytearray([15]), True) != 0

    def toggle(self):
        blank = not self.blanked()
        # Explicit blank ignores keyboard/touch pokes until explicitly unblanked.
        fcntl.ioctl(self.fd, TIOCLINUX, b"\x0e" if blank else b"\x04")
        logging.info("screen %s", "off" if blank else "on")

    def close(self):
        try:
            fcntl.ioctl(self.fd, TIOCLINUX, b"\x04")
        finally:
            os.close(self.fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wpctl", help="Enable volume keys using this system-wide wpctl executable")
    parser.add_argument("--systemctl", help="Executable used for long-press shutdown")
    parser.add_argument("--no-screen", action="store_true", help="Do not open or control a VT")
    parser.add_argument("--no-poweroff", action="store_true", help="Disable long-press shutdown")
    parser.add_argument("--long-press", type=float, default=3.0)
    args = parser.parse_args()
    if not 1 <= args.long_press <= 6:
        parser.error("long press must be 1..6 seconds")
    if not args.no_poweroff and not args.systemctl:
        parser.error("--systemctl is required unless --no-poweroff is set")
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    environment = dict(os.environ, XDG_RUNTIME_DIR="/run/pipewire")

    def run(command, environment=None):
        try:
            subprocess.run(command, env=environment, check=True, timeout=5,
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
            return True
        except (OSError, subprocess.SubprocessError) as error:
            logging.error("action failed: %s", error)
            return False

    def volume(up):
        if run([args.wpctl, "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@",
                "5%+" if up else "5%-"], environment):
            logging.info("volume %s", "up" if up else "down")

    def poweroff():
        logging.info("power held for %.1fs: orderly poweroff", args.long_press)
        run([args.systemctl, "--no-block", "poweroff"])

    screen = None if args.no_screen else ConsoleScreen()
    policy = KeyPolicy(volume if args.wpctl else None,
                       screen.toggle if screen is not None else None,
                       None if args.no_poweroff else poweroff, args.long_press)
    selector = selectors.DefaultSelector()
    devices = {}
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def remove(path):
        fd = devices.pop(path)
        selector.unregister(fd)
        os.close(fd)
        policy.reset()

    try:
        scan_at = 0
        while running:
            now = time.monotonic()
            if now >= scan_at:
                scan_at = now + 1
                for path in list(devices):
                    if not path.exists():
                        remove(path)
                for node in Path("/sys/class/input").glob("event*"):
                    path = Path("/dev/input") / node.name
                    if path in devices:
                        continue
                    try:
                        name = (node / "device/name").read_text().strip()
                        if name not in DEVICES:
                            continue
                        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                        selector.register(fd, selectors.EVENT_READ, (path, bytearray(), [False]))
                        devices[path] = fd
                        logging.info("listening to %s (%s)", path, name)
                    except OSError as error:
                        logging.warning("input discovery: %s", error)
            for key, _ in selector.select(0.05):
                path, pending, dropped = key.data
                try:
                    data = os.read(key.fd, EVENT.size * 64)
                    if not data:
                        remove(path)
                        continue
                    pending.extend(data)
                    while len(pending) >= EVENT.size:
                        _, _, kind, code, value = EVENT.unpack(pending[:EVENT.size])
                        del pending[:EVENT.size]
                        if kind == 0 and code == 3:  # SYN_DROPPED
                            policy.reset()
                            dropped[0] = True
                        elif kind == 0 and code == 0:  # SYN_REPORT
                            dropped[0] = False
                        elif kind == 1 and not dropped[0]:
                            policy.event(code, value, time.monotonic())
                except OSError as error:
                    logging.warning("input disconnected: %s", error)
                    remove(path)
            policy.tick(time.monotonic())
    finally:
        for path in list(devices):
            remove(path)
        selector.close()
        if screen is not None:
            screen.close()


if __name__ == "__main__":
    main()
