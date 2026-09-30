# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” describes repository support, not a fresh device test.

| Area | Adaptation | Status |
| --- | --- | --- |
| Boot and storage | SM8550 kernel/DTB, A/B boot and recovery, manual GPT preparation, ext4 `linux` root | Installed slot-B U-Boot/EFI and independent RAM recovery verified; fresh partitioning untested |
| Display and input | Panel, NT36532E touch, recovery keys | U-Boot menu and volume/power selection verified by RAM boot; Linux may start with a black panel; touch unverified |
| GPU and video | Adreno and video firmware, kernel drivers | Hardware OpenGL/Vulkan and H.264/HEVC decode verified |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi and Bluetooth | WCN7850 firmware and Bluetooth drivers | Fresh Wi-Fi/Bluetooth scans verified; set this tablet’s Bluetooth address |
| Audio | ADSP firmware, topology, SoundWire and CS35L43 drivers | ALSA card/PCM presence verified; playback, recording and routing untested |
| Sensors, fingerprint, pen | ADSP sensor services, FPC1553 and pen utilities | Optional; end-to-end use unverified |
| Camera | CAMSS/flash-class drivers, libcamera sensor gain helpers | Front scene capture and main-camera colour bars verified; uncalibrated ISP |

## Known limitations

The default 7.2.6 kernel boots with USB/SSH and Wi-Fi. The optional 7.3-rc5
kernel currently fails WCN7850 firmware loading. Boot without a USB host remains
unverified.

Linux can leave the panel black after the U-Boot menu. Cycling the compositor's
DSI output off/on restored the image in testing; changing brightness alone did
not. This is a display startup issue even when SSH is reachable. Full colour
fidelity remains unverified.

H.264 and HEVC 8-bit decoding passed full 180-second 1080p clips through Iris
with FFmpeg's `h264_v4l2m2m` and `hevc_v4l2m2m`. mpv, zero-copy presentation
and audio/video synchronization remain unverified.

Libcamera captures front OV32D40 scenes at 3264×2448 and rear S5KJN1 colour
bars at 4080×3060. Rear scene quality, autofocus, flash and calibrated colour
remain unverified. The depth sensor enumerates but capture quality is untested.

Recovery and the installed system negotiate a 10 Gb/s USB link; sustained
throughput is unmeasured. Keep the module's ADSP firmware in recovery: omitting
it prevents Type-C/UCSI startup and limits USB to 480 Mb/s.

## Optional settings

Sheng uses the shared NCM system / ACM+NCM recovery USB policy. Dual-role
and Type-C support remain enabled; automatic cable-role transitions still
require hardware validation. The module also owns the WCN7850 P2P
NetworkManager exclusion.
Set `hardware.sheng.wifiMacAddress` to this
unit's known factory address. `hardware.sheng.suspendWorkarounds.enable`
is opt-in (default `false`): it filters unused wake sources and cold-cycles
`ath12k_wifi7` across suspend. Suspend remains unverified in the minimal example.
