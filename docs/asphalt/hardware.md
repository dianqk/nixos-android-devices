# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” means the repository contains support; it does not certify a
fresh installation on another tablet.

| Area | Adaptation | Status |
| --- | --- | --- |
| Boot and storage | SM8475 kernel/DTB, A/B boot and recovery, read-only GPT planner, ext4 root on `linux` | Configured; first installation on another tablet unverified |
| Display and input | Panel, backlight, touch and recovery key menu | Display, backlight and touch verified; physical menu-key selection unverified |
| DisplayPort | DP0, primary Type-C port and FSA4480 AUX mux | Dell U2720Q EDID, HBR2 ×4 training and a 3840×2160 60 Hz compositor output verified; physical image, reverse orientation and DP audio not yet verified |
| GPU and video | Adreno and video firmware, kernel drivers | OpenGL/Vulkan rendering and full 180-second H.264/HEVC 8-bit hardware decode pass; repeated short 720p/1080p hardware encoding also verified |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi and Bluetooth | WCN6855; OnePlus WLAN core with included TB320FC board data | Nearby Wi-Fi/Bluetooth discovery passes; pairing and profiles not covered |
| Audio | CS35L45 speakers, ALSA UCM and topology | Physical ALSA playback endpoints detected; no playback in the basic suite |
| microSD | Device tree support | Configured; end-to-end use unverified |
| Cameras | HI1339 rear, S5K4H7 front, SC202CS rear macro; CAMSS and libcamera software ISP | Three-camera configuration, RAW capture and repeated start/stop verified; scene photographs from all three cameras verified |
| Battery telemetry | ADSP battery manager (`qcom-battmgr-bat`) through pmic_glink | Status, capacity, voltage and current readable on Linux 7.3.0-rc6 and consistent with discharge. `power_now` does not match voltage × current and should not be displayed; compute power from `voltage_now` × `current_now`. `charge_counter` is quantized to capacity % × `charge_full`; `charge_full` versus `state_of_health`, the reported USB type and charge-cycle behavior are unverified ([charging](charging.md)) |
| Sensors | SLPI, FastRPC, libssc/proxy and rotation client | Configured; readings, physical directions and suspend/resume unverified ([setup](../sensors.md)) |

The internal panel runs at 2560×1600, 120 Hz. Current U-Boot automatically marks
B successful after loading the configured EFI image from the checked ESP. This
acknowledges EFI loading, before Linux starts; it does not certify Linux health.
If that acknowledgement cannot complete, repeated unacknowledged boots can
exhaust the bootloader's retry count and return to Android A.

The default FFmpeg is upstream nixpkgs. The direct V4L2 results in this document
refer to the retained device-patched diagnostic build; select it explicitly as
shown in [optional FFmpeg](../video.md#optional-restricted-ffmpeg).

## Hardware video encoding

The optional device-patched FFmpeg provides `h264_v4l2m2m` and `hevc_v4l2m2m`. Select NV12
input for these 8-bit encoders. For a bounded H.264 check:

```console
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30:duration=3 \
  -vf format=nv12 -c:v h264_v4l2m2m -b:v 4M -y sample.h264
ffprobe -v error -count_frames -show_entries stream=width,height,nb_read_frames sample.h264
ffmpeg -v error -xerror -i sample.h264 -f null -
```

For HEVC, use `-c:v hevc_v4l2m2m` and `sample.hevc`. The finite input contains
90 frames; verify decoded frame count as well as process exit status. A separate
codec-header packet means encoded packet count need not equal picture count.
These synthetic checks do not configure screen capture or audio recording.

Short 720p and 1080p H.264/HEVC encodes are verified: the outputs decode with
exact frame counts, and hardware decoding of the 1080p outputs matches software
decoding pixel for pixel. Sustained recording, thermal behavior and maximum
throughput are not qualified.

The kernel supplies indexed reference buffers and protected ARP memory required
by the SM8450 firmware even for ordinary encoding. If it reports retained
protected memory or an IOMMU/ownership failure, preserve the kernel log and
restart before another attempt; the failed path deliberately refuses reuse.
Sequential sessions reuse page tables. Extensive concurrent encoders and memory
pressure have not been qualified; the protected-table allocation budget is
bounded, and exhaustion returns an error.


## Optional radio identities

The device module accepts `hardware.asphalt.radio.wifiAddressFile` and
`bluetoothAddressFile`, both defaulting to `null`. Provide a build-input file
with the factory Wi-Fi MAC or saved Qualcomm Bluetooth NVM address; the
Bluetooth file uses controller byte order, which the service reverses for
BlueZ. The Wi-Fi address is applied by a udev `.link` file when `wlan0`
appears, because NetworkManager's cloned address is ignored with its IWD
backend. Identity data remains in your own configuration. Recovery does not
run these initialization services.

## UFS clock limit

`hardware.asphalt.ufs.maxFrequency` defaults to 75 MHz. A udev rule applies it to
the UFS clock scaling in the initrd and the installed system, which also keeps
the link in its lowest HS gear. Once the boot-time interconnect and power votes
are released (all fw_devlink `sync_state()` calls complete), sustained writes at
the higher clock and gear raised UFS PHY/data-link errors and controller resets
on Linux 7.3.0-rc6, including one unexpected reboot. With the limit, the same
write load and boot ran without errors. Storage throughput is reduced. Set the
option to `null` only to investigate the cause.

## Unused clocks and power domains

`hardware.asphalt.ignoreUnusedClocksAndDomains` defaults to `true`, which adds
`clk_ignore_unused` and `pd_ignore_unused` to the installed system's kernel
command line. Setting it to `false` lets the kernel turn off clocks and power
domains that no driver has claimed. A system booted without these flags passed
the display, input, USB, radio and audio startup checks on Linux 7.3.0-rc6.
The charger image keeps both flags regardless of this option.

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
