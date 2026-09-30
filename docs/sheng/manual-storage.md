# Sheng / Pad 6S Pro: prepare storage manually in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md) · [Installation flow](../u-boot-install.md)

The sizes and ordering below describe the default installation example. For an existing layout, configure the shared [storage settings](../configuration.md) before building system and recovery. GPT roles, controller and non-overlap checks remain mandatory.

Work from slot B only; preserve A and `super`. The target outer-GPT layout has three neighboring partitions from the original userdata allocation: Android `userdata`, ext4 `linux` (at least 16 GiB), and a final 1 GiB FAT32 `linux-boot` ESP. **Do not write a table to `super` or nest a disk table inside `userdata`.** If stock Android userdata fills that allocation, simply shortening its GPT entry will corrupt it. Free Linux space only after deliberately clearing and preparing to recreate Android userdata, or after a device-specific offline filesystem shrink and verification. To retain an existing `linux` filesystem, first shrink and verify ext4 offline; do not use this fresh-install repartitioning example.

On the host, temporarily boot the recovery image built for this tablet. The first `mobile-device` invocation checks the image and target; the second boots it. ACM is a 115200/8N1 root console. After NCM DHCP, recovery SSH uses `172.16.45.1`.

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.sheng.recovery --out-link tmp/systemd-artifacts/devices.sheng.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.sheng.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.sheng.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_SHENG_ACM
ssh root@172.16.45.1
```

Before later host commands, establish a separate trusted `RECOVERY_HOST` alias following the [connection guide](../recovery.md#configure-and-connect). In recovery, inspect slot B, UFS, GPT and mounts. `/dev/sda` is an example; first verify which disk contains `userdata`.

```sh
recovery status
cat /proc/bootconfig
readlink -f /dev/disk/by-partlabel/userdata
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS
sfdisk --verify /dev/sda
sfdisk --dump /dev/sda
```

Sheng has **no generic automatic GPT planner or writer**. This manual command framework saves the full original table on the host. Edit a copy to reduce `userdata` and add outer-GPT `linux` and final `linux-boot` entries after it; keep earlier entries, UUIDs and starts unchanged. Calculate new starts and lengths from this tablet's `sfdisk --json` result, its 4096-byte logical sectors and `lastlba`. A 1 GiB ESP is exactly **262144 sectors**. Give new entries distinct UUIDs; use Linux type `0FC63DAF-8483-4772-8E79-3D69D8477DE4` and ESP type `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`. Check the order `userdata`, `linux`, `linux-boot`, non-overlap and usable bounds. Do not rebuild this table if existing Linux data must be retained.

```sh
set -e
mkdir -p tmp
ssh RECOVERY_HOST 'sfdisk --json /dev/sda' > tmp/sheng-before.json
ssh RECOVERY_HOST 'sfdisk --dump /dev/sda' > tmp/sheng-before.sfdisk
cp tmp/sheng-before.sfdisk tmp/sheng-target.sfdisk
${EDITOR:-vi} tmp/sheng-target.sfdisk
diff -u tmp/sheng-before.sfdisk tmp/sheng-target.sfdisk || test "$?" -eq 1
ssh RECOVERY_HOST 'sfdisk --no-act /dev/sda' < tmp/sheng-target.sfdisk
# Only after safely shrinking or preparing to recreate userdata, and checking this tablet's plan:
ssh RECOVERY_HOST 'sfdisk /dev/sda' < tmp/sheng-target.sfdisk
ssh RECOVERY_HOST 'sfdisk --verify /dev/sda && lsblk -b -o NAME,SIZE,PARTLABEL,PARTUUID,FSTYPE'
```

If the kernel does not see the new entries, re-enter recovery with all disks unmounted. In its root shell, first verify the ESP type and exact 1 GiB size of `linux-boot`, the Linux type and at least 16 GiB size of `linux`, and both devices' disk identity. Format with the root label configured for the installed system; `NIXOS` is the default.

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

The manual `mke2fs` target and arguments match `recovery format-root --confirm`; the checked command additionally validates the board, slot B, UFS, GPT order/types/sizes, lack of mounts and post-format state. It **does not create GPT partitions or format the FAT ESP**. The manual table write and format are therefore not one checked transaction, nor do they install the Nix closure, EFI files or `boot_b` U-Boot. Continue with the [installation guide](../u-boot-install.md).
