#!/usr/bin/env python3
"""Rotate one explicit output from iio-sensor-proxy orientation events."""
import argparse
import fnmatch
import json
import os
import re
import signal
import subprocess
import sys

ANGLES = {"normal": 0, "left-up": 90, "bottom-up": 180, "right-up": 270}


def detect_compositor():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower().split(":")
    for name in ("sway", "niri", "hyprland"):
        if name in desktop:
            return name
    for name, variable in (("sway", "SWAYSOCK"), ("niri", "NIRI_SOCKET"),
                           ("hyprland", "HYPRLAND_INSTANCE_SIGNATURE")):
        if os.environ.get(variable):
            return name
    raise RuntimeError("cannot identify the compositor in this session")


def rotate(compositor, output, angle, touch_device=None):
    if compositor == "sway":
        command = ["swaymsg", "-t", "command", f"output {output} transform {(-angle) % 360}"]
    elif compositor == "niri":
        command = ["niri", "msg", "output", output, "transform", str(angle or "normal")]
    else:
        touch = None
        if touch_device:
            devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))
            matches = [item["name"] for item in devices["touch"]
                       if fnmatch.fnmatchcase(item["name"], touch_device)]
            if len(matches) != 1:
                raise ValueError(f"expected one touchscreen matching {touch_device!r}, found {len(matches)}")
            touch = matches[0]
        # Preserve resolution, position and scale when applying a Hyprland
        # monitor rule; Lua monitor defaults would otherwise reset them.
        monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))
        monitor = next(item for item in monitors if item["name"] == output)
        mode = f'{monitor["width"]}x{monitor["height"]}@{monitor["refreshRate"]}'
        position = f'{monitor["x"]}x{monitor["y"]}'
        rule = (f"hl.monitor({{output={json.dumps(output)}, mode={json.dumps(mode)}, "
                f"position={json.dumps(position)}, scale={float(monitor['scale'])}, "
                f"transform={angle // 90}}})")
        command = ["hyprctl", "eval", rule]
    subprocess.run(command, check=True)
    if compositor == "hyprland" and touch:
        rule = (f"hl.device({{name={json.dumps(touch)}, output={json.dumps(output)}, "
                f"transform={angle // 90}}})")
        subprocess.run(["hyprctl", "eval", rule], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compositor", choices=["auto", "sway", "niri", "hyprland"], default="auto")
    parser.add_argument("--output", required=True)
    parser.add_argument("--touch-device", help="Hyprland touchscreen name or glob; exactly one must match")
    parser.add_argument("--offset", type=int, choices=[0, 90, 180, 270], default=0,
                        help="additional counterclockwise screen rotation")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.output):
        parser.error("output must be a connector name, e.g. DSI-1")
    compositor = detect_compositor() if args.compositor == "auto" else args.compositor
    process = subprocess.Popen(["stdbuf", "-oL", "monitor-sensor", "--accel"],
                               stdout=subprocess.PIPE, text=True, encoding="utf-8",
                               env={**os.environ, "LC_ALL": "C"})
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    previous = None
    try:
        for line in process.stdout:
            match = re.search(r"(?:orientation: |orientation changed: )([a-z-]+)", line)
            if not match or match[1] not in ANGLES:
                continue
            angle = (ANGLES[match[1]] + args.offset) % 360
            if angle == previous:
                continue
            try:
                rotate(compositor, args.output, angle, args.touch_device)
            except (subprocess.CalledProcessError, StopIteration, KeyError, ValueError) as error:
                print(f"rotation failed: {error}", file=sys.stderr)
                continue
            previous = angle
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()


if __name__ == "__main__":
    sys.exit(main())
