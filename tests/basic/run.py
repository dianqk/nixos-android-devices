#!/usr/bin/env python3
"""Manually check a running mobile example through an explicitly selected SSH host."""
import argparse
import json
import pathlib
import re
import shlex
import subprocess
import sys

TESTS = ("display", "wifi", "bluetooth", "audio", "camera", "h264", "hevc", "opengl", "vulkan")
SOFTWARE = re.compile(r"llvmpipe|softpipe|swrast|lavapipe|software|SwiftShader", re.I)


class Inconclusive(Exception):
    pass


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_media(info, codec):
    streams = info["streams"]
    require(len(streams) == 1, "Expected one video stream and no audio")
    video = streams[0]
    require(video["codec_name"] == codec and video["pix_fmt"] == "yuv420p", "Expected 8-bit " + codec)
    require(179.9 <= float(info["format"]["duration"]) <= 180.1, "Expected 180-second video")
    frames = int(video["nb_frames"])
    require(frames > 0, "Missing frame count")
    return frames


def validate_gpu(text, api):
    label = "GL_RENDERER" if api == "opengl" else "Device Name"
    match = re.search(rf"{label}:\s*(.+)", text)
    require(match is not None, "Missing GPU renderer identity")
    require(not SOFTWARE.search(match[1]), "Software rendering: " + match[1])
    score = "glmark2" if api == "opengl" else "vkmark"
    require(re.search(rf"{score} Score:\s*[1-9][0-9]*", text), "Rendering did not complete")


class Suite:
    def __init__(self, ssh, output, min_cameras=1, *, ssh_config=None):
        self.ssh = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                    "-o", "ConnectTimeout=10"]
        if ssh_config:
            self.ssh += ["-F", str(ssh_config)]
        self.ssh += ["--", ssh]
        self.min_cameras = min_cameras
        self.output = output
        self.log = None
        self.remote = None

    def command(self, args, timeout=45, stdin=None):
        if self.log:
            self.log.write("$ " + shlex.join(args) + "\n")
            self.log.flush()
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout, stdin=stdin)
        if self.log:
            self.log.write(result.stdout + result.stderr)
            self.log.flush()
        detail = "; ".join((result.stderr or result.stdout).strip().splitlines()[-3:])[-600:]
        require(result.returncode == 0, f"Command exited {result.returncode}: {detail}")
        return result.stdout

    def shell(self, *args, timeout=45):
        remote = ["timeout", "-k", "3", str(timeout - 5), *args]
        transport = self.ssh
        return self.command(transport + [shlex.join(remote)], timeout)

    def upload(self, source):
        destination = self.remote + "/" + source.name
        with source.open("rb") as stream:
            self.command(self.ssh + ["cat > " + shlex.quote(destination)],
                         timeout=120, stdin=stream)

    def session(self, *args):
        sockets = self.shell("sh", "-c", 'for f in /run/user/*/sway-ipc.*.sock; do [ ! -S "$f" ] || echo "$f"; done').splitlines()
        require(len(sockets) == 1, "Exactly one running Sway session is required")
        socket = sockets[0]
        runtime = socket.rsplit("/", 1)[0]
        uid = self.shell("stat", "-c", "%u", socket).strip()
        user = self.shell("id", "-nu", uid).strip()
        windows = self.shell("sh", "-c", f'for f in {shlex.quote(runtime)}/wayland-*; do [ ! -S "$f" ] || echo "$f"; done').splitlines()
        require(len(windows) == 1, "Exactly one Wayland socket is required")
        return self.shell("runuser", "-u", user, "--", "env", f"XDG_RUNTIME_DIR={runtime}",
                          f"SWAYSOCK={socket}", f"WAYLAND_DISPLAY={windows[0].rsplit('/', 1)[1]}", *args)

    def display(self):
        outputs = json.loads(self.session("swaymsg", "-r", "-t", "get_outputs"))
        (self.output / "outputs.json").write_text(json.dumps(outputs, indent=2) + "\n")
        require(any(o.get("active") and o.get("power") and o["current_mode"]["width"] > 0
                    and o["current_mode"]["height"] > 0 for o in outputs), "No active display")
        self.shell("sh", "-ec", '''
for d in /sys/class/drm/card*-*; do
  [ -f "$d/status" ] || continue
  echo "$d"; cat "$d/status" "$d/modes"
done
for d in /sys/class/backlight/*; do
  [ -d "$d" ] || continue
  echo "$d"
  for f in brightness actual_brightness max_brightness bl_power; do
    [ ! -f "$d/$f" ] || { echo "$f"; cat "$d/$f"; }
  done
done''')

    def wifi(self):
        devices = self.shell("iw", "dev")
        interfaces = re.findall(r"Interface (\S+)\n(?:(?!\s*Interface ).*\n)*?\s*type managed", devices)
        require(interfaces, "No managed Wi-Fi interface")
        interface = shlex.quote(interfaces[0])
        result = self.shell("sh", "-ec", f'''
interface={interface}
flags=$(cat "/sys/class/net/$interface/flags")
if [ "$((flags & 1))" = 0 ]; then
  trap 'ip link set dev "$interface" down' EXIT
  ip link set dev "$interface" up
fi
timeout 30 iw dev "$interface" scan''')
        if not re.search(r"^BSS ", result, re.M):
            raise Inconclusive("No nearby Wi-Fi access points found")

    def bluetooth(self):
        self.shell("systemctl", "is-active", "bluetooth")
        result = self.shell("sh", "-ec", '''
state=$(timeout 8 bluetoothctl show)
printf '%s\n' "$state"
case "$state" in
  *'Powered: yes'*) ;;
  *) trap 'timeout 8 bluetoothctl power off' EXIT; timeout 8 bluetoothctl power on ;;
esac
timeout 25 bluetoothctl --timeout 15 scan on''')
        result = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", result)
        require("Discovery started" in result, "Bluetooth discovery did not start")
        if not re.search(r"NEW.*Device |Device .*RSSI:", result):
            raise Inconclusive("No fresh Bluetooth discovery events")

    def camera(self):
        listing = self.shell("cam", "--list")
        # cam lists sensor-backed libcamera pipelines, excluding M2M codecs.
        cameras = re.findall(r"^\d+: .*\((.+)\)$", listing, re.M)
        require(len(cameras) >= self.min_cameras,
                f"Expected at least {self.min_cameras} cameras, found {len(cameras)}")
        for camera in cameras:
            info = self.shell("cam", "--camera", camera, "--info", "--list-properties")
            require(re.search(r"^0: [1-9][0-9]*x[1-9][0-9]*-\S+", info, re.M),
                    "No usable stream configuration: " + camera)
            require("Pixelformat:" in info, "No camera pixel formats: " + camera)

    def audio(self):
        result = self.shell("sh", "-ec", '''
cat /proc/asound/cards /proc/asound/pcm
for f in /dev/snd/pcmC*D*[pc]; do [ ! -c "$f" ] || echo "$f"; done''')
        require(re.search(r"/dev/snd/pcmC\d+D\d+[pc]", result), "No physical ALSA PCM nodes")
        require(re.search(r"(?:playback|capture) [1-9]", result), "No ALSA PCM endpoints")

    def decode(self, codec):
        info = json.loads(self.shell("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", f"{self.remote}/{codec}.mp4"))
        expected = validate_media(info, codec)
        (self.output / f"{codec}-media.json").write_text(json.dumps(info, indent=2) + "\n")
        # Explicit V4L2 M2M decoder selection cannot fall back to software.
        result = self.shell("timeout", "240", "ffmpeg", "-nostdin", "-hide_banner", "-v", "verbose", "-xerror",
                            "-c:v", codec + "_v4l2m2m", "-i", f"{self.remote}/{codec}.mp4",
                            "-map", "0:v:0", "-an", "-sn", "-dn", "-progress", "pipe:1", "-f", "null", "-", timeout=255)
        counts = re.findall(r"^frame=(\d+)$", result, re.M)
        require(counts and int(counts[-1]) == expected and "progress=end" in result,
                f"Incomplete decode: expected {expected} frames")

    def gpu(self, api, *command):
        workspaces = json.loads(self.session("swaymsg", "-r", "-t", "get_workspaces"))
        focused = next(w["name"] for w in workspaces if w["focused"])
        # Keep a fullscreen terminal from hiding/throttling the test window.
        self.session("swaymsg", "workspace __mobile_basic_test")
        try:
            result = self.session("timeout", "-k", "3", "30", *command)
            validate_gpu(result, api)
        finally:
            self.session("swaymsg", "workspace " + json.dumps(focused))

    def opengl(self):
        self.gpu("opengl", "glmark2-wayland", "--size", "640x360", "--benchmark", "build:duration=3")

    def vulkan(self):
        self.gpu("vulkan", "vkmark", "--winsys", "wayland", "--size", "640x360", "--benchmark", "cube:duration=3")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh", required=True, help="SSH host/alias with root access and a verified host key")
    parser.add_argument("--ssh-config", type=pathlib.Path, help="SSH config file")
    parser.add_argument("--media", type=pathlib.Path, help="Prepared h264.mp4 and hevc.mp4 directory")
    parser.add_argument("--output", required=True, type=pathlib.Path, help="New local result directory")
    parser.add_argument("--skip", action="append", default=[], help="Comma-separated tests: " + ",".join(TESTS))
    parser.add_argument("--min-cameras", type=int, default=1, help="Minimum detected cameras (Polaris: 2; Y700 2023: 3)")
    args = parser.parse_args()
    if args.min_cameras < 1:
        parser.error("--min-cameras must be positive")
    skips = {name for group in args.skip for name in group.split(",")}
    if skips - set(TESTS):
        parser.error("Unknown test(s): " + ",".join(sorted(skips - set(TESTS))))
    videos = [c for c in ("h264", "hevc") if c not in skips]
    if videos and (args.media is None or any(not (args.media / f"{c}.mp4").is_file() for c in videos)):
        parser.error("--media must contain the selected video files")
    args.output.mkdir(parents=True, exist_ok=False)
    suite = Suite(args.ssh, args.output, args.min_cameras, ssh_config=args.ssh_config)
    results = {}
    try:
        with (args.output / "setup.log").open("w") as suite.log:
            require(suite.shell("id", "-u").strip() == "0", "Root remote access is required")
            suite.shell("uname", "-a")
            suite.shell("readlink", "-f", "/run/current-system")
            if videos:
                suite.remote = suite.shell("mktemp", "-d", "/var/tmp/mobile-basic-test.XXXXXX").strip()
                for codec in videos:
                    suite.upload(args.media / f"{codec}.mp4")
        for name in TESTS:
            if name in skips:
                results[name] = {"status": "SKIP", "detail": "Requested"}
            else:
                print(f"Checking {name}...", flush=True)
                with (args.output / f"{name}.log").open("w") as suite.log:
                    try:
                        if name in ("h264", "hevc"):
                            suite.decode(name)
                        else:
                            getattr(suite, name)()
                        results[name] = {"status": "PASS"}
                    except Inconclusive as error:
                        results[name] = {"status": "INCONCLUSIVE", "detail": str(error)}
                    except subprocess.TimeoutExpired as error:
                        results[name] = {"status": "FAIL", "detail": f"Remote command timeout after {error.timeout}s"}
                    except (RuntimeError, ValueError, KeyError, IndexError, StopIteration) as error:
                        results[name] = {"status": "FAIL", "detail": str(error)}
            print(f"{results[name]['status']} {name}: {results[name].get('detail', '')}", flush=True)
    finally:
        suite.log = None
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        if suite.remote:
            suite.shell("rm", "-rf", "--", suite.remote)
    states = {result["status"] for result in results.values()}
    return 1 if "FAIL" in states else 2 if "INCONCLUSIVE" in states else 0


if __name__ == "__main__":
    sys.exit(main())
