# Clover LTE：recovery 中手动准备分区

[English](manual-storage.md) · [首次安装](first-install.zh.md) · [存储契约示例](../../devices/clover/storage-roles.example.sh)

此设备没有 A/B。**不修改 GPT**：物理 `userdata` 是 ext4 `/`，物理 `system` 是 FAT32 `/boot`。U-Boot 尚未在 Clover 真机验证。本页的手工格式化会清除这两个现有分区；先测量本机 eMMC，并用实测分区号、起点、容量和 PARTUUID 填写 `hardware.clover.storageRolesFile`。默认占位契约会拒绝 recovery 写入，不能用其他设备的值代替。

在主机上，从 fastboot 临时启动与这台 Clover 配置匹配的 recovery。第一条 `mobile-device` 只检查，第二条启动。ACM 是 115200/8N1 root 控制台；NCM 主机取得 DHCP 地址后，SSH 地址为 `172.16.44.1`。

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.clover.recovery --out-link tmp/systemd-artifacts/devices.clover.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.clover.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.clover.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_CLOVER_ACM
ssh root@172.16.44.1
```

后续非交互命令先按[连接说明](../recovery.md#configure-and-connect)为 recovery 建立单独的 `RECOVERY_HOST` SSH 别名和主机密钥信任。在 recovery root shell 中检查分区身份、所属 eMMC、实际容量和挂载状态，再与已填写的存储契约逐项比较：

```sh
recovery status
ROOT=$(readlink -f /dev/disk/by-partlabel/userdata)
ESP=$(readlink -f /dev/disk/by-partlabel/system)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,START,FSTYPE,LABEL,MOUNTPOINTS "$ROOT" "$ESP"
blkid -p "$ROOT" "$ESP"
```

仅当上述身份与本机实测契约一致、两个分区均未挂载时，才手动格式化现有分区。根标签 `NIXOS` 是模块默认值；若配置了 `rootUUID`，手动 `mke2fs` 必须加 `-U` 和同一个 UUID。FAT 标签示例为 `NIXOS_BOOT`，安装时仍须满足 `/boot` 的 FAT 验证；此物理 `system` 保留原厂 GPT type，不是另建的标准 ESP。

```sh
mke2fs -F -t ext4 -m 0 -L NIXOS "$ROOT"
mkfs.fat -F 32 -n NIXOS_BOOT "$ESP"
sync
e2fsck -fn "$ROOT"
fsck.fat -n "$ESP"
blkid -p "$ROOT" "$ESP"
```

手工 `mke2fs` 与 `recovery format-root --confirm` 使用相同的 `userdata` 分区和 ext4 参数；自动命令还要求完整存储契约，检查机型、eMMC、GPT、容量、无挂载及格式后结果。**它不会格式化 `system`，也不会创建分区**。手工 FAT 步骤没有对应的受检查自动命令；这组手工操作不等于完整首装，仍须安装 Nix 闭包、EFI 文件和 `boot` 中的 U-Boot，见[统一安装流程](../u-boot-install.zh.md)。
