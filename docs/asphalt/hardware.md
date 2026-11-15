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
| Suspend | s2idle (`mem_sleep_default`), UFS `spm_lvl` 5, named wakeup sources | s2idle entry, deep sleep and resume verified; power-key wake works, USB/battery events do not wake yet ([details](#suspend-and-wakeup)) |
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
the link in HS-G1. Set it to `null` to let the kernel scale between its two UFS
operating points.

The kernel describes the stock pair of operating points: 75 MHz at RPMh CX
LOW_SVS (HS-G1) and 850 MHz at TURBO_L1 (HS-G4). At 850 MHz the controller uses
Qualcomm's turbo configuration (`qcom,sm8475-ufshc`), as Lenovo's firmware does;
HS-G4 is never used at a lower clock. With this kernel and no limit, ten runs of
a sustained write load (4 GiB direct write, three copies of about 1000 files,
read-back) raised no PHY, data-link, fatal or host-reset errors, with CX at
TURBO_L1 during the load. 1 GiB writes ran at about 450–1200 MB/s (decreasing as
the device's write cache filled) and O_DIRECT reads at about 1.7 GB/s; at
75 MHz reads run at about 180 MB/s.

Earlier kernels without the turbo configuration raised PHY/data-link errors and
controller resets under the same load at 850 MHz and at 300 MHz/HS-G4, including
one unexpected reboot, once the boot-time interconnect and power votes were
released (all fw_devlink `sync_state()` calls complete). The default limit stays
until system suspend and resume are verified at 850 MHz: the udev limit does not
apply after a UFS host reset or on resume, which start at the highest operating
point.

## Suspend and wakeup

`hardware.asphalt.suspend.memSleep` defaults to `"s2idle"` and adds
`mem_sleep_default=s2idle` to the kernel command line; `"deep"` is offered by the
firmware but untested, and `null` keeps the kernel's default (`deep`). s2idle is
also Lenovo's stock default.

Verified on Linux 7.3.0-rc6 without the UFS clock limit (850 MHz turbo) and with
UFS `spm_lvl` 5 (device power-down, link off, full reinitialization on resume):
the SoC reached deep sleep (AOSS/CX/DDR collapse counters advanced for about 80 %
of a 114-second suspend), resume reported no UFS errors and direct reads
succeeded, Wi-Fi reassociated and touch reinitialized. `spm_lvl` 3 also resumed
cleanly in one trial.

Known limits:

- The power key wakes the device. Plugging in USB and other battery-manager or
  Type-C (pmic_glink) events do not wake it yet, even with those sources enabled.
- In one of two trials the Bluetooth UART interrupt (`qcom_geni_serial`) fired
  continuously shortly after suspend entry and was disabled by the kernel;
  Bluetooth then stayed unusable until reboot.
- During suspend entry the kernel may warn `i2c ... Transfer while suspended`
  when a pending Type-C/UCSI connector change sets the FSA4480 mux.

The device module declares wakeup sources for the shared
[wakeup policy](../configuration.md#suspend-wakeup-sources): `powerKey`,
`volumeKeys`, `battery` (battery manager and the ADSP remoteproc that hosts it)
and `usbPower` (USB supply and UCSI source supplies). For example, to wake only
on the power key and keep battery events ready for when they work:

```nix
androidDevices.power.wakeup = {
  enable = true;
  keep = [ "powerKey" "battery" ];
};
```

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
