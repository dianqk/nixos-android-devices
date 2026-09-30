# Install and use

[中文](README.zh.md) · [Project home](../README.md)

Create your system with the [configuration guide](configuration.md), then prepare
storage and boot files for the device. All four boards use
U-Boot → systemd-boot → Linux.

## Installation

| Device | FAT `/boot` | ext4 root | Firmware partition | Guides |
| --- | --- | --- | --- | --- |
| Asphalt / Y700 2023 | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Configure](asphalt/README.md) · [Prepare installation](asphalt/first-install.md) |
| Polaris / Mi MIX 2S | Physical `system` | `userdata` | `boot`, no A/B | [Configure](polaris/README.md) · [Install](polaris/first-install.md) |
| Sheng / Pad 6S Pro | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Configure](sheng/README.md) · [Prepare installation](sheng/first-install.md) |
| Clover / Mi Pad 4 LTE | Physical `system` | `userdata` | `boot`, no A/B | [Configure](clover/README.md) · [Prepare installation](clover/first-install.md) |

All four devices use the [first installer](initial-install.md) after preparing
their partitions. Clover requires a measured storage contract and its U-Boot
is untested on hardware. On Asphalt/Sheng, allocate Linux partitions from the
original userdata area and preserve Android A and super.

Follow [U-Boot installation](u-boot-install.md) for the complete sequence.

## Updates and troubleshooting

- Users, desktops, applications and services: [configuration](configuration.md).
- USB networking, SSH and `nixos-rebuild boot`: [connect and update](usb-signaller.md).
- Polaris generation selection and menu settings: [boot menu](polaris/boot-menu.md).
- Failed boots, target mounts and offline updates: [RAM recovery](recovery.md).
- Closure transfer and checked device operations: [mobile-device](../pkgs/mobile-device/README.md).
- Sheng recovery image updates: [recovery operations](sheng/recovery.md).

Routine system updates maintain the kernel, initrd, DTB and generation entries
on FAT `/boot`. Update U-Boot firmware and recovery images separately.

## Support tiers

Support tiers apply to the examples provided by this open-source repository:

| Tier | Support target | Validation requirement |
| --- | --- | --- |
| Tier 1 | Runnable + buildable + evaluable | A separate physical device dedicated to validating this repository's examples is required, with successful build, evaluation, and runtime checks |
| Tier 2 | Buildable + evaluable | Build and evaluation validation; no commitment to device runtime validation |
| Tier 3 | Evaluable | Evaluation validation; no commitment to build or device runtime validation |

No device currently meets Tier 1. See each device's hardware page for tested
features and known limitations.

## Firmware sources and licensing

Device-specific firmware sources and uses are documented in each device guide.
Generic firmware and regulatory data come from Nixpkgs `linux-firmware` and
`wireless-regdb`. Firmware binaries retain their upstream licenses and are not
covered by this project's MIT or kernel GPL-2.0 licenses. This repository does not
store copies of the device firmware payloads.
