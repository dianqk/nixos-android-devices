# Polaris 首次安装

[English](first-install.md) · [设备指南](README.zh.md) · [手工存储命令](manual-storage.zh.md)

Polaris 使用物理 `system` 作为 FAT32 `/boot`、`userdata` 作为 ext4 `/`，
`boot` 存放 U-Boot。GPT 几何和分区类型保持不变。此设备**没有 A/B 槽位**，
使用不带槽位后缀的 `boot` 和 `recovery`。

需要已解锁的手机、启用 Nix flakes 的 Linux 构建电脑、USB fastboot/SSH 连接，
以及 userdata 上足够容纳系统闭包并额外预留至少 1 GiB 的空间。格式化会清除目标分区。

## 识别本机

在本仓库中构建并临时启动 RAM recovery。将 `FASTBOOT_SERIAL` 替换为
`fastboot devices` 显示的手机序列号。第一条 fastboot 命令检查目标和镜像，
加 `--execute` 才会启动。

```sh
nix build .#devices.polaris.recovery -o tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery --execute
```

按[连接指南](../recovery.md)配置 `RECOVERY_HOST` 及其主机密钥。
Recovery 启动时不挂载或写入分区。检查布局：

```sh
ssh -T RECOVERY_HOST 'lsblk -b -o NAME,SIZE,PARTUUID,PARTLABEL,START,FSTYPE,LABEL,UUID'
```

确认内置 UFS 上的 `system`、`userdata`、`boot`、`misc` GPT 名称各自唯一。
重启工具要求 `misc` 为 4 MiB。Recovery 会检查型号、控制器、分区名和文件系统标签。
需要逐机 UUID 与几何检查时，按实测值填写
[`storage-roles.example.sh`](../../devices/polaris/storage-roles.example.sh)，
通过 `hardware.polaris.storageRolesFile` 指定。

## 构建配套系统与 recovery

复制[消费 flake](../../examples/consumer/flake.nix)，按[配置指南](../configuration.zh.md)
选择 `device = "polaris"`、构建电脑架构和唯一 USB 序列号，并加入 SSH 公钥。
系统和 recovery 共用根标签（默认 `NIXOS`）及可选存储契约。示例启动控制台系统，
无线和音频默认关闭。

在自己的配置目录中，先用 Git 跟踪源文件，再构建：

```sh
nix build .#system -o tmp/systemd-artifacts/system
nix build .#bootstrap-info -o tmp/systemd-artifacts/bootstrap-info
nix build .#recovery -o tmp/systemd-artifacts/recovery
nix profile install .#mobile-device
```

三个输出须来自同一锁定配置；系统已包含匹配的 U-Boot 镜像。

## 从 RAM recovery 安装

临时启动自己配置的 recovery，再次连接 SSH：

```sh
mobile-device --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/recovery
mobile-device --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/recovery --execute
```

如果 userdata 不是标签匹配的空 ext4 文件系统，检查后显式格式化。
**此操作会清除 userdata。**

```sh
mobile-device recovery --target RECOVERY_HOST format-userdata
mobile-device recovery --target RECOVERY_HOST format-userdata --execute
```

将物理 `system` 准备为 FAT32。匹配的 FAT 只检查并保留，否则清除其内容；GPT 几何不变。

```sh
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

检查并安装系统：

```sh
SYSTEM=$(readlink -f tmp/systemd-artifacts/system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info --execute
```

[首次安装器](../initial-install.zh.md)校验闭包、安装 EFI 文件，最后将 U-Boot
写入 `boot`。安装未完成时会阻止重启；留在 recovery，按安装器的失败处理说明修复。
成功后执行：

```sh
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

验证 SSH、[代际菜单](boot-menu.md)和独立 RAM recovery。
后续[系统更新](../usb-signaller.md)维护 EFI 文件，不重写 U-Boot；
recovery 的 `deploy` 用于更新已有系统。
