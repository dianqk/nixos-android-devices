# Marble firmware packaging

[中文](firmware.zh.md) · [Device guide](README.md)

Status: packaged and checked at build time; **not yet verified on hardware**.

## Firmware release

The package uses one release: the runtime firmware of the stock HyperOS build
**OS3.0.4.0.VMRMIXM** (`POCO/marble_global/marble:15/AQ3A.250226.002`), taken
unchanged from a phone running it: the modem firmware partition
(`/vendor/firmware_mnt`), `/vendor/firmware`, `/vendor/bt_firmware`,
`/vendor/dsp` and the sensor defaults of `/vendor/etc/sensors`. Image versions: `ADSP.HT.5.7-01183-WAIPIO-1`,
`SLPI.HY.5.0-00211-WAIPIO-1`, `CDSP.HT.2.7-00947-WAIPIO-1`,
`MPSS.DE.2.0.c1-00381-WAIPIO_GEN_PACK-1`, `video-firmware.2.4`, WLAN
`WLAN.HSP.2.0.c2-00057`. Remote processors check Xiaomi's signatures, so the
firmware must come from Marble's stock firmware; do not substitute generic or
other-board images. No per-handset data (persist, modem NV partitions, Wi-Fi
or Bluetooth addresses, speaker or sensor calibration) is included.

## Firmware source

The package fetches one release archive by hash:
[`marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst`](https://github.com/dianqk/nixos-android-devices/releases/download/firmware/marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst)
(86196426 bytes, `sha256-+gwYrQNpaM+eRbDMJCdbXJvBBz9ERksci/O0One7mEo=`). Its
root is the payload tree, each directory with its own `SHA256SUMS`, plus a
top-level `SHA256SUMS` and a README. The build checks the manifests. This
repository does not store the payloads.

| Directory | Content |
| --- | --- |
| `adsp` | `adsp2.mdt` + segments, `adspr.jsn`, `adspua.jsn`, `battmgr.jsn` |
| `slpi` | `slpi2.mdt` + segments, `slpir.jsn`, `slpius.jsn` |
| `cdsp` | `cdsp.mdt` + segments, `cdspr.jsn` (not used yet) |
| `modem` | `modem.mdt` + segments, `modemr.jsn`, `modem_pr/` carrier configurations, `ipa_fws.mdt` + segments |
| `gpu` | `a730_zap.mbn`, `a730_sqe.fw`, `gmu_gen70000.bin` |
| `video` | `vpu20_4v.mbn` |
| `wlan` | `amss20.bin`, `m3.bin`, `regdb.bin`, `regdb_xiaomi.bin`, `bd_m16t*.elf` |
| `bluetooth` | `hpbtfw20.tlv`, `hpbtfw21.tlv`, `hpnv20*`, `hpnv21*` |
| `audio` | `aw882xx_acf.bin` |
| `dsp` | FastRPC libraries of `/vendor/dsp`; `sdsp/` is used by the sensors, `adsp/` and `cdsp/` not yet |
| `sensors` | `config/*.json` (stock SSC registry defaults) and `sns_reg_config` of `/vendor/etc/sensors` |

To supply your own copy (a mirror, or a local tree with the same layout), set
`hardware.marble.firmwareSource`:

```nix
{ androidPackages, ... }:
{
  hardware.marble.firmwareSource = androidPackages.mkFirmwareArchive {
    name = "marble-firmware-source";
    url = "https://example.org/marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst";
    hash = "sha256-+gwYrQNpaM+eRbDMJCdbXJvBBz9ERksci/O0One7mEo=";
  };
  # or a directory: hardware.marble.firmwareSource = /path/to/marble-firmware;
}
```

A local copy of the archive itself also works without changing the
configuration: `nix-store --add-fixed sha256 marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst`
adds it at the store path that the fetch by hash expects.

## Installed files

`androidPackages.devices.marble.firmware` (unfree; allow `marble-firmware` and
`marble-firmware-zstd`) has five outputs. Paths follow the board DT's
`firmware-name` properties and the drivers' default names; the layout matches
the postmarketOS package by iLtanaka
([firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble)).

| Output | Path under `lib/firmware` | Archive file |
| --- | --- | --- |
| `out` | `qcom/a730_sqe.fw`, `qcom/gmu_gen70000.bin` | `gpu/` |
| `out` | `qcom/sm8475/xiaomi/marble/a730_zap.mbn` | `gpu/` |
| `out` | `qcom/vpu/vpu20_4v.mbn` (Iris default name on SM8450) | `video/` |
| `out` | `ath11k/WCN6855/hw2.1/amss.bin` | `wlan/amss20.bin` |
| `out` | `ath11k/WCN6855/hw2.1/{m3,regdb}.bin` | `wlan/` |
| `out` | `ath11k/WCN6855/hw2.1/board.bin` | `hardware.marble.wifiBoardFile` |
| `out` | `qca/hp*` and `qca/wcnhp*` links | `bluetooth/` |
| `dsp` | `qcom/sm8475/xiaomi/marble/{adsp2,slpi2}.*`, `*.jsn` | `adsp/`, `slpi/` |
| `modem` | `qcom/sm8475/xiaomi/marble/{modem,ipa_fws}.*`, `modemr.jsn`, `modem_pr/` | `modem/` |
| `audio` | `qcom/sm8475/xiaomi/marble/aw88261_acf.bin` | `audio/aw882xx_acf.bin`, without its monitor sections |
| `sensors` | none; `etc/sensors/` and `seed/` hold the SSC registry defaults, `dsp/` the SLPI FastRPC libraries | `sensors/`, `dsp/sdsp/` |

The Marble module adds `out` and `dsp` to `hardware.firmware` and `out` to the
installed system's initrd: the GPU, ath11k, Bluetooth and Iris drivers are
built into the kernel and request their firmware during early boot. The RAM
recovery does not include firmware. The `modem` output is installed only with
`hardware.marble.modem.enable` (root file system, not the initrd), together
with rmtfs on the modem NV partitions; see [modem](../modem.md). The `audio`
output is installed only with `hardware.marble.audio.enable`, together with
the AudioReach topology and UCM ([audio](README.md#audio)). The `sensors`
output is the sensor data of `hardware.marble.sensors.enable`
([sensors](README.md#sensors)). The package has priority over generic
linux-firmware.

Choices:

- GPU: `a730_sqe.fw` is the stock file, not linux-firmware's (different
  bytes); `gmu_gen70000.bin` is identical to linux-firmware's.
- Video: linux-firmware has no `vpu20_4v.mbn`; the stock signed image is used.
- Wi-Fi: the board's WCN6855 reports hw2.1. Android loads `amss20.bin` on this
  chip revision; linux-firmware's generic WLAN.HSP.1.1 image is not used. The
  board data is one of Xiaomi's `bd_m16t*.elf` files (`gf`: GlobalFoundries
  WCN6855, `gl`: global, `in`: India hardware). The default is
  `bd_m16tgf.elf` (GlobalFoundries part, China hardware 23049RAD8C); select
  another with `hardware.marble.wifiBoardFile`. It installs as `board.bin`
  (ath11k's fallback); if linux-firmware is also installed, its WCN6855
  `board-2.bin` is searched first.
- Bluetooth: the stock rampatch and NVM files, which all differ from
  linux-firmware's; the chip is a GlobalFoundries part, so btqca selects
  the `hpnv21g` NVM.
- Speaker amplifiers: the stock `aw882xx_acf.bin` holds a register profile
  per scene (Music, Receiver, Voice) and amplifier, plus one
  `ACF_SEC_TYPE_MONITOR` section per amplifier for the vendor HAL's
  battery/temperature monitor, which the mainline aw88261 driver does not
  implement. The build drops the two monitor sections and keeps the register
  profiles unchanged; the result (SHA-256 `25713aca…`, checked at build time)
  is byte-identical to the community
  [`aw88261_acf.bin`](https://github.com/iLtanaka/firmware-xiaomi-marble).
- Sensors: the SSC registry defaults are generated at build time from
  `sensors/config` with the stock selectors for this board (`soc_id` 591,
  `hw_platform` MTP, `platform_subtype_id` 0; registry version 12, one file
  per group), giving the same 141 groups as the stock registry.
  `lightSensorConfig.json` (data of Xiaomi's light HAL, without a registry
  selector) is not used. Per-handset calibration stays in the phone's
  persist partition; the generated registry holds stock defaults only.

## Not packaged yet

- CDSP is not enabled in the board DT.

These are proprietary Xiaomi/Qualcomm firmware binaries, not covered by the
repository's source-code license. All rights remain with their owners.
