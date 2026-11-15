# NixOS on Android devices

[中文](README.zh.md)

NixOS device modules, kernels and U-Boot firmware for eight Qualcomm and MediaTek
phones and tablets. Systems boot through **U-Boot → systemd-boot → Linux** and
use standard NixOS configuration, updates and generation management.

## Devices

| Device | Codename | Guide |
| --- | --- | --- |
| Lenovo Legion Y700 2023 (TB320FC) | `asphalt` | [Use and install](docs/asphalt/README.md) |
| Xiaomi Mi MIX 2S | `polaris` | [Use and install](docs/polaris/README.md) |
| Xiaomi Pad 6S Pro 12.4 | `sheng` | [Use and install](docs/sheng/README.md) |
| Xiaomi 14 Ultra | `aurora` | [Use and install](docs/aurora/README.md) |
| Xiaomi Mi Pad 4 8-inch LTE | `clover` | [Use and install](docs/clover/README.md) |
| Redmi Note 12 Turbo / POCO F5 | `marble` | [Use and install](docs/marble/README.md) |
| Alldocube iPlay 80 mini Ultra | `t880` | [Use and install](docs/t880/README.md) |
| OnePlus 13 | `dodge` | [Use and install](docs/dodge/README.md) |

Each guide covers the supported hardware, storage contract, first installation,
updates, recovery and known limitations. Support status is recorded per device;
this README does not assign support levels.

## Quick start

1. **Configure** with `lib.mkSystem` or `nixosModules.<device>`. Device options
   use `hardware.<device>.*`; shared capabilities use `androidDevices.*`.
   Users, SSH keys, desktops and applications use ordinary NixOS configuration.
2. **Build** matching system and boot artifacts with `lib.mkArtifacts`. See the
   [configuration guide](docs/configuration.md).
3. **Install** by following the device guide: prepare the ext4 root and FAT
   `/boot`, install the system and EFI files, then install U-Boot.
4. **Update** through [USB SSH](docs/usb-signaller.md) or your network with
   `nixos-rebuild boot`. Routine updates maintain `/boot`; they do not rewrite
   U-Boot.

The [consumer flake](examples/consumer/flake.nix) is a complete starting point.
The [examples](examples/) are demos, not required policy.

## Build platforms

Build on AArch64 Linux, or use x86_64 cross compilation with local QEMU for
uncached native ARM dependencies. See
[build requirements](docs/configuration.md#build-platforms-and-remote-builders).

## Firmware and risk

Device firmware is distributed as per-device archives in the repository's
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware).
The Git tree contains packaging and patches, not OEM firmware payloads.

**Flashing risk:** This project was generated with LLMs. Flashing its images can
make a device unbootable or permanently unusable. Check the model, partitions and
image, and establish a working recovery path before writing. Installation and
troubleshooting use independent [RAM recovery](docs/recovery.md); see
[U-Boot installation](docs/u-boot-install.md).

## Documentation

- [Installation and updates](docs/README.md)
- [Configuration](docs/configuration.md)
- [Modules and packages](docs/modules.md) · [Packages](docs/packages.md)
- [Development and checks](docs/development.md)
- [Recovery](docs/recovery.md) · [USB access](docs/usb-signaller.md)
- [Dodge same-slot boot choice](docs/boot-choice.md)

## License

Original project code is available under the [MIT license](LICENSE). Linux
kernel patches follow the upstream [GPL-2.0 terms](LICENSES/GPL-2.0). Firmware
binaries retain their upstream licenses and are not covered by these licenses.
