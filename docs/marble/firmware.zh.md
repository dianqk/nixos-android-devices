# Marble 固件打包

[English](firmware.md) · [设备指南](README.zh.md)

状态：已打包并在构建时校验；**尚未在实机上验证**。

## 固件版本

软件包只使用一个版本：原厂 HyperOS **OS3.0.4.0.VMRMIXM**
（`POCO/marble_global/marble:15/AQ3A.250226.002`）的运行时固件，原样取自运行该版本的
手机：基带固件分区（`/vendor/firmware_mnt`）、`/vendor/firmware`、
`/vendor/bt_firmware`、`/vendor/dsp` 以及 `/vendor/etc/sensors` 的传感器默认配置。镜像版本：`ADSP.HT.5.7-01183-WAIPIO-1`、
`SLPI.HY.5.0-00211-WAIPIO-1`、`CDSP.HT.2.7-00947-WAIPIO-1`、
`MPSS.DE.2.0.c1-00381-WAIPIO_GEN_PACK-1`、`video-firmware.2.4`、WLAN
`WLAN.HSP.2.0.c2-00057`。远程处理器校验小米签名，因此固件必须来自 Marble 原厂固件；
不要换用通用或其他机型的镜像。不包含任何单机数据（persist、基带 NV 分区、Wi-Fi 或蓝牙
地址、扬声器或传感器校准）。

## 固件来源

软件包按哈希获取一个发布归档：
[`marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst`](https://github.com/dianqk/nixos-android-devices/releases/download/firmware/marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst)
（86196426 字节，`sha256-+gwYrQNpaM+eRbDMJCdbXJvBBz9ERksci/O0One7mEo=`）。归档根目录即
载荷目录树，每个子目录有自己的 `SHA256SUMS`，另有顶层 `SHA256SUMS` 与 README。构建时
校验这些清单。本仓库不保存固件本体。

| 目录 | 内容 |
| --- | --- |
| `adsp` | `adsp2.mdt` 及分段、`adspr.jsn`、`adspua.jsn`、`battmgr.jsn` |
| `slpi` | `slpi2.mdt` 及分段、`slpir.jsn`、`slpius.jsn` |
| `cdsp` | `cdsp.mdt` 及分段、`cdspr.jsn`（暂未使用） |
| `modem` | `modem.mdt` 及分段、`modemr.jsn`、`modem_pr/` 运营商配置、`ipa_fws.mdt` 及分段 |
| `gpu` | `a730_zap.mbn`、`a730_sqe.fw`、`gmu_gen70000.bin` |
| `video` | `vpu20_4v.mbn` |
| `wlan` | `amss20.bin`、`m3.bin`、`regdb.bin`、`regdb_xiaomi.bin`、`bd_m16t*.elf` |
| `bluetooth` | `hpbtfw20.tlv`、`hpbtfw21.tlv`、`hpnv20*`、`hpnv21*` |
| `audio` | `aw882xx_acf.bin` |
| `dsp` | `/vendor/dsp` 的 FastRPC 库；传感器使用 `sdsp/`，`adsp/` 与 `cdsp/` 暂未使用 |
| `sensors` | `/vendor/etc/sensors` 的 `config/*.json`（原厂 SSC registry 默认值）与 `sns_reg_config` |

如需使用自己的副本（镜像站，或布局相同的本地目录），设置
`hardware.marble.firmwareSource`：

```nix
{ androidPackages, ... }:
{
  hardware.marble.firmwareSource = androidPackages.mkFirmwareArchive {
    name = "marble-firmware-source";
    url = "https://example.org/marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst";
    hash = "sha256-+gwYrQNpaM+eRbDMJCdbXJvBBz9ERksci/O0One7mEo=";
  };
  # 或目录：hardware.marble.firmwareSource = /path/to/marble-firmware;
}
```

本地的归档文件本身也可直接使用而无需改配置：
`nix-store --add-fixed sha256 marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst`
会把它加到按哈希获取时预期的 store 路径。

## 安装的文件

`androidPackages.devices.marble.firmware`（非自由软件；需允许 `marble-firmware` 与
`marble-firmware-zstd`）有五个输出。路径遵循板级 DT 的 `firmware-name` 属性与驱动默认
文件名；布局与 iLtanaka 的 postmarketOS 软件包
（[firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble)）一致。

| 输出 | `lib/firmware` 下的路径 | 归档文件 |
| --- | --- | --- |
| `out` | `qcom/a730_sqe.fw`、`qcom/gmu_gen70000.bin` | `gpu/` |
| `out` | `qcom/sm8475/xiaomi/marble/a730_zap.mbn` | `gpu/` |
| `out` | `qcom/vpu/vpu20_4v.mbn`（SM8450 上 Iris 的默认文件名） | `video/` |
| `out` | `ath11k/WCN6855/hw2.1/amss.bin` | `wlan/amss20.bin` |
| `out` | `ath11k/WCN6855/hw2.1/{m3,regdb}.bin` | `wlan/` |
| `out` | `ath11k/WCN6855/hw2.1/board.bin` | `hardware.marble.wifiBoardFile` |
| `out` | `qca/hp*` 及 `qca/wcnhp*` 链接 | `bluetooth/` |
| `dsp` | `qcom/sm8475/xiaomi/marble/{adsp2,slpi2}.*`、`*.jsn` | `adsp/`、`slpi/` |
| `modem` | `qcom/sm8475/xiaomi/marble/{modem,ipa_fws}.*`、`modemr.jsn`、`modem_pr/` | `modem/` |
| `audio` | `qcom/sm8475/xiaomi/marble/aw88261_acf.bin` | `audio/aw882xx_acf.bin`，去掉监控段 |
| `sensors` | 无；`etc/sensors/` 与 `seed/` 存放 SSC registry 默认值，`dsp/` 存放 SLPI FastRPC 库 | `sensors/`、`dsp/sdsp/` |

Marble 模块把 `out` 与 `dsp` 加入 `hardware.firmware`，并把 `out` 加入已安装系统的
initrd：GPU、ath11k、蓝牙与 Iris 驱动编译进内核，在早期启动时就请求固件。RAM recovery
不包含固件。`modem` 输出仅在启用 `hardware.marble.modem.enable` 时安装（根文件系统，
不进 initrd），同时在基带 NV 分区上运行 rmtfs；见[基带](../modem.zh.md)。`audio` 输出
仅在启用 `hardware.marble.audio.enable` 时安装，同时安装 AudioReach 拓扑与 UCM
（见[音频](README.zh.md#音频)）。`sensors` 输出是 `hardware.marble.sensors.enable` 的传感器数据
（见[传感器](README.zh.md#传感器)）。
本软件包优先于通用 linux-firmware。

选择：

- GPU：`a730_sqe.fw` 使用原厂文件，而非 linux-firmware 的（内容不同）；
  `gmu_gen70000.bin` 与 linux-firmware 的相同。
- 视频：linux-firmware 没有 `vpu20_4v.mbn`；使用原厂签名镜像。
- Wi-Fi：板上 WCN6855 报告 hw2.1。Android 在该芯片版本上加载 `amss20.bin`；不使用
  linux-firmware 的通用 WLAN.HSP.1.1 镜像。板级数据是小米 `bd_m16t*.elf` 之一（`gf`：
  GlobalFoundries 版 WCN6855，`gl`：国际版，`in`：印度版硬件）。默认
  `bd_m16tgf.elf`（GlobalFoundries 芯片、国行硬件 23049RAD8C）；可用
  `hardware.marble.wifiBoardFile` 选择其他文件。它安装为 `board.bin`（ath11k 的后备
  文件名）；若同时安装 linux-firmware，会先查找其 WCN6855 `board-2.bin`。
- 蓝牙：使用原厂 rampatch 与 NVM 文件，均与 linux-firmware 的不同；芯片为
  GlobalFoundries 版，btqca 会选择 `hpnv21g` NVM。
- 扬声器功放：原厂 `aw882xx_acf.bin` 为每颗功放的每个场景（Music、Receiver、Voice）
  提供一个寄存器配置，另有每颗功放一个 `ACF_SEC_TYPE_MONITOR` 段，供厂商 HAL 的
  电池/温度监控使用，主线 aw88261 驱动未实现该功能。构建时去掉这两个监控段，寄存器
  配置不变；结果（SHA-256 `25713aca…`，构建时校验）与社区的
  [`aw88261_acf.bin`](https://github.com/iLtanaka/firmware-xiaomi-marble) 逐字节相同。
- 传感器：SSC registry 默认值在构建时由 `sensors/config` 按本机型的原厂选择条件生成
  （`soc_id` 591、`hw_platform` MTP、`platform_subtype_id` 0；registry 版本 12，每组一个
  文件），得到与原厂 registry 相同的 141 个组。`lightSensorConfig.json`（小米光感 HAL 的
  数据，没有 registry 选择条件）不使用。单机校准留在手机的 persist 分区中；生成的
  registry 只含原厂默认值。

## 尚未打包

- 板级 DT 未启用 CDSP。

这些是小米/高通的专有固件二进制，不受本仓库源代码许可证约束。所有权利归其所有者。
