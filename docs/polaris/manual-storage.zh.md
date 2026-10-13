# Polaris：在 recovery 中准备存储

[English](manual-storage.md) · [首次安装](first-install.zh.md) · [USB recovery 连接说明](../recovery.zh.md)

此设备没有 A/B。**不修改 GPT**：物理 `userdata` 是 ext4 `/`，物理 `system` 是 FAT32 `/boot`。以下操作会清除这两个分区原有内容；先核对本机数据和构建配置中的根标签。

在主机上，从 fastboot 临时启动**与本机配置匹配**的 recovery 镜像。`mobile-device` 第一条只检查，第二条才启动：

```sh
nix build .#devices.polaris.recovery --out-link result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

ACM 和 NCM 同时可用。ACM 使用主机 `/dev/serial/by-id/` 下对应设备的端口，以 115200/8N1 打开 root 控制台；NCM 主机取得 DHCP 地址后，通过 recovery 的 `172.16.42.1` 登录。完整 recovery 在可用的已验证 Linux 根分区保留独立 SSH 身份，否则使用 RAM 临时密钥；先按[连接说明](../recovery.zh.md#configure-and-connect)建立单独的 `RECOVERY_HOST` 别名和信任。

```sh
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_POLARIS_ACM
ssh root@172.16.42.1
ssh RECOVERY_HOST 'lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,UUID,MOUNTPOINTS'
```

以下命令在 **recovery 的 root shell** 中执行，既可经 ACM，也可经 NCM 的 `ssh RECOVERY_HOST` 进入。先确认 `system`、`userdata` 在内置 UFS 上各只有一个、没有挂载，且大小与实机相符：

```sh
recovery status
ROOT=$(readlink -f /dev/disk/by-partlabel/userdata)
ESP=$(readlink -f /dev/disk/by-partlabel/system)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS "$ROOT" "$ESP"
blkid -p "$ROOT" "$ESP"
```

确认之后，使用受检查的命令格式化**现有分区**；每条命令先输出计划。GPT 位置和大小不变。

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

`format-root` 将 `userdata` 格式化为带配置标签的 ext4，并在设置时使用 `storageRoles.root.fsUuid`。`prepare-boot` 仅在 `system` 尚不是 FAT 时将其格式化为 FAT32（标签 `NIXOS_BOOT`）；它要求根分区已格式化且为空或其中的 store 能通过校验，并在首次安装完成前保留待处理标记。格式化本身不会安装 Nix 闭包、EFI 文件或 U-Boot；完成整套首装应使用[受检查的 `install-initial` 流程](first-install.zh.md#从-ram-recovery-安装)。
