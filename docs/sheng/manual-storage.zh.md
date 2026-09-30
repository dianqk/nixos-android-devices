# Sheng / Pad 6S Pro：recovery 中手动准备分区

[English](manual-storage.md) · [首次安装](first-install.zh.md) · [统一安装流程](../u-boot-install.zh.md)

下列大小与顺序描述默认首装示例。已有其他布局时，构建系统和 recovery 前先配置共用的[存储选项](../configuration.zh.md)。GPT 分区角色、控制器和非重叠校验仍保留。

仅从 B 槽操作，保留 A 和 `super`。目标是外层 GPT 中原 `userdata` 分配范围内的三个相邻分区：Android `userdata`、ext4 `linux`（至少 16 GiB）、末尾 1 GiB FAT32 `linux-boot` ESP。**不要把分区表写到 `super` 或在 `userdata` 内嵌套磁盘表。** 若原厂 Android userdata 占满该范围，直接缩小 GPT 会损坏它；只有在已清空并准备重建 Android userdata，或已通过本机专用流程离线缩小并验证其文件系统后，才可划出 Linux 空间。已有 `linux` 中的数据如需保留，也须先离线缩小 ext4 并验证，不能照搬首装步骤。

主机上临时启动与本机配置匹配的 recovery。第一条 `mobile-device` 仅检查镜像和目标，第二条启动。ACM 是 115200/8N1 root 控制台；NCM 主机取得 DHCP 地址后，SSH 连接 `172.16.45.1`。

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.sheng.recovery --out-link tmp/systemd-artifacts/devices.sheng.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.sheng.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.sheng.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_SHENG_ACM
ssh root@172.16.45.1
```

后续主机命令先按[连接说明](../recovery.md#configure-and-connect)建立 recovery 专用 `RECOVERY_HOST` 别名和主机密钥信任。在 recovery shell 中核对 B 槽、UFS、现有 GPT 和挂载状态。以下只以 `/dev/sda` 为示例；先用 `readlink` 确认 `userdata` 实际所在盘。

```sh
recovery status
cat /proc/bootconfig
readlink -f /dev/disk/by-partlabel/userdata
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS
sfdisk --verify /dev/sda
sfdisk --dump /dev/sda
```

Sheng **没有通用的自动 GPT 规划/写入器**。以下是手动制作计划的命令框架：在主机保存完整原表，复制后编辑副本中的 `userdata` 大小，并在其尾后加入 `linux` 和末尾 `linux-boot` 两条外层 GPT 记录；原有前缀、分区 UUID 和起点保持原样。新扇区起点/大小须由本机 `sfdisk --json` 的 4096 字节逻辑扇区和 `lastlba` 算出，1 GiB ESP 恰好是 **262144 个扇区**。为新条目生成不同的 UUID；`linux` type 为 `0FC63DAF-8483-4772-8E79-3D69D8477DE4`，`linux-boot` type 为 `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`。核对新条目顺序为 `userdata`、`linux`、`linux-boot`，无重叠且均在可用范围内。已有 Linux 数据需保留时，不执行此重建计划。

```sh
set -e
mkdir -p tmp
ssh RECOVERY_HOST 'sfdisk --json /dev/sda' > tmp/sheng-before.json
ssh RECOVERY_HOST 'sfdisk --dump /dev/sda' > tmp/sheng-before.sfdisk
cp tmp/sheng-before.sfdisk tmp/sheng-target.sfdisk
${EDITOR:-vi} tmp/sheng-target.sfdisk
diff -u tmp/sheng-before.sfdisk tmp/sheng-target.sfdisk || test "$?" -eq 1
ssh RECOVERY_HOST 'sfdisk --no-act /dev/sda' < tmp/sheng-target.sfdisk
# 仅在 userdata 已安全缩小或准备重建，且计划匹配本机后执行：
ssh RECOVERY_HOST 'sfdisk /dev/sda' < tmp/sheng-target.sfdisk
ssh RECOVERY_HOST 'sfdisk --verify /dev/sda && lsblk -b -o NAME,SIZE,PARTLABEL,PARTUUID,FSTYPE'
```

若内核尚未识别新分区，在无挂载状态下重新进入 recovery。以下在 recovery root shell 中执行；先核对 `linux-boot` 的 ESP type、1 GiB 容量、`linux` 的 Linux type、至少 16 GiB 容量和实际磁盘身份，然后格式化。根标签须与系统配置一致，示例为默认 `NIXOS`。

```sh
ESP=$(readlink -f /dev/disk/by-partlabel/linux-boot)
ROOT=$(readlink -f /dev/disk/by-partlabel/linux)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,MOUNTPOINTS "$ESP" "$ROOT"
blkid -p "$ESP" "$ROOT"
mkfs.fat -F 32 -n NIXOS_BOOT "$ESP"
mke2fs -F -t ext4 -m 0 -L NIXOS "$ROOT"
sync
fsck.fat -n "$ESP"
e2fsck -fn "$ROOT"
```

手工 `mke2fs` 的目标和参数与 `recovery format-root --confirm` 相同；自动命令还核对机型、B 槽、UFS、GPT 顺序/类型/大小、无挂载及格式后状态。自动命令**不创建 GPT 分区，也不格式化 FAT ESP**；本页的手工写表与格式化因此不是同一个受检查的事务，也不安装 Nix 闭包、EFI 文件或 `boot_b` U-Boot。后续按[统一安装流程](../u-boot-install.zh.md)完成。
