# Polaris：recovery 中手动准备分区

[English](manual-storage.md) · [首次安装](first-install.zh.md) · [USB recovery 连接说明](../recovery.md)

此设备没有 A/B。**不修改 GPT**：物理 `userdata` 是 ext4 `/`，物理 `system` 是 FAT32 `/boot`。以下操作会清除这两个分区原有内容；先核对本机数据和构建配置中的根标签。示例假设默认根标签 `NIXOS`、FAT 标签 `NIXOS_BOOT`。

在主机上，从 fastboot 临时启动**与本机配置匹配**的 recovery 镜像。`mobile-device` 第一条只检查，第二条才启动：

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.polaris.recovery --out-link tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery --execute
```

ACM 和 NCM 同时可用。ACM 使用主机 `/dev/serial/by-id/` 下对应设备的端口，以 115200/8N1 打开 root 控制台；NCM 主机取得 DHCP 地址后，通过 recovery 的 `172.16.42.1` 登录。SSH 主机密钥每次 recovery 启动会变化，先按[连接说明](../recovery.md#configure-and-connect)建立单独的 `RECOVERY_HOST` 别名和信任。

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

确认之后，手工格式化**现有分区**，不运行 `sfdisk`。若自定义存储契约固定了文件系统 UUID，须把相同的 `mke2fs -U` / `mkfs.fat -i` 参数加到手动命令；否则不要复制此默认示例的 UUID 行为。

```sh
mke2fs -F -t ext4 -m 0 -L NIXOS "$ROOT"
mkfs.fat -F 32 -n NIXOS_BOOT "$ESP"
sync
e2fsck -fn "$ROOT"
fsck.fat -n "$ESP"
blkid -p "$ROOT" "$ESP"
```

格式化的目标、文件系统和默认标签与自动流程的 `recovery format-userdata --confirm`、`recovery prepare-boot --confirm` 相同。**原始手工命令不等价于自动流程**：自动工具还检查机型、内置 UFS、分区名唯一性和文件系统状态；若现有 FAT 已匹配，`prepare-boot` 只检查、不重建。需要重建时，它先验证根中已有 store 或新空根，并写入待安装标记。手工格式化也不会安装 Nix 闭包、EFI 文件或 U-Boot；完成整套首装应使用[受检查的 `install-initial` 流程](first-install.zh.md#从-ram-recovery-安装)。
