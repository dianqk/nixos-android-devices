# Clover LTE: prepare storage manually in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md) · [Storage contract example](../../devices/clover/storage-roles.example.sh)

This device has no A/B slots. **Keep the GPT unchanged**: physical `userdata` is ext4 `/`, and physical `system` is FAT32 `/boot`. U-Boot is not yet hardware-validated on Clover. These manual formats erase both existing partitions. Measure this tablet's eMMC first and fill `hardware.clover.storageRolesFile` with its actual partition numbers, starts, sizes and PARTUUIDs. The default placeholder contract refuses recovery writes; values from another tablet are not suitable.

On the host, temporarily boot recovery built for this Clover. The first `mobile-device` invocation checks, and the second boots. ACM is a 115200/8N1 root console. After NCM DHCP, recovery SSH is at `172.16.44.1`.

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.clover.recovery --out-link tmp/systemd-artifacts/devices.clover.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.clover.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.clover.recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_CLOVER_ACM
ssh root@172.16.44.1
```

For later noninteractive commands, configure a separate trusted `RECOVERY_HOST` alias using the [connection guide](../recovery.md#configure-and-connect). In a recovery root shell, inspect partition identities, their eMMC parent, sizes and mount state, then compare every field with the completed per-tablet contract:

```sh
recovery status
ROOT=$(readlink -f /dev/disk/by-partlabel/userdata)
ESP=$(readlink -f /dev/disk/by-partlabel/system)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,START,FSTYPE,LABEL,MOUNTPOINTS "$ROOT" "$ESP"
blkid -p "$ROOT" "$ESP"
```

Only after those identities match this tablet's measured contract and both partitions are unmounted, format the existing partitions. `NIXOS` is the default root label. If `rootUUID` is configured, add `-U` with that same UUID to manual `mke2fs`. The FAT label `NIXOS_BOOT` is illustrative; the installed `/boot` must pass FAT checks. Physical `system` keeps its vendor GPT type; it is not a newly created standard ESP.

```sh
mke2fs -F -t ext4 -m 0 -L NIXOS "$ROOT"
mkfs.fat -F 32 -n NIXOS_BOOT "$ESP"
sync
e2fsck -fn "$ROOT"
fsck.fat -n "$ESP"
blkid -p "$ROOT" "$ESP"
```

Manual `mke2fs` uses the same `userdata` partition and ext4 arguments as `recovery format-root --confirm`; the checked command also requires a complete storage contract and verifies board, eMMC, GPT, capacity, lack of mounts and post-format state. **It does not format `system` or create partitions**. The manual FAT step has no matching checked automatic command. This is not a complete installation: the Nix closure, EFI files and U-Boot in `boot` still need installation; see the [installation guide](../u-boot-install.md).
