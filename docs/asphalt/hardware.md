# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” means the repository contains support; it does not certify a
fresh installation on another tablet.

| Area | Adaptation | Status |
| --- | --- | --- |
| Boot and storage | SM8475 kernel/DTB, A/B boot and recovery, read-only GPT planner, ext4 root on `linux` | Configured; first installation on another tablet unverified |
| Display and input | Panel, backlight, touch and recovery key menu | Display, backlight and touch verified; physical menu-key selection unverified |
| DisplayPort | DP0, primary Type-C port and FSA4480 AUX mux | Dell U2720Q EDID, HBR2 ×4 training and Sway 3840×2160 at 60 Hz verified; physical image, reverse orientation and DP audio not yet verified |
| GPU and video | Adreno and video firmware, kernel drivers | OpenGL/Vulkan rendering and full 180-second H.264/HEVC 8-bit hardware decode pass on the development tablet |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi and Bluetooth | WCN6855; OnePlus WLAN core with included TB320FC board data | Nearby Wi-Fi/Bluetooth discovery passes; pairing and profiles not covered |
| Audio | CS35L45 speakers, ALSA UCM and topology | Physical ALSA playback endpoints detected; no playback in the basic suite |
| microSD | Device tree support | Configured; end-to-end use unverified |
| Cameras | HI1339 rear, S5K4H7 front, SC202CS rear macro; CAMSS and libcamera software ISP | Three-camera configuration, RAW capture and repeated start/stop verified; scene photographs from all three cameras verified |
| Other sensors | No user path documented | Unverified |

The internal panel runs at 2560×1600, 120 Hz. Automatic
[B-slot boot-success acknowledgement](https://source.android.com/docs/core/architecture/bootloader/updating#support-for-slots)
is not integrated. Repeated unacknowledged boots can exhaust the bootloader's
retry count and return to Android A.

Use `config.androidDevices.video.ffmpegPackage` in video players to retain the device V4L2 decoder fixes.

## Optional radio identities

The device module accepts `hardware.asphalt.radio.wifiAddressFile` and
`bluetoothAddressFile`, both defaulting to `null`. Provide a build-input file
with the factory Wi-Fi MAC or saved Qualcomm Bluetooth NVM address; the
Bluetooth file uses controller byte order, which the service reverses for
BlueZ. Identity data remains in your own configuration. Recovery does not
run these initialization services.

## Cameras

The example includes the `cam` CLI. List camera IDs with `cam --list`; numeric
indices can change between boots. The camera paths end in:

| Camera | CCI path | RAW mode |
| --- | --- | --- |
| Main rear HI1339 | `cci@ac15000/i2c-bus@0/camera@20` | 4208×3120 GBRG10 |
| Front S5K4H7 | `cci@ac15000/i2c-bus@1/camera@10` | 3264×2448 GRBG10 |
| Rear macro SC202CS | `cci@ac16000/i2c-bus@0/camera@36` | 1600×1200 BGGR10 |

For an explicit photograph, use the desired full ID from the list:

```console
cam --camera '<camera ID>' --stream role=viewfinder --capture=30 --file=/tmp/photo.ppm
```

All three RAW streams run at about 30 fps. The software ISP uses generic,
uncalibrated tuning; autofocus and flash are not implemented. Scene capture is verified on all three cameras. The main rear close-up is
soft and dark with the current fixed lens position and generic tuning; image
quality is not calibrated. The [basic suite](../../tests/basic/README.md) only enumerates
and configures cameras; use `--min-cameras 3` for this tablet.

## DisplayPort

Connect a DP Alt Mode display through the primary Type-C port (GLINK port 0).
The Linux kernel exposes `DP-1`; the example compositor enables it alongside
`DSI-1`. Display placement and scaling remain compositor policy. This does not
add external-display output to U-Boot or its generation menu.

USB3 coexistence, the reverse cable orientation and display audio still need
hardware validation.
