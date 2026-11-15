# U-Boot installation


> **Dodge exception:** the standalone flashable U-Boot role is retired. Use
> the [same-slot native/KernelSU product](boot-choice.md), not a new
> standalone loader in `boot_b`. `devices.dodge.boot-firmware` contains only
> raw/ELF/config embedding inputs; it is not an OEM boot image. Preserve existing
> independent B/RAM recovery and rollback assets. Native same-slot transactions
> and their EFI guard are implemented and host-tested; physical/runtime and
> power-loss acceptance remain separate. Other boards' standalone roles and
> installation steps are unchanged.

[中文](u-boot-install.zh.md)

Installed mobile systems use U-Boot → systemd-boot → Linux.
`devices.<device>.u-boot` provides standalone U-Boot firmware where supported
(excluding Dodge). The `boot-files` output
for an installed system contains EFI files for FAT. The `recovery` output
provides the board’s RAM recovery image. [T880](t880/install.md) loads a host-supplied raw FIT through
its installed U-Boot. [Dodge](recovery.md#dodge-host-supplied-fit) retains a raw FIT role and uses a separately retained, boot-verified RAM
bootstrap when independent OEM recovery is needed.

| Device | FAT `/boot` | ext4 `/` | Firmware partition |
| --- | --- | --- | --- |
| Asphalt | Separate 1 GiB `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Polaris | Physical `system` | `userdata` | `boot`, no A/B |
| Sheng | Separate 1 GiB `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Aurora | Separate 1 GiB `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Clover | Physical `system` | `userdata` | `boot`, no A/B |
| Marble | Separate `linux-boot` ESP | Separate `linux` | `boot_b` only |
| Dodge | Separate `linux-boot` ESP | Separate `linux` | Same-slot native embedding; preserve independent B |
| T880 | Separate `linux-boot` ESP | Separate `linux` | `boot_a` only |

Both Linux partitions on Asphalt, Sheng, Aurora, Marble and Dodge come from the original userdata allocation
and are siblings in the outer GPT. Preserve Android A and super. Never write a
rootfs image to system or treat the EFI files directory as a partition image.
On T880, preserve Android B and super.

1. Set device identities, credentials and storage contracts using the
   [configuration guide](configuration.md).
2. For a standalone-capable board (not Dodge), if it lacks compatible U-Boot, obtain its standalone firmware
   image and flash it using the device guide.
3. Start RAM recovery using the device's supported route. Check the GPT and
   partition identities, prepare FAT and an empty ext4 root, and use the
   [first system installer](initial-install.md) to install NixOS and its EFI generation.
4. Verify normal boot, RAM recovery, SSH, generation updates and rollback.
   Routine system updates install EFI generations. Update firmware separately
   when needed.

## Build and flash U-Boot independently

In this repository, replace `DEVICE` with the device name:

```sh
nix build .#devices.DEVICE.u-boot --out-link DEVICE-u-boot.img
sha256sum DEVICE-u-boot.img
```

This output is the standalone flashable image and can be distributed on its
own. The consumer flake exposes the same artifact role as `boot`. An existing
compatible firmware image can be reused. Follow the device guide when flashing
from the vendor bootloader. If already running compatible RAM recovery, use
its checked firmware update operation instead. Replace `BOOT_PARTLABEL` with
the device's firmware partition label from the table above:

```sh
mobile-device recovery --target RECOVERY_HOST install-image DEVICE-u-boot.img \
  --partition /dev/disk/by-partlabel/BOOT_PARTLABEL
mobile-device recovery --target RECOVERY_HOST install-image DEVICE-u-boot.img \
  --partition /dev/disk/by-partlabel/BOOT_PARTLABEL --execute
```

Recovery resolves the target partition from its board and slot configuration,
checks the image identity and capacity, and verifies the write by readback.
Complete the device guide's remaining boot preparation before starting NixOS.

For an existing EFI system, recovery supports `mount-target --rw`, `rebuild boot`
and `unmount-target`; see [recovery](recovery.md). Hardware support and remaining
limits are listed for [Asphalt](asphalt/hardware.md), [Polaris](polaris/hardware.md),
[Sheng](sheng/hardware.md), [Aurora](aurora/hardware.md) and [Clover](clover/hardware.md).
