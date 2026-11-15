# First system installation

[中文](initial-install.zh.md) · [U-Boot and storage preparation](u-boot-install.md)

`mobile-device recovery install-initial` installs the NixOS closure and an EFI
generation from RAM recovery. Follow the device guide to prepare an empty ext4
root and FAT ESP. Use a host tool and RAM recovery that both support system-only
installation.

The usual order is to [install U-Boot separately](u-boot-install.md), start RAM
recovery using the device's supported route, and install the system. If a
compatible U-Boot is already installed, keep using it. You can also install the
system before flashing U-Boot if the device can start RAM recovery independently.
Before booting the installed system, make sure the device has compatible U-Boot.

Build `system` and `bootstrap-info` from the same locked configuration and
verify SSH access to RAM recovery. The [configuration guide](configuration.md)
describes the build outputs. Both x86_64 and AArch64 Linux hosts can initiate
installation.

Run these commands on the build host, replacing paths and the recovery SSH alias:

```sh
SYSTEM=$(readlink -f result-system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info --execute
```

The first command checks local metadata and recovery prerequisites.
`--execute` checks again, streams the complete closure, loads its Nix
registration, verifies closure membership and NAR hashes, and matches `/` and
`/boot` in fstab to the checked partitions. It then creates the initial profile,
runs the standard NixOS EFI installer, and verifies the selected EFI entry.
The operation writes the prepared root and ESP. Partitioning, formatting,
firmware flashing and reboot are separate commands.

`bootstrap-info` provides the closure registration and size metadata needed by
an empty root. Use `deploy` for an existing installed system.

The recovery daemon reports results through `recovery status` and
`recovery task TASK_ID`. If installation fails, inspect the error in recovery.
The pending marker at `/var/lib/mobile-efi-preparation/pending` blocks normal
recovery boot selection. After a complete transfer, retry with `--resume` and
the same system and bootstrap-info. An incomplete transfer requires a fresh
installation onto a prepared empty root.

Before the first normal boot on Asphalt, follow the device's
[checked B DTBO procedure](asphalt/first-install.md#erase-b-dtbo-and-boot).
