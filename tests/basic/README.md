# Basic hardware test

Run on the host with Python 3 and OpenSSH; the example needs root SSH and a running Niri session:

```sh
python3 tests/basic/run.py --ssh DEVICE_HOST --media tmp/basic-media --output tmp/basic-results
# Clover, or another device without Vulkan:
python3 tests/basic/run.py --ssh DEVICE_HOST --media tmp/basic-media --output tmp/basic-results-no-vulkan --skip vulkan
```

Use a verified host key and, if needed, a dedicated SSH configuration:

```sh
python3 tests/basic/run.py --ssh asphalt-wifi --ssh-config /path/to/ssh_config \
  --media tmp/basic-media --output tmp/basic-results-wifi --min-cameras 3
```

SSH uses batch authentication and
strict host-key checking. Configure the Wi-Fi address, identity and verified
known_hosts in the SSH config; all commands and uploads use that connection.

`--skip` accepts comma-separated test names and can be repeated. Use a new local
result directory for each run. Results are PASS, FAIL, INCONCLUSIVE or SKIP;
logs and `results.json` stay on the host. Exit codes: 0 = selected tests passed,
1 = failure, 2 = inconclusive scan. Nothing runs automatically at boot.

| Test | Checks |
| --- | --- |
| `display` | Niri output, resolution, refresh, scale, rotation, DRM connector/modes and backlight information. Physical visibility needs a separate screenshot and camera check. |
| `wifi` | One fresh Wi-Fi scan; no connection. |
| `bluetooth` | 15-second discovery of nearby devices; no pairing or connection. |
| `audio` | Kernel ALSA sound card and physical PCM device nodes; no playback or recording. This does not verify sound or an inserted jack. |
| `camera` | Enumerate libcamera cameras, acquire each and validate available stream configurations/formats; no capture or image-quality check. Use `--min-cameras 2` for Polaris or `--min-cameras 3` for Y700 2023. |
| `h264`, `hevc` | Decode each complete 180-second, 1080p, 8-bit silent clip through FFmpeg V4L2 M2M; require all frames and reject software fallback. |
| `opengl`, `vulkan` | Render a small scene for three seconds in Wayland; reject known software renderers. Scores are not performance thresholds. |

Scans temporarily enable a disabled interface/controller and restore its power
state on exit. An empty scan is inconclusive. The script does not request any
connection; existing connections are left alone. Logs may contain nearby device
identifiers. A skipped test is not a pass. Media are uploaded over SSH and removed
after the run. No network connection is needed on the device.

## Media

Prepare once on a host with Python 3, curl and FFmpeg:

```sh
python3 tests/basic/prepare-media.py tmp/basic-media
```

The script downloads checksum-pinned, free
[H.264](https://test-videos.co.uk/bigbuckbunny/mp4-h264) and
[H.265](https://test-videos.co.uk/bigbuckbunny/mp4-h265) excerpts of
**Big Buck Bunny**, © 2008 Blender Foundation,
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
Each ten-second excerpt is repeated without re-encoding to make a three-minute
video with no audio stream (H.264 60 fps; H.265 30 fps). Files are downloaded only
on request, not included in the image. The example installs only the necessary
CLI applications: iw, BlueZ, FFmpeg, libcamera (`cam`), glmark2, vkmark and existing system utilities.
Polaris and Asphalt use their device-specific FFmpeg patches.
