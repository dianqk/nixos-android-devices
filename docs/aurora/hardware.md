# Aurora hardware support and implementation reference

[Configuration, installation and updates](README.md) · [中文](hardware.zh.md)

Aurora is Tier 2: buildable and evaluable. The observations below describe tested
capabilities, not a commitment to runtime validation of every configuration.
The kernel is Linux 7.3-rc6 with the Aurora patch queue.
Use the exact Android 14 factory baseline in the [installation guide](README.md#required-factory-firmware-before-installation).
Runtime firmware packages do not replace the OEM boot/security firmware.

## Support overview

| Capability | Current support and limits |
| --- | --- |
| Boot and storage | B-slot U-Boot/EFI installation, independent recovery and generation rollback have been exercised. Preserve Android A and super. |
| CPU and GPU | CPU scaling/idle, Adreno 750 OpenGL 4.6, GLES 3.2 and Turnip Vulkan rendering have been exercised. Sustained thermal behavior and GPU fault recovery remain unverified. |
| Display | N1 1440×3200 at 30, 60 (preferred) and 120 Hz. Refresh and screen-on corruption checks pass at 60 Hz; 30/120 Hz visual checks, HBM and calibrated color remain incomplete. |
| Touch | Basic taps, dragging and rotation have been exercised. Multitouch accuracy, edges, palm rejection and suspend remain unverified. |
| Sensors | SSC acceleration and SensorProxy are available; the consumer supplies desktop rotation policy. |
| USB and radios | USB3 ACM/NCM, Wi-Fi and Bluetooth data paths have been exercised. See [connectivity](connectivity.md) for identity setup and remaining role/power limitations. |
| DisplayPort | Basic external picture output works. DP audio, additional modes, sustained operation and coexistence (USB3, touchscreen mapping) are not verified. |
| Cellular modem | Opt-in and experimental: MPSS, IPA, rmtfs (read-only NV by default), tqftpserv, ModemManager and the QTEE license services. Registration (LTE/5G NR), IPv4/IPv6 mobile data and SMS work with the license services enabled, including the unfree `qwesd`. See [connectivity](connectivity.md#cellular-modem-experimental) and [modem services](../modem.md). |
| Video | Iris V4L2 and an optional VA-API backend; supported test profiles and limitations are listed below. |
| Audio and power | Stereo speaker playback works; see [audio](audio.md) for remaining limits. System suspend and charging-policy parity remain unverified. |

Recovery can briefly access a verified Linux root to prepare its own SSH identity;
no target remains mounted afterward. See [recovery access](../recovery.md#configure-and-connect).

## Touchscreen

The Android 14 installed configuration enables `hardware.aurora.touch.enable`
by default. The S3910P SPI transport feeds an ARM64 adapter using the matching
OEM host-processing library and configuration. Allow the proprietary
`aurora-touch` and `aurora-firmware` packages. Recovery uses physical keys and
excludes this userspace touch runtime.

Inspect contacts with `evtest /dev/input/aurora-touch` or libinput tools. See the
[touch runtime guide](../../pkgs/aurora/touch/README.md) for diagnostics,
capture/replay and provenance. In multi-output sessions, map the touchscreen to
the intended panel in your compositor; display attachment does not establish
correct touch routing.

## Sensors and rotation

`hardware.aurora.sensors.enable` defaults on for the Android 14 installed system.
It supplies SSC/FastRPC, the matching firmware's sensor data and iio-sensor-proxy.
Consumers choose their SensorProxy/compositor rotation integration. Recovery
excludes this userspace stack.

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
ssccli --sensor accelerometer --timeout 3
monitor-sensor --accel
```

The listener must produce acceleration samples before the proxy starts. Inspect
both service journals on failure; repeatedly restarting ADSP or substituting
another ROM's sensor data is not a supported repair. See [sensor configuration](sensors.md).

## Video codecs

The board uses Iris with OEM VPU33 firmware. The following results apply to the
Android 14 stack with FFmpeg 9.0.1 and the packaged optional VA backend:

| Path | Observed operation | Known limits |
| --- | --- | --- |
| FFmpeg V4L2 decode | H.264 Baseline/High and HEVC Main 8-bit have matched software output. | HEVC Main10 capture-format failure; intermittent HEVC session/corrupt-frame failures remain unresolved. |
| FFmpeg V4L2 encode | Short H.264/HEVC 8-bit streams. | Direct Matroska output may fail without global codec headers; use Annex-B for diagnostics. |
| VA-API decode | H.264, HEVC Main/Main10, VP9 Profile 0/2 and AV1 Profile 0 8/10-bit samples have matched software output. | Sample coverage does not establish every profile, resolution or stream feature. |
| VA-API encode | H.264 High / HEVC Main 8-bit at 720p and 1080p with CQP and CBR. | 10-bit encoding, B-frames and long thermal runs are unverified. |

4K/8K, HDR and Vulkan Video remain unverified. Vulkan rendering support does not
establish Vulkan Video support. See [firmware compatibility](firmware.md).

For direct V4L2 diagnostics, select the decoder explicitly and check the log for
`iris_driver` / `Iris Decoder` and the selected video node:

```sh
ffmpeg -loglevel verbose -c:v h264_v4l2m2m -i input.mp4 -an -f null -
ffmpeg -loglevel verbose -c:v hevc_v4l2m2m -i input.mp4 -an -f null -
```

### Optional VA-API backend

Enable `androidDevices.video.vaapi.enable = true`; the hardware module does not
install the userspace backend automatically. See the [driver guide](../video.md#optional-va-api-driver).
The required kernel changes are [included](#va-api-kernel-prerequisites).

```sh
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi -i input.mp4 \
  -vf hwdownload,format=nv12 -an -f framemd5 output.md5
mpv --hwdec=vaapi --hwdec-software-fallback=no --vo=gpu-next input.mp4
```

Use the render node for the intended GPU and `p010le` for 10-bit comparisons.
Compare downloaded frames with an independent software decode; profile listing
or successful submission alone does not verify decoding.

A few display drops confined to player startup can occur with either software
or hardware decode. If playback then remains steady without decoder errors,
A/V desynchronization or new kernel faults, the initial counter alone does not
indicate a decoder regression. Accumulating drops, sustained stutter and hangs
require separate diagnosis. No preroll workaround is installed by this module.

Explicit VA-API also avoids a known `hwdec=auto` path that tries unavailable
Vulkan Video before producing AV1 parsing errors during fallback. A `yuv420p`
surface-probe error may be nonfatal if the driver subsequently selects NV12/P010
and decoding completes correctly.

## Native N1 display

The driver supports the N1 42-02-0a panel in DSC command mode. It exposes
1440×3200 at 30, 60 and 120 Hz, with mode-specific initialization and a full power
cycle on mode changes. Other Android refresh modes, seamless switching and
autonomous low-refresh operation are not enabled.

Brightness is controlled through `/sys/class/backlight/n1-panel/brightness`
(0–4095). Recovery provides a VT menu; set
`androidDevices.recovery.minimal = true` for a diagnostic console. Neither mode
includes touchscreen interaction. Display blanking does not imply system suspend.

The panel needs DSC 1.2 rate-control parameters, two slices per packet and the
stock command-transfer rate. SM8650 dual-mixer command scanout also retains
left/right DMA multirect and the matching INTF tearcheck sequence. Older kernels can show physical corruption even
when screenshots look correct. Retain the packaged DSC and display takeover
fixes when changing the kernel; confirm output on the physical display.
Basic external DP picture output works; DP audio, additional modes, sustained
operation and coexistence are not verified. See [connectivity](connectivity.md#displayport).

## Kernel integration and known limits

See the [patch overview](../../pkgs/linux-kernel/sm8650/aurora/PATCHES.md). Use the [packaged kernel definition](../../pkgs/linux-kernel/sm8650/aurora/default.nix)
as the authoritative patch/configuration list. Board-specific integration includes:

- [Board wiring and reserved GPIOs](../../pkgs/linux-kernel/sm8650/aurora/board.patch):
  keep firmware-owned GPIO reservations; probing those pins can stall initialization.
- [GMU component integration](../../pkgs/linux-kernel/patches/gmu-sync-state/README.md):
  retain the upstream proposal's provenance and documented local rebase.
- [UFS MCQ](../../pkgs/linux-kernel/sm8650/aurora/ufs-mcq.patch),
  [display IOMMU takeover](../../pkgs/linux-kernel/sm8650/aurora/sm8650-mdss-identity.patch)
  and [enabled-PLL preservation](../../pkgs/linux-kernel/sm8650/aurora/lucid-ole-preserve-enabled-pll.patch).
- BTF for systemd BPF restrictions; `/sys/kernel/btf/vmlinux` should be present.
- Direct Android recovery uses `androidDevices.boot.android.arm64LoadOffset`
  to align the unchanged kernel payload. The wrapper is not an EFI executable;
  the installed EFI path uses the original kernel.

CPU SpecSEI variation, virtual ITS table limits, intermittent GMU fenced-write
latency and Type-C role negotiation remain known limitations. Keep their
diagnostics visible; successful boot or rendering does not establish that these
issues are resolved. RTC wall-clock time may be unreliable in isolated recovery.
The unused QCE consumer is disabled; CPU cryptography remains available.

OEM board references are the pinned Xiaomi [kernel](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/c7841217725ac8bed6c4bf790d149dde10444e3d),
[board trees](https://github.com/MiCode/kernel_devicetree/tree/0dbbaba95d270e0dd74ef52eba722801409bd647),
[display driver](https://github.com/MiCode/vendor_opensource_display-drivers/tree/828d8a4fa074706bf087c5a22152309d29ea15c2)
and [display trees](https://github.com/MiCode/vendor_qcom_proprietary_display-devicetree/tree/3354864add728de1916f65511c25a512e8b06a72).
The [community Houji board](https://github.com/yoni13/armada-houji/blob/5d6156dbb0ce23d0156040219be38bbc28aa15c8/ports/houji/sm8650-xiaomi-houji.dts)
was also a reference for reserved GPIOs; Aurora wiring remains board-specific.
See [firmware packaging](firmware.md) for matching binary requirements.
Hardware patches retain source links and local adaptation notes; they do not
imply upstream acceptance or make proprietary firmware open source.

## VA-API kernel prerequisites

Aurora includes the shared Iris HFI gen2
[decode-order controls](../../pkgs/linux-kernel/patches/iris-hfi-gen2-decode-order.patch)
and [capture-pool support](../../pkgs/linux-kernel/patches/iris-hfi-gen2-capture-pool.patch).
SM8650's VPU33 uses `iris_hfi_gen2_data`; its board operations and firmware remain
unchanged. The optional backend requires these controls: profiles may appear in
`vainfo` even when context creation fails with DISPLAY_DELAY EINVAL. Standard
V4L2 clients retain display-order output unless they request the new control.

The patches retain Xilin Wu's author, date and sign-off metadata and originate
from the pinned [libva-v4l2 source](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches).
There are no Aurora-specific changes to these two patches.
