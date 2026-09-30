# Asphalt / Y700 2023：recovery 中手动准备分区

[English](manual-storage.md) · [首次安装](first-install.zh.md)

下列大小与顺序描述默认首装示例。已有其他布局时，构建系统和 recovery 前先配置共用的[存储选项](../configuration.zh.md)。GPT 分区角色、控制器和非重叠校验仍保留。

此设备仅从 B 槽操作；保留 A 和 Android `super`。Linux 使用外层 GPT 的独立 1 GiB `linux-boot` FAT32 ESP 与 `linux` ext4 根，均从原 `userdata` 分配范围取得。原厂布局转为此布局会清除 Android userdata。先确认数据丢失范围。

在主机临时启动本机 recovery（首条仅检查），然后用 ACM 控制台或 NCM SSH 进入：

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.asphalt.recovery --out-link tmp/systemd-artifacts/devices.asphalt.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.asphalt.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.asphalt.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_ASPHALT_ACM
ssh root@172.16.43.1
```

ACM 是 115200/8N1 root 控制台。NCM 主机需要 DHCP；recovery 地址为 `172.16.43.1`。后续非交互命令先按[连接说明](../recovery.md#configure-and-connect)建立独立 SSH 主机密钥信任及 `RECOVERY_HOST` 别名。先在 recovery 核对 B 槽、UFS 和现有 GPT：

```sh
recovery status
cat /proc/bootconfig
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS
USERDATA=$(readlink -f /dev/disk/by-partlabel/userdata)
DISK=/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$USERDATA")/..")")
sfdisk --verify "$DISK"
sfdisk --dump "$DISK"
```

Asphalt 提供**只读** `recovery plan-uefi`。以下主机命令以原厂布局给 Android 留出空间，并让 `linux-boot` + `linux` 共用 128 GiB。`existing` 仅用于检查已完成的 EFI 布局。计划中的 `erases`、GPT 前缀和完整 `sfdisk` 文本必须先人工审查。从已核验的 userdata 分区解析所属磁盘；UFS 磁盘字母并不稳定。

```sh
set -e
mkdir -p tmp
ssh RECOVERY_HOST 'recovery plan-uefi 128GiB' > tmp/asphalt-plan.json
jq '{state,action,before_sha256,erases,partitions}' tmp/asphalt-plan.json
jq -r '.sfdisk' tmp/asphalt-plan.json > tmp/asphalt-target.sfdisk
DISK=$(jq -r '.sfdisk | split("\n")[] | select(startswith("device: ")) | ltrimstr("device: ")' tmp/asphalt-plan.json)
ssh RECOVERY_HOST "sfdisk --dump $DISK" > tmp/asphalt-before.sfdisk
test "$(sha256sum tmp/asphalt-before.sfdisk | cut -d' ' -f1)" = "$(jq -r .before_sha256 tmp/asphalt-plan.json)"
ssh RECOVERY_HOST "sfdisk --no-act $DISK" < tmp/asphalt-target.sfdisk
# 核对上述输出和数据丢失范围后，手动执行写入：
ssh RECOVERY_HOST "sfdisk $DISK" < tmp/asphalt-target.sfdisk
ssh RECOVERY_HOST "sfdisk --verify $DISK && lsblk -b -o NAME,SIZE,PARTLABEL,PARTUUID,FSTYPE"
```

分区表写入后，确认内核已识别新分区；若没有，在无挂载状态下重新进入 recovery，再继续。以下命令在 recovery root shell 中执行；先确认 `linux-boot` 恰好 1 GiB、GPT type 为 ESP，`linux` 为 Linux type 且至少 16 GiB，分区不在 `super` 内。默认根标签为 `NIXOS`。

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

`plan-uefi` 生成的目标布局与项目预期一致，但它**只规划，不自动写 GPT**。`recovery format-root --confirm` 只在已有合规布局上格式化同一个 `linux` 分区，并增加机型、B 槽、UFS、GPT、容量、挂载状态和格式后检查；它不创建 `linux-boot`，也不格式化 FAT。原始手工命令绕过这些检查，且不会安装 Nix 闭包、EFI 文件或 U-Boot；后续按[统一安装流程](../u-boot-install.zh.md)逐项完成。
