# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” means the repository supplies the adaptation; it is not a claim
that a new installation has passed a full device test.

| Area | Adaptation | Status |
| --- | --- | --- |
| SoC and boot | SDM845 DTB, patched kernel, Android boot and recovery images | Configured; images build |
| UFS and root | UFS initrd handling, ext4 userdata, unique GPT-name checks; optional exact per-phone contract | Configured; first format/install unverified on another device |
| Display and input | NT35596S panel patch, recovery key menu, Sway example | Sway screenshot, physical first frame on two boots and output power cycling pass; input remains unverified |
| GPU | Polaris firmware package and kernel support | Short OpenGL (FD630) and Vulkan (Turnip Adreno 630) render tests pass at scale 1; vkmark times out at scale 3 |
| Video decoding | Device-patched FFmpeg V4L2 M2M | Complete silent 180-second 1080p H.264 and HEVC 8-bit clips decode with all frames and no errors |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi and modem | Firmware and QRTR/RMTFS services; optional per-phone calibration and identity | Fresh access-point scan passes with per-phone data; connections untested |
| Bluetooth | Early firmware and optional per-phone identity | Fresh nearby-device scan passes; no pairing or connection tested |
| Audio | ADSP service descriptors, TAS2559 driver, ALSA UCM and PCM sample alignment | Physical X2S card and MultiMedia1/2 PCM detection passes; basic tests do not play or record audio |
| Camera | Main rear IMX363 and front OV5675 through CAMSS and libcamera | Both enumerate and capture real images; front 1296×972 and rear 1920×1080 output tested, including capture as `demo` |
| Fingerprint, NFC, GNSS | No validated user path documented here | Unverified |

Use `config.androidDevices.video.ffmpegPackage` in video players to retain the device V4L2 decoder fixes.
When enabling Bluetooth, set `hardware.polaris.radio.bluetoothIdentityFile` to the device-side address file; the service waits for the Bluetooth controller and verifies the active address.

An intermittent modem startup XPU fault can prevent Wi-Fi initialization after
reboot. RMTFS keeps calibration writes in RAM; its backing snapshot stays
read-only. Complete poweroff remains unverified.

## Cameras

The example installs libcamera's `cam` CLI. List cameras, then use the index
shown for the desired sensor:

```sh
cam --list
cam -c 1 --stream role=still,width=1296,height=972,pixelformat=RGB888 --capture=30 --file=/tmp/front.ppm
cam -c 2 --stream role=still,width=1920,height=1080,pixelformat=RGB888 --capture=30 --file=/tmp/rear.ppm
```

Each command keeps the final frame in a PPM file; retrieve it with
`scp root@172.16.42.1:/tmp/front.ppm .`. The pipeline uses a generic software ISP
with GPU debayering where available. Colour/noise tuning, autofocus, OIS,
flash and the auxiliary rear sensor are not implemented or validated.
The [basic camera test](../../tests/basic/README.md) uses `--min-cameras 2`
to check both pipelines without taking photos; `--skip camera` omits it.
