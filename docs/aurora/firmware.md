# Aurora firmware packaging

[中文](firmware.zh.md)

The supported installation base is the China Android 14 fastboot ROM
**OS1.0.3.0.UNACNXM**. Flash that exact factory base before installing NixOS;
follow the [installation prerequisites](README.md#required-factory-firmware-before-installation).
The package defaults to the matching Android 14 runtime firmware. It does not
flash or replace the bootloader/security-firmware partitions.

## Variant selection

Use the same variant in recovery and the installed system:

```nix
hardware.aurora.firmwareVariant = "android14"; # default
```

The module uses this selection in both early recovery and the installed system.
An explicit `hardware.aurora.firmwarePackage` override must pass the same
`firmwareVariant` to the firmware package, alongside any `bluetoothNvm` override.
The selection covers ADSP, GPU, video, Wi-Fi and Bluetooth together. A calibrated
Bluetooth NVM override must also come from the selected release. The
[legacy Android 16 variant](#legacy-android-16-variant) is not a supported
installation base.

Update the initrd and reboot when changing variants. Replacing files and
restarting remoteproc in a failed boot can mix cached MDT metadata with new
segments; it is not an adequate compatibility test.

## Android 14 sources

All files are unchanged copies from OS1.0.3.0.UNACNXM (runtime build
V816.0.3.0.UNACNXM):

| Component | Source | Hashes |
| --- | --- | --- |
| ADSP (61 files) | `NON-HLOS.bin`, directory `image/adsp*` (image SHA-256 `785543cdcece1955d4fec679dbcf5b92c2030226ff4703a04a92fdab30e5c1b8`) | [ADSP SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/adsp/SHA256SUMS) |
| Adreno 750 GPU | `/vendor/firmware/` | [GPU SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/gpu/SHA256SUMS) |
| Video (`vpu33_4v.mbn`) | `/vendor/firmware/` | [Video SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/video/SHA256SUMS) |
| WLAN | `NON-HLOS.bin`, `image/kiwi` | [WLAN SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/wlan/SHA256SUMS) |
| Bluetooth | `BTFM.bin`, `image` | [Bluetooth SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/bluetooth/SHA256SUMS) |
| Modem | see [Modem firmware](#modem-firmware) | [Modem SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/modem/SHA256SUMS) |

The extracted files match the same release's installed Android files.
SQE/GMU (`gen70900_sqe.fw`, `gmu_gen70900.bin`) install under
`lib/firmware/qcom/`; the complete ELF ZAP image `gen70900_zap.mbn` installs under
`qcom/sm8650/xiaomi/aurora/`. The mainline A750 driver does not request the stock
AQE image, so it is omitted.

The Android 14 ADSP span is `0x4080000` at `0x9df00000`. The board reservation
is sized for the larger Android 16 image (`0x4680000`), so both fit. The MDT
loader passes the image's actual load span to the secure PAS memory-setup call.

## Packaging and validation

The package installs split MDT/Bxx images and service descriptors under
`lib/firmware/qcom/sm8650/xiaomi/aurora/`. Linux's Qualcomm MDT loader supports
these split files directly; no concatenation or substitution with another
board's firmware is required. ADSP and ADSP DTB both need their MDT and segments.

These are proprietary Xiaomi/Qualcomm firmware binaries, not covered by the
repository's source-code license. All firmware rights remain with their owners.
Only files from the factory ROM are included; no handset-specific partition
readbacks, address overrides or calibration data are included. The data is fetched from the pinned
[firmware-xiaomi-aurora repository](https://github.com/dianqk/firmware-xiaomi-aurora).
The shared [source definition](../../pkgs/aurora/firmware-source.nix) supplies both
the firmware package and OEM touch data; no OEM payloads are embedded here.

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
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14
```

## Status

With the Android 14 bundle on its matching base:

- ADSP battery reporting, USB, Wi-Fi and Bluetooth work; see
  [connectivity](connectivity.md). Bluetooth was checked with a separately
  calibrated NVM; the unmodified stock NVM is not verified for every handset.
  RF calibration quality and sustained charging are not established.
- The GPU passes OpenGL validation and Turnip Vulkan submission. Known GLES
  mediump validation differences remain; the corresponding highp cases pass.
- FFmpeg's VA-API backend decodes H.264/HEVC/VP9/AV1 pixel-exactly and encodes
  H.264/HEVC. Direct `hevc_v4l2m2m` decoding fails intermittently (firmware
  error `0x4000003` or corrupt frames); prefer VA-API.
- The Android 14 bundle on an Android 16 security-firmware base is not
  verified; fitting in Linux's DT does not imply cross-base compatibility.

## Video firmware

`vpu33_4v.mbn` is the complete signed ELF (2,331,336 bytes for Android 14).
The package installs it under `qcom/sm8650/xiaomi/aurora/`; the board's Iris
`firmware-name` selects it instead of the generic VPU33 image.

The relocatable load segments fit Aurora's `0x9bb00000 + 0x800000` (8 MiB)
reservation. This is a complete image, not a split MDT set; do not concatenate
or substitute SM8550 VPU30 firmware. Validate the packaged ELF together with the
ADSP segments on the host:

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14 \
  --video /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora/vpu33_4v.mbn
```

H.264/HEVC 8-bit hardware decode matches software decode, and short 8-bit
encoding works. Main10 decode does not work through FFmpeg's V4L2 format
mapping; this does not establish a hardware limitation. See the
[device guide](README.md).

## Modem firmware

The Android 14 firmware package has a separate `modem` output, used only by
[`hardware.aurora.modem`](connectivity.md#cellular-modem-experimental). It
contains the complete `image/` tree of the OS1.0.3.0.UNACNXM `modemfirmware`
partition (`MODEM-FW.bin`, SHA-256
`1ad54d1b0260b21ff26697bad73bc70c5d0575c5348a6eab92c785ce6aba3076`): split
`modem.mdt` and `modem_dtb.mdt` images, service descriptors, `qdsp6m.qdb`
databases and the `modem_pr/mcfg` carrier configurations. It also contains the
split IPA GSI firmware `ipa_fws.mdt` from `NON-HLOS.bin/image`. All 533 files are
unchanged, and their sizes match the mounted partitions on a handset running that
base. They install under `qcom/sm8650/xiaomi/aurora/`, where tqftpserv resolves
the modem's `/readonly/firmware/image/` requests. Hashes are in
[MODEM-SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/modem/SHA256SUMS).

The MDT loader loads the split segments directly; no squashed `.mbn` files are
needed. The modem image spans `0xe200000` of the `0x8bc00000 + 0xf400000`
reservation and the modem DTB fits `0x9b000000 + 0x80000`. The relocatable IPA
image spans `0x8568` of the `0x9b080000 + 0x10000` region. Check the packaged
files with:

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14 \
  --modem /path/to/modem/lib/firmware/qcom/sm8650/xiaomi/aurora
```

Per-handset modem NV data (`modemst1`, `modemst2`, `fsg`, `fsc`) is not part of
any package. The Android 16 variant leaves the `modem` output empty.

## Radio firmware

The WLAN and Bluetooth `SHA256SUMS` listed under [Android 14 sources](#android-14-sources)
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

## Legacy Android 16 variant

`firmwareVariant = "android16"` selects files from the Android 16 fastboot ROM
OS3.0.7.0.WNACNXM. It is kept for compatibility research and is not a supported
installation base. All files are unchanged:

- ADSP: `NON-HLOS.bin`, FAT directory `image/adsp*` (image SHA-256
  `ed4fbd01d9de16496ed85d5e49f5437ba9c253ba3e0dbd922cdf78e419a858fc`);
  [ADSP SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/adsp/SHA256SUMS).
  The main-image load span is `0x4680000` at `0x9df00000`.
- GPU: `/vendor/firmware/gen70900_sqe.fw`, `/vendor/firmware/gmu_gen70900.bin`
  and `/odm/firmware/gen70900_zap.mbn`;
  [GPU SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/gpu/SHA256SUMS).
- Video: `/odm/firmware/vpu33_4v.mbn`, 2,339,528 bytes, version
  `video-firmware.3.4-75ad4eb9657cf50ee663b05f78c01d6ceccd5632`;
  [Video SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/video/SHA256SUMS).
- WLAN and Bluetooth:
  [WLAN SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/wlan/SHA256SUMS),
  [Bluetooth SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/bluetooth/SHA256SUMS).
- The `modem` output is empty.

The variant must match the installed base. Android 14 security firmware rejects
the larger Android 16 ADSP image with `-EINVAL`; ADSP then stays offline and
battery queries return `EAGAIN`, which UPower may show as 0%. This is
unavailable telemetry, not a measured empty battery.
