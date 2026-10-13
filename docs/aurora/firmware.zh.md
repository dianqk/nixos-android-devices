# Aurora 固件打包

[English](firmware.md)

受支持的安装底包是中国版 Android 14 fastboot ROM
**OS1.0.3.0.UNACNXM**。安装 NixOS 前须刷入这一精确版本的原厂底包；
参见[安装前提](README.zh.md)。
固件包默认使用与之匹配的 Android 14 运行时固件。它不会刷写或替换
bootloader/安全固件分区。

## 变体选择

recovery 与已安装系统须使用同一变体：

```nix
hardware.aurora.firmwareVariant = "android14"; # default
```

模块在早期 recovery 和已安装系统中都使用此选择。
显式覆盖 `hardware.aurora.firmwarePackage` 时，须向固件包传入相同的
`firmwareVariant`，并同时传入任何 `bluetoothNvm` 覆盖。
该选择同时涵盖 ADSP、GPU、视频、Wi-Fi 和蓝牙。经过校准的蓝牙 NVM 覆盖
也必须来自所选版本。[旧版 Android 16 变体](#旧版-android-16-变体)
不是受支持的安装底包。

切换变体时，更新 initrd 并重启。在启动失败的系统中替换文件并重启
remoteproc，可能将缓存的 MDT 元数据与新分段混用；这不足以作为兼容性测试。

<a id="android-14-sources"></a>
## Android 14 来源

所有文件均为 OS1.0.3.0.UNACNXM（运行时 build
V816.0.3.0.UNACNXM）的未修改副本：

| 组件 | 来源 | 哈希 |
| --- | --- | --- |
| ADSP（61 个文件） | `NON-HLOS.bin`，目录 `image/adsp*`（镜像 SHA-256 `785543cdcece1955d4fec679dbcf5b92c2030226ff4703a04a92fdab30e5c1b8`） | [ADSP SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/adsp/SHA256SUMS) |
| Adreno 750 GPU | `/vendor/firmware/` | [GPU SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/gpu/SHA256SUMS) |
| 视频（`vpu33_4v.mbn`） | `/vendor/firmware/` | [Video SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/video/SHA256SUMS) |
| WLAN | `NON-HLOS.bin`，`image/kiwi` | [WLAN SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/wlan/SHA256SUMS) |
| 蓝牙 | `BTFM.bin`，`image` | [Bluetooth SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/bluetooth/SHA256SUMS) |
| 基带 | 见[基带固件](#基带固件) | [Modem SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/modem/SHA256SUMS) |

提取的文件与同一版本 Android 中已安装的文件一致。
SQE/GMU（`gen70900_sqe.fw`、`gmu_gen70900.bin`）安装在
`lib/firmware/qcom/` 下；完整的 ELF ZAP 镜像 `gen70900_zap.mbn` 安装在
`qcom/sm8650/xiaomi/aurora/` 下。主线 A750 驱动不会请求原厂 AQE 镜像，
因此未包含该镜像。

Android 14 ADSP 的加载跨度为 `0x4080000`，起始于 `0x9df00000`。板级预留区
按更大的 Android 16 镜像（`0x4680000`）设定大小，因此两者都能放下。MDT
加载器将镜像的实际加载跨度传给安全 PAS 内存设置调用。

## 打包与验证

固件包将拆分的 MDT/Bxx 镜像和服务描述文件安装到
`lib/firmware/qcom/sm8650/xiaomi/aurora/` 下。Linux 的 Qualcomm MDT 加载器
可直接使用这些拆分文件；无需拼接，也无需替换为其他板子的固件。ADSP 和
ADSP DTB 都需要各自的 MDT 与分段。

这些是 Xiaomi/Qualcomm 的专有固件二进制文件，不受本仓库源代码许可证约束。
所有固件权利归其所有者。仅包含原厂 ROM 中的文件；不包含任何单机分区读出、
地址覆盖或校准数据。数据从固定版本的
[firmware-xiaomi-aurora 仓库](https://github.com/dianqk/firmware-xiaomi-aurora)获取。
共享的[来源定义](../../pkgs/aurora/firmware-source.nix)同时为固件包和 OEM
触摸数据提供来源；此处不嵌入任何 OEM 载荷。

构建固件包：

```sh
nix build .#devices.aurora.firmware --out-link result-firmware
```

Aurora 模块将此包同时加入 `hardware.firmware` 和
`androidDevices.initrdFirmware`，使 GPU/ADSP/视频固件在早期启动阶段可用。
板级配置通过 DT 固件名 `qcom/sm8650/xiaomi/aurora/adsp.mdt` 和
`qcom/sm8650/xiaomi/aurora/adsp_dtb.mdt` 启用 ADSP。其 DTB 预留区为
`0x9de80000 + 0x80000`。在主机上验证打包的分段：

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14
```

## 状态

在匹配底包上使用 Android 14 固件集时：

- ADSP 电池信息上报、USB、Wi-Fi 和蓝牙均可工作；参见
  [连接功能](connectivity.zh.md)。蓝牙使用单独校准的 NVM 检查过；
  未修改的原厂 NVM 未在每台设备上验证。
  射频校准质量和持续充电尚未确认。
- GPU 通过 OpenGL 验证和 Turnip Vulkan 提交测试。已知的 GLES
  mediump 验证差异仍然存在；对应的 highp 用例通过。
- FFmpeg 的 VA-API 后端可逐像素准确地解码 H.264/HEVC/VP9/AV1，并可编码
  H.264/HEVC。直接使用 `hevc_v4l2m2m` 解码会间歇性失败（固件
  错误 `0x4000003` 或帧损坏）；优先使用 VA-API。
- Android 16 安全固件底包上的 Android 14 固件集未经验证；能放入 Linux 的 DT
  并不意味着跨底包兼容。

## 视频固件

`vpu33_4v.mbn` 是完整的已签名 ELF（Android 14 版为 2,331,336 字节）。
固件包将其安装在 `qcom/sm8650/xiaomi/aurora/` 下；板级 Iris
`firmware-name` 选择它，而不是通用 VPU33 镜像。

可重定位加载段可放入 Aurora 的 `0x9bb00000 + 0x800000`（8 MiB）
预留区。这是完整镜像，而非拆分的 MDT 集合；不要拼接，也不要替换为
SM8550 VPU30 固件。在主机上将打包的 ELF 与 ADSP 分段一并验证：

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14 \
  --video /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora/vpu33_4v.mbn
```

H.264/HEVC 8-bit 硬件解码结果与软件解码一致，短时 8-bit 编码可用。
通过 FFmpeg 的 V4L2 格式映射无法进行 Main10 解码；这并不能说明是硬件限制。
参见[设备指南](README.zh.md)。

<a id="modem-firmware"></a>
## 基带固件

Android 14 固件包有单独的 `modem` 输出，仅供
[`hardware.aurora.modem`](connectivity.zh.md) 使用。它包含
OS1.0.3.0.UNACNXM `modemfirmware` 分区（`MODEM-FW.bin`，SHA-256
`1ad54d1b0260b21ff26697bad73bc70c5d0575c5348a6eab92c785ce6aba3076`）的完整
`image/` 目录树：拆分的 `modem.mdt` 和 `modem_dtb.mdt` 镜像、服务描述文件、
`qdsp6m.qdb` 数据库以及 `modem_pr/mcfg` 运营商配置。它还包含
`NON-HLOS.bin/image` 中拆分的 IPA GSI 固件 `ipa_fws.mdt`。全部 533 个文件
均未修改，其大小与运行该底包的设备上挂载的分区一致。它们安装在
`qcom/sm8650/xiaomi/aurora/` 下，tqftpserv 在此解析基带对
`/readonly/firmware/image/` 的请求。哈希见
[MODEM-SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/d4551a3c8d2ef39769f24304fd7f3cd37396cac6/android14/modem/SHA256SUMS)。

MDT 加载器直接加载拆分的分段；不需要合并后的 `.mbn` 文件。基带镜像在
`0x8bc00000 + 0xf400000` 预留区中占用 `0xe200000`，基带 DTB 可放入
`0x9b000000 + 0x80000`。可重定位的 IPA 镜像在 `0x9b080000 + 0x10000`
区域中占用 `0x8568`。检查打包的文件：

```sh
python3 tests/aurora-firmware.py /path/to/firmware/lib/firmware/qcom/sm8650/xiaomi/aurora --adsp-variant android14 \
  --modem /path/to/modem/lib/firmware/qcom/sm8650/xiaomi/aurora
```

单机基带 NV 数据（`modemst1`、`modemst2`、`fsg`、`fsc`）不属于任何固件包。
Android 16 变体的 `modem` 输出为空。

<a id="radio-firmware"></a>
## 无线固件

[Android 14 来源](#android-14-来源)中列出的 WLAN 和蓝牙 `SHA256SUMS`
固定了所选版本中未修改的 ROM 文件。`amss20.bin`、`phy_ucode20.elf` 和 `bd_n1.elf` 分别安装为
`ath12k/WCN7850/hw2.0/{amss.bin,m3.bin}` 以及 `board-2.bin` 中的 BDF 条目。保留完整的 M3 ELF：
[Qualcomm CNSS2 的 Kiwi-v2 加载器](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8650/blob/38d50357db2728300a61b6f757f2d3a09651c155/vendor/qcom/opensource/wlan/platform/cnss2/pci.c#L5157)
将 `phy_ucode20.elf` 加载到 M3 缓冲区。这与辅助 ucode 不同。

生成的 `board-2.bin` 在实测的 PCI/QMI 键
`bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255`
下包含 N1 BDF 和 Xiaomi REGDB。没有通用的 `board.bin` 回退。该包的优先级高于
通用固件。进行无线测试前，检查合并后的固件目录：AMSS/M3/BDF/REGDB 必须来自
此包，且不得有无关的 `firmware-2.bin` 覆盖 AMSS/M3。不要将此 N1 包用于其他
WCN7850 板子。

蓝牙使用限定在 `qca/xiaomi/aurora/` 下的文件名。实测该板的 ROM ID 为 2.0，
board ID 为零；Android 会从 `hmtnv20.b00` 回退到 `hmtnv20.b2e`。DT 显式选择
该完整文件名和 `hmtbtfw20.tlv`。
固件包接受 `bluetoothNvm`，用于单独维护并经过验证的 NVM；
`hardware.aurora.firmwarePackage` 允许使用者选择覆盖后的包。
不要公开单机校准数据或地址。此处默认使用未修改的原厂 NVM，不包含厂商用户空间
在运行时对标签的调整。主机构建会检查 TLV 封装和标签边界；此打包步骤不会向
recovery 加入 Python。

<a id="legacy-android-16-variant"></a>
## 旧版 Android 16 变体

`firmwareVariant = "android16"` 选择 Android 16 fastboot ROM
OS3.0.7.0.WNACNXM 中的文件。保留它用于兼容性研究，它不是受支持的
安装底包。所有文件均未修改：

- ADSP：`NON-HLOS.bin`，FAT 目录 `image/adsp*`（镜像 SHA-256
  `ed4fbd01d9de16496ed85d5e49f5437ba9c253ba3e0dbd922cdf78e419a858fc`）；
  [ADSP SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/adsp/SHA256SUMS)。
  主镜像加载跨度为 `0x4680000`，起始于 `0x9df00000`。
- GPU：`/vendor/firmware/gen70900_sqe.fw`、`/vendor/firmware/gmu_gen70900.bin`
  和 `/odm/firmware/gen70900_zap.mbn`；
  [GPU SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/gpu/SHA256SUMS)。
- 视频：`/odm/firmware/vpu33_4v.mbn`，2,339,528 字节，版本
  `video-firmware.3.4-75ad4eb9657cf50ee663b05f78c01d6ceccd5632`；
  [Video SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/video/SHA256SUMS)。
- WLAN 和蓝牙：
  [WLAN SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/wlan/SHA256SUMS)、
  [Bluetooth SHA256SUMS](https://github.com/dianqk/firmware-xiaomi-aurora/blob/60febc4751f8b939468bd57879d6831635d520d7/android16/bluetooth/SHA256SUMS)。
- `modem` 输出为空。

变体必须与已安装的底包匹配。Android 14 安全固件会以 `-EINVAL` 拒绝更大的
Android 16 ADSP 镜像；此时 ADSP 保持离线，电池查询返回 `EAGAIN`，UPower
可能将其显示为 0%。这是遥测数据不可用，并非测得电池电量为空。
