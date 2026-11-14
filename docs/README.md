# Install and use

[中文](README.zh.md) · [Project home](../README.md)

Create your system with the [configuration guide](configuration.md), then prepare
storage and boot files for the device. All supported boards use
U-Boot → systemd-boot → Linux; Dodge uses the same-slot boot-choice variant.

## Installation

| Device | FAT `/boot` | ext4 root | Firmware partition | Guides |
| --- | --- | --- | --- | --- |
| Asphalt / Y700 2023 | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Configure](asphalt/README.md) · [Prepare installation](asphalt/first-install.md) |
| Polaris / Mi MIX 2S | Physical `system` | `userdata` | `boot`, no A/B | [Configure](polaris/README.md) · [Install](polaris/first-install.md) |
| Sheng / Pad 6S Pro | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Configure](sheng/README.md) · [Prepare installation](sheng/first-install.md) |
| Aurora / Xiaomi 14 Ultra | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Configure and install](aurora/README.md) |
| Clover / Mi Pad 4 LTE | Physical `system` | `userdata` | `boot`, no A/B | [Configure](clover/README.md) · [Prepare installation](clover/first-install.md) |
| Marble / Redmi Note 12 Turbo | Separate 1 GiB `linux-boot` | `linux` | `boot_b` only | [Device guide](marble/README.md) |
| T880 / iPlay 80 mini Ultra | Not measured | Not measured | Not measured; experimental builds only | [Device guide](t880/README.md) |
| Dodge / OnePlus 13 | Separate `linux-boot` ESP | `linux` | `boot_b` only; same-slot boot choice | [Device guide](dodge/README.md) |
| Unicorn / Xiaomi 12S Pro | Separate 1 GiB `linux-boot` | `linux` (whole userdata) | `boot_b`; recovery in `recovery_b` | [Device guide](unicorn/README.md) |

Follow [U-Boot installation](u-boot-install.md) for the complete sequence.
Dodge's same-slot product is described in the [boot-choice guide](boot-choice.md).

## Updates and troubleshooting

- Users, desktops, applications and services: [configuration](configuration.md).
- USB networking, SSH and `nixos-rebuild boot`: [connect and update](usb-signaller.md).
- Polaris radio calibration snapshot for Wi-Fi and the modem: [radio snapshot](polaris/radio-snapshot.md).
- Polaris generation selection and menu settings: [boot menu](polaris/boot-menu.md).
- Polaris/Clover pre-Linux power and reboot targets: [boot actions](boot-actions.md).
- Failed boots, target mounts and offline updates: [RAM recovery](recovery.md).
- Closure transfer and checked device operations: [mobile-device](../pkgs/mobile-device/README.md).
- Sheng recovery image updates: [recovery operations](sheng/recovery.md).

Routine system updates maintain the kernel, initrd, DTB and generation entries
on FAT `/boot`. Update U-Boot firmware and recovery images separately.

## Customizing and porting

- Package reuse and overrides: [packages](packages.md).
- Module boundaries, shared `androidDevices.*` inputs and device options:
  [modules](modules.md).
- Evaluation checks, kernel patch queues and new-board bring-up:
  [development](development.md).
- Development-host tools and USB configuration: [host](host.md).
- SSC sensors and screen rotation: [sensors](sensors.md).
- Qualcomm modem and QTEE services: [modem](modem.md).

## Firmware sources and licensing

Device firmware is published as per-device archives in the repository's
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware).
The Git tree keeps packaging, patches and configuration, not OEM payloads.
Generic firmware and regulatory data come from Nixpkgs `linux-firmware` and
`wireless-regdb`. Firmware binaries retain their upstream licenses and are not
covered by this project's MIT or kernel GPL-2.0 licenses.
