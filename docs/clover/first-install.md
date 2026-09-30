# Clover LTE first installation

Read the [U-Boot installation workflow](../u-boot-install.md) and [device configuration](README.md) first.

After preparing the partitions below, use the [shared first installer](../initial-install.md) to import the closure, install EFI and write matching U-Boot firmware.

Clover uses physical system as FAT `/boot` and userdata as ext4 root, without A/B. U-Boot has not been tested on hardware. The measured `hardware.clover.storageRolesFile` must include `userdata`, `system` and `boot` roles; the default unconfigured contract refuses installation.

See the [Clover manual storage example](manual-storage.md) for temporary recovery boot, ACM/NCM access, measured eMMC contract checks and manual formats. It also explains the scope of the checked `format-root` command.
