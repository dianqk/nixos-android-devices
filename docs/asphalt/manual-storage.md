# Asphalt / Y700 2023: prepare storage manually in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md)

The sizes and ordering below describe the default installation example. For an existing layout, configure the shared [storage settings](../configuration.md) before building system and recovery. GPT roles, controller and non-overlap checks remain mandatory.

Work from slot B only; preserve A and Android `super`. Linux uses separate outer-GPT partitions taken from the original userdata allocation: a 1 GiB FAT32 `linux-boot` ESP and an ext4 `linux` root. Converting stock storage erases Android userdata. Confirm the affected data first.

On the host, temporarily boot this device's recovery (first invocation is a check), then enter through ACM or NCM:

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.asphalt.recovery --out-link tmp/systemd-artifacts/devices.asphalt.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.asphalt.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.asphalt.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_ASPHALT_ACM
ssh root@172.16.43.1
```

ACM is a 115200/8N1 root console. The NCM host needs DHCP; recovery uses `172.16.43.1`. Before noninteractive SSH, set up a separate trusted `RECOVERY_HOST` alias following the [connection guide](../recovery.md#configure-and-connect). Inspect slot B, UFS and GPT inside recovery:

```sh
recovery status
cat /proc/bootconfig
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS
USERDATA=$(readlink -f /dev/disk/by-partlabel/userdata)
DISK=/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$USERDATA")/..")")
sfdisk --verify "$DISK"
sfdisk --dump "$DISK"
```

Asphalt has a **read-only** `recovery plan-uefi` command. The host example allocates 128 GiB in total to `linux-boot` plus `linux` from stock userdata. Use `existing` only to verify a completed EFI layout. Review `erases`, the preserved GPT prefix and the full `sfdisk` script before writing. Resolve the disk from the verified userdata partition; UFS disk letters are not stable.

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
# After reviewing the output and data loss, write the table manually:
ssh RECOVERY_HOST "sfdisk $DISK" < tmp/asphalt-target.sfdisk
ssh RECOVERY_HOST "sfdisk --verify $DISK && lsblk -b -o NAME,SIZE,PARTLABEL,PARTUUID,FSTYPE"
```

Confirm that the kernel sees the new partitions. If it does not, re-enter recovery with no disks mounted before continuing. In a recovery root shell, verify that `linux-boot` is exactly 1 GiB with ESP GPT type, and that `linux` is a Linux-type partition of at least 16 GiB outside `super`. The default root label is `NIXOS`.

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

The `plan-uefi` output matches the expected layout, but **only plans it**; it does not write GPT. `recovery format-root --confirm` formats the same existing `linux` partition after board, slot B, UFS, GPT, size, mount and post-format checks. It neither creates nor formats `linux-boot`. Raw manual commands bypass those checks and do not install the Nix closure, EFI files or U-Boot. Continue with the [installation guide](../u-boot-install.md).
