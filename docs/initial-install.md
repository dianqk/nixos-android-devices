# First installation

[中文](initial-install.zh.md) · [Storage preparation](u-boot-install.md)

`mobile-device recovery install-initial` installs an initial EFI system on
Asphalt, Polaris, Sheng and Clover, with device, slot and partition checks.

Prepare an empty ext4 root and FAT `/boot` using the device guide first:
[Asphalt](asphalt/first-install.md), [Polaris](polaris/first-install.md),
[Sheng](sheng/first-install.md), [Clover](clover/first-install.md).
This command does not create partitions or format filesystems. Clover requires a
measured storage contract including `userdata`, `system` and `boot`; its U-Boot
still lacks hardware validation. Asphalt/Sheng require recovery on slot B and
write only `boot_b`; Android A, super and both recovery partitions are preserved.

Build `system`, `bootstrap-info` and `recovery` from the same locked configuration,
using the [consumer flake outputs](configuration.md), and verify SSH access to
recovery. The system includes its matching U-Boot image; no separate firmware
image is needed. Both x86_64 and AArch64 Linux hosts can initiate installation.

Run these commands on the build host, replacing paths and the recovery SSH alias:

```sh
SYSTEM=$(readlink -f tmp/systemd-artifacts/system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info --execute
```

The first command validates local metadata and recovery prerequisites without
importing the closure or modifying the filesystems. `--execute` checks again,
streams the complete closure, loads its Nix registration, verifies closure
membership and NAR hashes, and matches `/` and `/boot` in fstab to the checked
partitions. It then creates the initial profile and runs the standard NixOS EFI
installer. Only after the selected EFI entry is present does it write and read
back matching U-Boot in the checked boot partition. It does not reboot.

`bootstrap-info` is build-time closure registration and size metadata, needed
because the empty root has no usable Nix database yet. Ordinary `deploy` operates
on an existing installed system and does not perform this bootstrap or write
U-Boot.

The default result file is `/run/mobile-initial-install.result`. On success,
inspect recovery status and explicitly reboot when ready. No second firmware
flash is needed. On failure, the root retains
`/var/lib/mobile-efi-preparation/pending`, which blocks normal recovery boot
selection. Stay in recovery and inspect the failure; do not simply remove the
marker. Once files have been imported, a blind rerun is refused because the root
is no longer empty. Repair deliberately or explicitly prepare an empty root
again. Root, FAT and firmware writes are not atomic. A boot write/readback failure
requires repairing the matching firmware before rebooting.

Fresh-install hardware validation remains incomplete; see the device guides.
