# Clover LTE first installation

[中文](first-install.zh.md)

Read the [U-Boot installation workflow](../u-boot-install.md) and [device configuration](README.md) first.

Use the [separate firmware procedure](../u-boot-install.md#build-and-flash-u-boot-independently)
if compatible U-Boot is missing. After preparing the partitions below, use the
[shared first installer](../initial-install.md) to import the closure and install its EFI generation.

Clover uses physical system as FAT `/boot` and userdata as ext4 root, without A/B. U-Boot/EFI installation, updates, rollback and independent recovery are verified on hardware. Recovery finds `userdata`, `system`, `boot`, `recovery` and `misc` by their unique stock GPT names on the eMMC; measured values in `hardware.clover.storageRoles` are optional and must then also match.

See [Clover storage preparation](manual-storage.md) for temporary recovery boot, ACM/NCM access, measuring the partitions and the checked `format-root` and `prepare-boot` commands.
