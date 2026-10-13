# Clover LTE first installation

[中文](first-install.zh.md)

Read the [U-Boot installation workflow](../u-boot-install.md) and [device configuration](README.md) first.

After preparing the partitions below, use the [shared first installer](../initial-install.md) to import the closure, install EFI and write matching U-Boot firmware.

Clover uses physical system as FAT `/boot` and userdata as ext4 root, without A/B. U-Boot has not been tested on hardware. Recovery refuses root, firmware, recovery and misc operations until `hardware.clover.storageRoles` holds this tablet's measured `userdata`, `boot`, `recovery` and `misc` partitions. The FAT `/boot` is the unique `system` partition on the eMMC.

See [Clover storage preparation](manual-storage.md) for temporary recovery boot, ACM/NCM access, measuring the partitions and the checked `format-root` and `prepare-boot` commands.
