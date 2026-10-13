# Polaris: prepare storage in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md) · [USB recovery connection](../recovery.md)

This device has no A/B slots. **Keep the GPT unchanged**: physical `userdata` is ext4 `/`, and physical `system` is FAT32 `/boot`. These commands erase the existing contents of both partitions. Check the phone and the root label in your build first.

On the host, temporarily boot a recovery image built for this phone. The first `mobile-device` invocation checks; the second boots it:

```sh
nix build .#devices.polaris.recovery --out-link result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

ACM and NCM are both available. Open the phone's `/dev/serial/by-id/` port at 115200/8N1 for the ACM root console. After the host obtains an NCM DHCP address, connect to recovery at `172.16.42.1`. Full recovery retains its own SSH identity on a verified Linux root when available, otherwise using a temporary RAM key; first configure a separate trusted `RECOVERY_HOST` alias as described in the [connection guide](../recovery.md#configure-and-connect).

```sh
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_POLARIS_ACM
ssh root@172.16.42.1
ssh RECOVERY_HOST 'lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,UUID,MOUNTPOINTS'
```

Run the following in a **root shell inside recovery**, via either ACM or `ssh RECOVERY_HOST`. Confirm unique `system` and `userdata` partitions on the built-in UFS, with expected sizes and no mounts:

```sh
recovery status
ROOT=$(readlink -f /dev/disk/by-partlabel/userdata)
ESP=$(readlink -f /dev/disk/by-partlabel/system)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS "$ROOT" "$ESP"
blkid -p "$ROOT" "$ESP"
```

After checking, format the **existing partitions** with the checked commands; each prints its plan first. GPT geometry stays unchanged.

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

`format-root` formats `userdata` as ext4 with the configured label and, if set, `storageRoles.root.fsUuid`. `prepare-boot` formats `system` as FAT32 (label `NIXOS_BOOT`) only when it is not already FAT; it requires a formatted root that is empty or holds a store that verifies, and leaves a pending marker until the first installation completes. Formatting alone does not install the Nix closure, EFI files or U-Boot; use the [checked `install-initial` flow](first-install.md#install-from-ram-recovery) for the complete first installation.
