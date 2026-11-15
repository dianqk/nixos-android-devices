# Clover LTE: prepare storage in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md)

This device has no A/B slots. **Keep the GPT unchanged**: physical `userdata` is ext4 `/`, and physical `system` is FAT32 `/boot`. U-Boot/EFI installation, updates, rollback and independent recovery are verified on hardware. Preparation erases the root and, unless it is already FAT, the `system` partition. Recovery finds each partition by its unique stock GPT name on the eMMC. Optional measured values in `hardware.clover.storageRoles` must come from this tablet.

On the host, temporarily boot recovery built for this Clover. The first `mobile-device` invocation checks, and the second boots. ACM is a 115200/8N1 root console. After NCM DHCP, recovery SSH is at `172.16.44.1`.

```sh
nix build .#devices.clover.recovery --out-link result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_CLOVER_ACM
ssh root@172.16.44.1
```

For later noninteractive commands, configure a separate trusted `RECOVERY_HOST` alias using the [connection guide](../recovery.md#configure-and-connect). Check the partitions from the recovery root shell:

```sh
for name in userdata system boot recovery misc; do
  part=$(readlink -f "/dev/disk/by-partlabel/$name")
  printf '%s %s ' "$name" "$part"
  blkid -p -s PART_ENTRY_UUID -s PART_ENTRY_NUMBER -s PART_ENTRY_OFFSET -o export "$part" | tr '\n' ' '
  blockdev --getsize64 "$part"
done
```

Each name must appear once, `boot` and `recovery` must be 64 MiB and `misc` 1 MiB; `system` must be 512 MiB to 8 GiB. To pin this tablet's partitions, optionally enter the values in `hardware.clover.storageRoles.<role>.{partuuid,number,offset,bytes}` (see the [device guide](README.md)), then rebuild both the system and a matching recovery. `offset` is the 512-byte start reported as `PART_ENTRY_OFFSET`.

Then prepare both filesystems with the checked commands; each prints its plan first:

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

`format-root` formats only the root role as ext4 with the configured label (default `NIXOS`; `storageRoles.root.fsUuid` keeps a chosen UUID). `prepare-boot` formats `system` as FAT32 with the configured boot label (default `BOOT`, `androidDevices.boot.uefi.label`), keeping its vendor GPT type, only when it is not already FAT; it requires a formatted root that is empty or holds a store that verifies, and leaves a pending marker until the first installation completes. Neither command creates or resizes partitions. This is not a complete installation: the Nix closure, EFI files and U-Boot in `boot` still need installation; see the [installation guide](../u-boot-install.md).
