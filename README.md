# NixOS on Android devices

[中文](README.zh.md)

NixOS device modules, kernels and U-Boot firmware for five Xiaomi and Lenovo
phones and tablets. Systems boot through **U-Boot → systemd-boot → Linux** and
use standard NixOS configuration, updates and generation management. Build on
AArch64 Linux, or use x86_64 cross compilation with local QEMU for uncached
native ARM dependencies. See the [build requirements](docs/configuration.md#build-platforms-and-remote-builders).

## Supported devices

| Device | Codename | Support tier | Configuration and hardware status |
| --- | --- | --- | --- |
| Lenovo Legion Y700 2023 (TB320FC) | `asphalt` | Tier 2: buildable and evaluable | [Device guide](docs/asphalt/README.md) |
| Xiaomi Mi MIX 2S | `polaris` | Tier 2: buildable and evaluable | [Device guide](docs/polaris/README.md) |
| Xiaomi Pad 6S Pro 12.4 | `sheng` | Tier 2: buildable and evaluable | [Device guide](docs/sheng/README.md) |
| Xiaomi 14 Ultra | `aurora` | Tier 2: buildable and evaluable | [Device guide](docs/aurora/README.md) |
| Xiaomi Mi Pad 4 8-inch LTE | `clover` | Tier 3: evaluable | [Device guide](docs/clover/README.md) |

Tiers describe this repository's examples; consult each device guide for hardware
features and test coverage. No device currently meets the dedicated runtime
validation requirement for Tier 1. See the [support criteria](docs/README.md#support-tiers).

## Get started

1. **Configure**: follow the [configuration guide](docs/configuration.md) to create
   your flake with `lib.mkSystem` or `nixosModules.<device>`. Device-specific options
   use `hardware.<device>.*`; shared capabilities use `androidDevices.*`. Users,
   SSH keys, desktops and applications use ordinary NixOS configuration.
2. **Build**: export matching system and boot artifacts with `lib.mkArtifacts`.
   [Artifact selection](docs/configuration.md#select-artifacts) explains the system
   closure, U-Boot firmware and EFI files.
3. **Install**: follow the [device installation guide](docs/README.md#installation)
   to prepare an ext4 root and FAT `/boot`, install the system and EFI files, then
   install U-Boot. All five devices use the [first installer](docs/initial-install.md)
   after device-specific partition preparation.
4. **Update**: connect through [USB SSH](docs/usb-signaller.md) or your configured
   network, run `nixos-rebuild boot`, and verify the new generation after reboot.
   Routine updates maintain EFI files on `/boot` without rewriting U-Boot.

**Flashing risk:** This project was generated entirely with LLMs. Flashing its
images can make a device unbootable or permanently unusable. Anyone who builds
or flashes them accepts responsibility for that risk. Check the model, partitions
and image, and establish a working recovery path before writing. Installation
and troubleshooting use independent [RAM recovery](docs/recovery.md); see
[U-Boot installation](docs/u-boot-install.md) for storage requirements.

## Kernel status

Each device has exactly one kernel: the Linux release provided by the locked
Nixpkgs input (currently 7.3-rc6) plus the device's patch queue. Recovery uses
the same kernel as the installed system. See the
[kernel configuration notes](pkgs/linux-kernel/README.md).

## Build the repository examples

On a Linux build computer with Nix flakes enabled, build only the artifacts
needed for your chosen device. For example:

```sh
nix build .#devices.polaris.system --out-link result-system
nix build .#devices.polaris.boot-files --out-link result-boot-files
nix build .#devices.polaris.u-boot --out-link result-u-boot
```

Replace `polaris` with `asphalt`, `sheng`, `clover` or `aurora` for another board.
`devices.<device>.boot` and `devices.<device>.u-boot` are the same firmware;
`boot-files` is a directory, not a flashable partition image. Other outputs include
`bootstrap-info`, `recovery` and `kernel`; select them as the installation guide
requires. These commands only build artifacts. Set device-specific storage
identities and access credentials before deployment.

Desktop configurations in [`examples/`](examples/) explicitly select Niri,
passwordless `demo` autologin and test tools. Device modules supply hardware
capabilities. Polaris also has a [minimal console example](docs/polaris/minimal.md)
with empty-password root SSH over USB. Adapt the examples to your access policy.

## More documentation

- [Documentation index](docs/README.md)
- [Package reuse and overrides](docs/packages.md)
- [Module boundaries and shared options](docs/modules.md)
- [Build and development checks](docs/development.md)
- [Host deployment tool](pkgs/mobile-device/README.md)
- [SSC sensors and screen rotation](docs/sensors.md): optional board
  capabilities; see the runtime validation limits.
- [Development-host tools and USB configuration](docs/host.md)

## License

Original project code is available under the [MIT license](LICENSE). Linux
kernel patches follow the upstream [GPL-2.0 terms](LICENSES/GPL-2.0).
