# Clover LTE：在 recovery 中准备存储

[English](manual-storage.md) · [首次安装](first-install.zh.md)

此设备没有 A/B。**不修改 GPT**：物理 `userdata` 是 ext4 `/`，物理 `system` 是 FAT32 `/boot`。U-Boot/EFI 安装、更新、回滚和独立 recovery 已在真机验证。准备过程会清除根分区，以及尚未格式化为 FAT 的 `system` 分区。recovery 按 eMMC 上唯一的原厂 GPT 名称找到各分区；`hardware.clover.storageRoles` 中可选的实测值必须来自本机。

在主机上，从 fastboot 临时启动与这台 Clover 配置匹配的 recovery。第一条 `mobile-device` 只检查，第二条启动。ACM 是 115200/8N1 root 控制台；NCM 主机取得 DHCP 地址后，SSH 地址为 `172.16.44.1`。

```sh
nix build .#devices.clover.recovery --out-link result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_CLOVER_ACM
ssh root@172.16.44.1
```

后续非交互命令先按[连接说明](../recovery.zh.md#configure-and-connect)建立单独的可信 `RECOVERY_HOST` 别名。在 recovery root shell 中检查分区：

```sh
for name in userdata system boot recovery misc; do
  part=$(readlink -f "/dev/disk/by-partlabel/$name")
  printf '%s %s ' "$name" "$part"
  blkid -p -s PART_ENTRY_UUID -s PART_ENTRY_NUMBER -s PART_ENTRY_OFFSET -o export "$part" | tr '\n' ' '
  blockdev --getsize64 "$part"
done
```

每个名称必须只出现一次，`boot` 和 `recovery` 为 64 MiB，`misc` 为 1 MiB，`system` 在 512 MiB 到 8 GiB 之间。如需固定本机分区，可将测量值填入 `hardware.clover.storageRoles.<role>.{partuuid,number,offset,bytes}`（见[设备指南](README.zh.md)），再同时重新构建系统和匹配的 recovery。`offset` 是 `PART_ENTRY_OFFSET` 报告的以 512 字节为单位的起点。

随后使用受检查的命令准备两个文件系统；每条命令先输出计划：

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

`format-root` 只将 root 角色格式化为带配置标签（默认 `NIXOS`）的 ext4；`storageRoles.root.fsUuid` 可保留指定的 UUID。`prepare-boot` 仅在 `system` 尚不是 FAT 时将其格式化为带配置启动标签（默认 `BOOT`，`androidDevices.boot.uefi.label`）的 FAT32，并保留原厂 GPT type；它要求根分区已格式化且为空或其中的 store 能通过校验，并在首次安装完成前保留待处理标记。两条命令都不会创建或调整分区。这还不是完整安装：Nix 闭包、EFI 文件和 `boot` 中的 U-Boot 仍需安装，见[安装指南](../u-boot-install.zh.md)。
