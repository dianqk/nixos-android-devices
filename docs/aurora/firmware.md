# Aurora firmware packaging

[中文](firmware.zh.md)

The supported installation base is the China Android 16 fastboot ROM
**OS3.0.308.0.WNACNXM**. Flash that exact factory base before installing NixOS;
follow the [installation prerequisites](README.md#required-factory-firmware-before-installation).
The package defaults to the matching Android 16 runtime firmware. It does not
flash or replace the bootloader/security-firmware partitions.

## Firmware release

The package carries one release: the runtime payloads of OS3.0.308.0.WNACNXM
(Android 16), used by both recovery and the installed system. They cover ADSP,
GPU, video, modem, Wi-Fi and Bluetooth together. A calibrated Bluetooth NVM
override (`bluetoothNvm`) must come from the same release. The security
firmware of the former Android 14 base (OS1.0.3.0.UNACNXM) rejects the larger
Android 16 ADSP image with `-EINVAL`; ADSP then stays offline and battery
queries return `EAGAIN`, which UPower may show as 0%. Do not mix releases.

## Firmware source

The package fetches one release archive by hash:
[`aurora-firmware-OS3.0.308.0.WNACNXM-20261024.tar.zst`](https://github.com/dianqk/nixos-android-devices/releases/download/firmware/aurora-firmware-OS3.0.308.0.WNACNXM-20261024.tar.zst)
(90,844,509 bytes, SHA-256
`ef6707fe3acda94169155a973bc5000ec94470eb1b3a3b5cbc3e2ceb6d9c08ff`).
Its root is the payload tree (`adsp`, `audio`, `bluetooth`, `gpu`, `modem`,
`sensors`, `touch`, `video`, `wlan`), each directory with its own `SHA256SUMS`,
plus a top-level `SHA256SUMS` and a README. The build checks every manifest.
This repository does not store the payloads.

To supply your own copy (a mirror or a local tree with the same layout),
set `hardware.aurora.firmwareSource`; the firmware package and the optional
touch host processor both use it:

```nix
{ androidPackages, ... }:
{
  hardware.aurora.firmwareSource = androidPackages.mkFirmwareArchive {
    name = "aurora-firmware-source";
    url = "https://example.org/aurora-firmware-OS3.0.308.0.WNACNXM-20261024.tar.zst";
    hash = "sha256-72cH/jrNqUFpFVqXO8UADslEcOsbOjtcvD4s622cCP8=";
  };
  # or a directory: hardware.aurora.firmwareSource = /path/to/aurora-firmware;
}
```

## Android 16 sources

All files are unchanged copies from OS3.0.308.0.WNACNXM (build
`BP2A.250605.031.A3`), read from a handset running that release: the `modem`
(`NON-HLOS`), `bluetooth` (`BTFM`) and `modemfirmware` (`MODEM-FW`) partitions
and the vendor/odm file systems. The file selection is the same as for the
former Android 14 archive; the Android 16 release moved the `qsh_ble` sensor
configurations to `/odm` and no longer has `sns_oem13.json`.

| Component | Source | Hashes |
| --- | --- | --- |
| ADSP (61 files) | `modem` partition (`NON-HLOS`), directory `image/adsp*` | `adsp/SHA256SUMS` |
| Adreno 750 GPU | `/vendor/firmware/` | `gpu/SHA256SUMS` |
| Video (`vpu33_4v.mbn`) | `/vendor/firmware/` | `video/SHA256SUMS` |
| WLAN | `modem` partition, `image/kiwi` | `wlan/SHA256SUMS` |
| Bluetooth | `bluetooth` partition (`BTFM`), `image` | `bluetooth/SHA256SUMS` |
| Modem | see [Modem firmware](#modem-firmware) | `modem/SHA256SUMS` |
SQE/GMU (`gen70900_sqe.fw`, `gmu_gen70900.bin`) install under
`lib/firmware/qcom/`; the complete ELF ZAP image `gen70900_zap.mbn` installs under
`qcom/sm8650/xiaomi/aurora/`. The mainline A750 driver does not request the stock
AQE image, so it is omitted.

The Android 16 ADSP span is `0x4680000` at `0x9df00000`, exactly the board
reservation (the former Android 14 image spanned `0x4080000`). Every remoteproc,
PIL, SMEM and command-DB carve-out of the Android 16 live device tree matches the
board DT. The MDT loader passes the image's actual load span to the secure PAS
memory-setup call.

## Packaging and validation

The package installs split MDT/Bxx images and service descriptors under
`lib/firmware/qcom/sm8650/xiaomi/aurora/`. Linux's Qualcomm MDT loader supports
these split files directly; no concatenation or substitution with another
board's firmware is required. ADSP and ADSP DTB both need their MDT and segments.

These are proprietary Xiaomi/Qualcomm firmware binaries, not covered by the
repository's source-code license. All firmware rights remain with their owners.
Only files from the factory ROM are included; no handset-specific partition
readbacks, address overrides or calibration data are included. The data comes
from the [release archive](#firmware-source); the shared
[source definition](../../pkgs/aurora/firmware-source.nix) supplies both the
firmware package and the optional OEM touch data; no OEM payloads are embedded here.

Build the firmware package with:

```sh
nix build .#devices.aurora.firmware --out-link result-firmware
```

The Aurora module includes this
package in both `hardware.firmware` and `androidDevices.initrdFirmware`, making
GPU/ADSP/video firmware available during early boot. The board enables ADSP
using DT firmware names `qcom/sm8650/xiaomi/aurora/adsp.mdt` and
`qcom/sm8650/xiaomi/aurora/adsp_dtb.mdt`. Its DTB reservation is
`0x9de80000 + 0x80000`. Validate packaged segments on the host with:

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora
```

## Status

With the Android 16 bundle on its matching base, ADSP and modem start, battery
and USB telemetry, Wi-Fi, Bluetooth (with a separately calibrated NVM), cellular
data, SSC sensors, GPU firmware loading and the video devices work; see
[connectivity](connectivity.md). The unmodified stock NVM is not verified for
every handset. RF calibration quality and sustained charging are not
established.

The following were measured with the former Android 14 firmware and have not
been repeated on Android 16:

- The GPU passes OpenGL validation and Turnip Vulkan submission. Known GLES
  mediump validation differences remain; the corresponding highp cases pass.
- FFmpeg's VA-API backend decodes H.264/HEVC/VP9/AV1 pixel-exactly and encodes
  H.264/HEVC. Direct `hevc_v4l2m2m` decoding fails intermittently (firmware
  error `0x4000003` or corrupt frames); prefer VA-API.

## Video firmware

`vpu33_4v.mbn` is the complete signed ELF (2,339,528 bytes for Android 16).
The package installs it under `qcom/sm8650/xiaomi/aurora/`; the board's Iris
`firmware-name` selects it instead of the generic VPU33 image.

The relocatable load segments fit Aurora's `0x9bb00000 + 0x800000` (8 MiB)
reservation. This is a complete image, not a split MDT set; do not concatenate
or substitute SM8550 VPU30 firmware. Validate the packaged ELF together with the
ADSP segments on the host:

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora \
  --video /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora/vpu33_4v.mbn
```

H.264/HEVC 8-bit hardware decode matches software decode, and short 8-bit
encoding works. Main10 decode does not work through FFmpeg's V4L2 format
mapping; this does not establish a hardware limitation. See the
[device guide](README.md).

## Modem firmware

The firmware package has a separate `modem` output, used only by
[`hardware.aurora.modem`](connectivity.md#cellular-modem-experimental). It
contains the complete `image/` tree of the OS3.0.308.0.WNACNXM `modemfirmware`
partition (`MODEM-FW`): split
`modem.mdt` and `modem_dtb.mdt` images, service descriptors, `qdsp6m.qdb`
databases and the `modem_pr/mcfg` carrier configurations. It also contains the
split IPA GSI firmware `ipa_fws.mdt` from the `modem` partition's `image`. All 581 files are
unchanged, and their sizes match the mounted partitions on a handset running that
base. They install under `qcom/sm8650/xiaomi/aurora/`, where tqftpserv resolves
the modem's `/readonly/firmware/image/` requests. Hashes are in
`modem/SHA256SUMS`.

The MDT loader loads the split segments directly; no squashed `.mbn` files are
needed. The modem image spans `0xe200000` of the `0x8bc00000 + 0xf400000`
reservation and the modem DTB fits `0x9b000000 + 0x80000`. The relocatable IPA
image spans `0x8568` of the `0x9b080000 + 0x10000` region. Check the packaged
files with:

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora \
  --modem /path/to/modem/lib/firmware/qcom/sm8650/xiaomi/aurora
```

Per-handset modem NV data (`modemst1`, `modemst2`, `fsg`, `fsc`) is not part of
any package.

## Radio firmware

The WLAN and Bluetooth `SHA256SUMS` listed under [Android 16 sources](#android-16-sources)
pin unchanged ROM files from the selected release. `amss20.bin`, `phy_ucode20.elf` and `bd_n1.elf` install as
`ath12k/WCN7850/hw2.0/{amss.bin,m3.bin}` and the BDF entry in `board-2.bin`. The complete M3 ELF is retained:
[Qualcomm CNSS2's Kiwi-v2 loader](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8650/blob/38d50357db2728300a61b6f757f2d3a09651c155/vendor/qcom/opensource/wlan/platform/cnss2/pci.c#L5157)
loads `phy_ucode20.elf` into the M3 buffer. This is distinct from auxiliary ucode.

The generated `board-2.bin` contains N1 BDF and Xiaomi REGDB under the observed
PCI/QMI key `bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255`.
There is no generic `board.bin` fallback. The package has higher priority than
generic firmware. Before radio tests, inspect the merged firmware directory:
AMSS/M3/BDF/REGDB must come from this package, and no unrelated `firmware-2.bin`
may override AMSS/M3. Do not use this N1 package for another WCN7850 board.

Bluetooth uses scoped `qca/xiaomi/aurora/` filenames. The board's observed ROM
ID is 2.0, board ID zero; Android falls back from `hmtnv20.b00` to
`hmtnv20.b2e`. The DT selects that full filename and `hmtbtfw20.tlv` explicitly.
The package accepts `bluetoothNvm` for a separately maintained, validated NVM;
`hardware.aurora.firmwarePackage` lets consumers select the overridden package.
Do not publish handset calibration or addresses. The default here is the
unchanged factory NVM, without vendor userspace's runtime tag adjustments.
The host build checks the TLV envelope and tag boundaries; Python is not added
to recovery by this packaging step.
