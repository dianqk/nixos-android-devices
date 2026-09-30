# U-Boot installation

[中文](u-boot-install.zh.md)

All four installed systems use U-Boot → systemd-boot → Linux. Both
`devices.<device>.boot` and `devices.<device>.u-boot` contain U-Boot firmware;
`boot-files` contains EFI files for FAT, and `recovery` is an independent
Android-format RAM recovery image. Evaluation does not prepare storage or flash firmware.

| Device | FAT `/boot` | ext4 `/` | Firmware partition |
| --- | --- | --- | --- |
| Asphalt | Separate 1 GiB `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Polaris | Physical `system` | `userdata` | `boot`, no A/B |
| Sheng | Separate 1 GiB `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Clover | Physical `system` | `userdata` | `boot`, no A/B |

Both Linux partitions on Asphalt/Sheng come from the original userdata allocation
and are siblings in the outer GPT. Preserve Android A and super. Never write a
rootfs image to system or treat the EFI files directory as a partition image.

1. Set device identities, credentials and storage contracts using the
   [configuration guide](configuration.md). Build matching system, bootstrap-info,
   boot-files, u-boot and recovery outputs from one locked configuration. Verify
   access to independent RAM recovery first.
2. In recovery, measure GPT geometry, capacity, partition identities and filesystems.
3. Prepare FAT and an empty ext4 root as above, following the device storage guide.
   Partitioning and formatting remain explicit, separate operations.
4. Use the [shared first installer](initial-install.md) on any of the four boards.
   It imports and verifies the complete closure and registration, installs the EFI
   generation and writes matching U-Boot firmware last. Run its check before
   `--execute`; a successful installation needs no additional firmware flash.
5. Verify boot, independent recovery, SSH, generation updates and rollback.
   Routine `nixos-rebuild boot` updates FAT files without rewriting the Android
   boot partition. Firmware updates are separate operations.

For an existing EFI system, recovery supports `mount-target --rw`, `rebuild boot`
and `unmount-target`; see [recovery](recovery.md). Hardware support and remaining
limits are listed for [Asphalt](asphalt/hardware.md), [Polaris](polaris/hardware.md),
[Sheng](sheng/hardware.md) and [Clover](clover/hardware.md).
