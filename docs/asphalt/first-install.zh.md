# Asphalt 安装与启动恢复

[English](first-install.md) · [设备指南](README.zh.md)

根据设备现状选择流程：

- **已有 NixOS：** Android/LineageOS 替换了 B 启动镜像或 DTBO，但 Linux 根和
  ESP 仍在时，使用[启动恢复](#恢复已有-efi-安装)，不要重新分区、格式化或重复首次安装。
- **首次安装：** 准备底包后，执行明确的[破坏性存储准备](#首次安装的存储准备)。

## 安装前的 Android 底包

**Asphalt 适配使用联想 TB320FC ROW 版 ZUI 17.0.339（Android 15）底包。
安装 NixOS 前先准备这一底包。** 适配时运行的 Android 系统是在该联想底包之上的
LineageOS Android 16 GSI：

| 项目 | 开发基线 |
| --- | --- |
| 设备／地区 | 联想 Y700 2023，`TB320FC`，ROW |
| 联想构建版本 | `TB320FC_ROW_OPEN_USER_Q00031.0_V_ZUI_17.0.339_ST_251219` |
| Vendor fingerprint | `Lenovo/TB320FC/TB320FC:15/AQ3A.240812.002/ZUI_17.0.339_251219_ROW:user/release-keys` |
| 适配时的 Android 系统 | LineageOS `23.2-20260524-VANILLA-EXT4-GSI`，Android 16 |

替换 Android 前，分别核对设备、vendor 构建与正在运行的系统：

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.vendor.build.version.incremental
adb -s SERIAL shell getprop ro.vendor.build.fingerprint
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.lineage.version
```

采集到的 `ro.vendor.build.version.release` 为 `13`，与 Android 15 vendor
fingerprint 不一致，不能单靠此属性识别底包。GSI 的 Android 16 版本也不能代表
联想底层固件版本。这些属性记录已观察到的构建；混刷或局部刷写后，不能据此证明
每个启动或安全固件分区的版本。其他联想底包版本尚未在本适配中证明等价。
底包准备应在首次安装的 Linux 分区之前完成；之后保留 Android A 和 super，Linux
使用 B。NixOS 更新不会更新原厂底包。恢复已有安装并不能证明最近的 Android 安装
保留了所有底层固件；不要根据 LineageOS 版本推断底包，也不要在启动恢复时顺带重刷原厂固件。

## 恢复已有 EFI 安装

仅在原有 FAT `linux-boot` ESP 和 ext4 `linux` 根分区仍保留时使用此流程。
状态不明时先在可信 recovery 中只读检查；仅有分区名不能证明文件系统可用。
保留 Android A、super、recovery、校准和所有已有用户数据。
Android 安装可能把 B recovery 替换为 Lineage recovery，不能假定原有 NixOS RAM
recovery 还在。需要时按[recovery 指南](../recovery.zh.md)建立可信维护连接。

在自己的[消费 flake](../configuration.zh.md)中构建匹配的 U-Boot `boot` 产物和主机
CLI。`boot` 是 U-Boot 固件，不是 Linux 内核或根文件系统镜像：

```sh
nix build .#boot --out-link result-boot
nix build .#mobile-device --out-link result-mobile-device
export PATH="$PWD/result-mobile-device/bin:$PATH"
```

进入 OEM fastboot，先完成下方[身份与 B 槽检查](#核对-oem-fastboot-并选择-b)，
再检查并明确刷入 **`boot_b` 一个分区**：

```sh
mobile-device --serial SERIAL fastboot flash \
  result-boot --partition boot_b
mobile-device --serial SERIAL fastboot flash \
  result-boot --partition boot_b --execute
```

执行前核对输出的机型、目标分区、大小和 SHA-256。
然后按[擦除 B DTBO 并启动](#擦除-b-dtbo-并启动)操作。启动恢复不替换 recovery，
也不写入文件系统镜像。NixOS 可连接后，核对原有 root/ESP、所选 EFI 代际和保留的
回退，再进行[标准 NixOS SSH 更新](../usb-signaller.zh.md#standard-updates)。管理链路相关
变更优先使用 `nixos-rebuild boot` 后受控重启。重新分区和擦除 DTBO 都不是日常更新步骤。

## 首次安装的存储准备

使用 B 槽上的 Rust daemon NixOS recovery，先确认实际运行的是它且 SSH 可连接。
保留 A、super、校准和独立 recovery。Recovery initrd 不包含 Python；标准 NixOS
安装与更新可在 chroot 中使用目标系统的 Python。

从原厂 userdata 布局开始，以下命令先检查，再明确执行**破坏性**准备：Android 与 Linux
各约占原 userdata 的 50%，Linux 一侧包含独立 FAT ESP（默认 1 GiB）和 ext4 根。
Android userdata 数据不保留，之后需要单独恢复出厂初始化。已分区设备不会重新分区。
不要使用此操作修复已有安装的启动路径。

```sh
ssh RECOVERY_HOST 'recovery prepare-install --check'
ssh RECOVERY_HOST 'recovery prepare-install --confirm-erase-userdata'
```

完成后按[首次安装](../initial-install.zh.md)导入匹配系统、安装 EFI，最后写入
`boot_b` U-Boot。该安装程序不会重启，且已经写入匹配固件；**不要重复启动恢复流程中的
手动 `boot_b` 刷写**。安装成功后，从 NixOS recovery 返回 OEM fastboot：

```sh
mobile-device recovery --target RECOVERY_HOST reboot bootloader
mobile-device recovery --target RECOVERY_HOST reboot bootloader --execute
```

首次正常启动 U-Boot 前，完成下方身份检查和 DTBO 擦除。不要依赖 `fastboot boot`
启动 Asphalt RAM recovery，OEM bootloader 的该能力尚未确立。
已有系统可使用 `recovery rebuild boot` 或主机侧 `mobile-device recovery deploy`
进行离线更新。旧有的 root/ESP 顺序和对齐间隙仍受支持；普通更新不重新分区。

仅需清空已有 Linux 根时，可用 `recovery format-root --check` 检查，再通过
`--confirm` 格式化。这是单独的破坏性重装操作，不是启动修复；它保留 Android 和 ESP。
新的 daemon 存储准备与首次安装操作仍待各设备实机验证。

## 核对 OEM fastboot 并选择 B

将 `SERIAL` 替换为实际平板序列号；改变槽位或刷写前，先检查这些只读结果：

```sh
fastboot -s SERIAL getvar serialno
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar modelname
fastboot -s SERIAL getvar unlocked
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL getvar partition-size:boot_b
fastboot -s SERIAL getvar partition-size:dtbo_b
```

要求序列号匹配、OEM product 为 `taro`、modelname 准确为 `TB320FC`，且 bootloader
已解锁。`dtbo_b` 容量必须准确为 24 MiB（`0x1800000`）；U-Boot 刷写检查还会核对
镜像和 `boot_b` 容量。单凭 `taro` 不能识别 Asphalt。身份或容量不符时停止操作。

若当前还不是 B，在核对以上身份**之后**明确选择 B；此操作不刷写 A：

```sh
fastboot -s SERIAL set_active b
fastboot -s SERIAL getvar current-slot
```

刷写与擦除检查都要求当前 B 槽，执行时重新验证设备。检查拒绝时，不要改用原始
fastboot 写入绕过限制。详见[CLI 身份规则](../../pkgs/mobile-device/README.zh.md#fastboot)。

## 擦除 B DTBO 并启动

Android/LineageOS 安装可能恢复不兼容的原厂 overlay。已核对的平板进入 OEM
fastboot 且 B 为当前槽后，执行无需镜像的操作：

```sh
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b --execute
```

先核对检查结果，再执行。要求实时 `taro`/`TB320FC`、显式序列号匹配、当前 B 槽和
准确 24 MiB 容量；擦除不能用 recovery 身份记录代替实时型号。无需全零 DTBO 镜像。
只擦除 `dtbo_b`，保留 `dtbo_a`、A、super、recovery 和校准。
擦除失败时先检查错误，不要自动改刷其他镜像。U-Boot 安装或恢复与 DTBO 准备成功后重启：

```sh
fastboot -s SERIAL reboot
```

启动后核对 EFI 代际、运行内核、root/ESP、SSH 和回退。EFI 加载不等于 Linux 健康启动。
以后依赖 recovery 维护前，应单独确认实际可用的 recovery。
