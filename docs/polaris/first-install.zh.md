# Polaris 首次安装

[English](first-install.md) · [设备指南](README.zh.md) · [存储准备](manual-storage.zh.md)

Polaris 使用物理 `system` 作为 FAT32 `/boot`、`userdata` 作为 ext4 `/`，
`boot` 存放 U-Boot。GPT 几何和分区类型保持不变。此设备**没有 A/B 槽位**，
使用不带槽位后缀的 `boot` 和 `recovery`。

需要已解锁的手机、启用 Nix flakes 的 Linux 构建电脑、USB fastboot/SSH 连接，
以及至少 16 GiB 的 userdata 分区（`androidDevices.recovery.minimumRootBytes` 默认值），
且能容纳系统闭包并额外预留 1 GiB。格式化会清除目标分区。

## 安装前的 Android 底包

**Polaris 的适配基线是适用于 `polaris` 的 LineageOS 22.2 最新构建。
安装 NixOS 前先准备这一版本。** 此处“最新”指 22.2 系列内的最新构建，
不指更新的 LineageOS 大版本；本指南不固定具体构建日期。

替换 Android 前，核对并记录已安装版本：

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.lineage.version
adb -s SERIAL shell getprop ro.build.fingerprint
```

确认设备为 `polaris`、LineageOS 版本为 `22.2-…`。在为 NixOS 格式化
`system` 和 `userdata` 前完成 Android 准备；Polaris 没有可保留 Android
的第二个槽位。NixOS 更新不会安装或更新 LineageOS。

## 识别本机

在本仓库中构建并临时启动 RAM recovery。将 `FASTBOOT_SERIAL` 替换为
`fastboot devices` 显示的手机序列号。第一条 fastboot 命令检查目标和镜像，
加 `--execute` 才会启动。

```sh
nix build .#devices.polaris.recovery -o result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

按[连接指南](../recovery.zh.md)配置 `RECOVERY_HOST` 及其主机密钥。
完整 Recovery 启动时可短暂访问已有 Linux 根分区以保存或读取 SSH 身份；
不会格式化分区，完成后不保留目标挂载。检查布局：

```sh
ssh -T RECOVERY_HOST 'lsblk -b -o NAME,SIZE,PARTUUID,PARTLABEL,START,FSTYPE,LABEL,UUID'
```

确认内置 UFS 上的 `system`、`userdata`、`boot`、`misc` GPT 名称各自唯一。
recovery 请求要求 `misc` 为 4 MiB。Recovery 会检查型号、控制器、分区名、内核分区几何
信息和文件系统标签。需要逐机精确检查时，将实测值填入 `hardware.polaris.storageRoles`
（见[单槽设备](../recovery.zh.md#single-slot-devices-clover-and-polaris)）。

## 构建配套系统与 recovery

复制[消费 flake](../../examples/consumer/flake.nix)，按[配置指南](../configuration.zh.md)
选择 `device = "polaris"`、构建电脑架构和唯一 USB 序列号，并加入 SSH 公钥。
系统和 recovery 共用根标签（默认 `NIXOS`）及可选的 `storageRoles`。示例启动控制台系统，
无线和音频默认关闭。

在自己的配置目录中，先用 Git 跟踪源文件，再构建：

```sh
nix build .#system -o result-system
nix build .#bootstrap-info -o result-bootstrap-info
nix build .#recovery -o result-recovery
nix profile install .#mobile-device
```

三个输出须来自同一锁定配置；系统已包含匹配的 U-Boot 镜像。

## 从 RAM recovery 安装

临时启动自己配置的 recovery，再次连接 SSH：

```sh
mobile-device --serial FASTBOOT_SERIAL fastboot boot result-recovery
mobile-device --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

如果 userdata 不是标签匹配的空 ext4 文件系统，检查后显式格式化。
**此操作会清除 userdata。**

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
```

将物理 `system` 准备为 FAT32。匹配的 FAT 只检查并保留，否则清除其内容；GPT 几何不变。

```sh
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

检查并安装系统：

```sh
SYSTEM=$(readlink -f result-system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info --execute
```

[首次安装器](../initial-install.zh.md)校验闭包、安装 EFI 文件，最后将 U-Boot
写入 `boot`。安装未完成时会阻止重启；留在 recovery，按安装器的失败处理说明修复。
成功后执行：

```sh
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

验证 SSH、[代际菜单](boot-menu.zh.md)和独立 RAM recovery。
后续[系统更新](../usb-signaller.zh.md)维护 EFI 文件，不重写 U-Boot；
recovery 的 `deploy` 用于更新已有系统。
