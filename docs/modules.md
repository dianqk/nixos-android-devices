# Module boundaries

[中文](modules.zh.md)

Consumers import `nixosModules.<device>` and configure device-specific options
under `hardware.<device>.*`, with shared capabilities under `androidDevices.*`,
as described in the [configuration guide](configuration.md). Each device
export includes the shared modules and enables its board support. Internal paths
under `modules/` are implementation details, not consumer imports.

## Adding or maintaining a device

Keep reusable NixOS support in `modules/mobile/` and hardware policy in
`modules/devices/<device>/`.

Shared modules must not look up device codenames, maintain device lists, or select
behavior using a device family. Configure their inputs in the device module:

| Device-owned input | Shared consumer |
| --- | --- |
| Host platform, hostname, console and platform kernel parameters | NixOS and `base.nix` |
| Kernel, firmware and `hardware.deviceTree.name` | Kernel/initrd and UEFI modules |
| `boot.firmwarePackage` | Installed-system boot artifact |
| `boot.directKernel.enable` and `boot.android.*` | Optional direct-kernel and RAM recovery images |
| `boot.uefi.device` and `boot.uefi.requireStandardEsp` | Boot mount and installer checks |
| `persistentImage.rootfs.device` | Installed ext4 root |
| `usb.signaller.address`, `usb.signaller.controlGroup`, controller and serial | USB management modules |
| `recovery.targetHostName` and `recovery.daemon.*` (slot model, compatibles, controller, boot request, storage roles, UFS safe mode) | Recovery daemon configuration |

The option prefixes in the table are under `androidDevices`, except for standard
NixOS options. Device-specific options such as `hardware.<device>.systemHostName`
are declared and consumed only by that device module, which passes their values
to networking and recovery explicitly.

`androidDevices.deviceName` is an artifact/display label. Shared modules may
include it in filenames, titles and recovery
identity markers, but must not use it to select packages, partitions or hardware
policy. A new board should not require adding a branch to a shared module.

For installed systems, supply a UEFI firmware image through
`boot.firmwarePackage`. RAM recovery constructs an Android boot image from the
supplied kernel and Android boot parameters; it does not require a firmware
package. The supplemental direct-kernel artifact is independently enabled by
`boot.directKernel.enable` and is absent in recovery configurations.

`boot.uefi.requireStandardEsp` defaults to true. This checks the standard GPT ESP
type, expected size and update free space. Existing Polaris/Clover modules set it
to false because they retain the vendor GPT type on physical `system`; Asphalt
and Sheng keep the standard ESP policy. Both modes verify that `/boot` is FAT and
that its mounted source matches the configured physical partition. Disabling
standard ESP checks is a board storage decision, not a workaround for an
installation failure. See each device's installation guide before changing it.

Shared hardware services take explicit device inputs. For example, the
[modem and QTEE modules](modem.md) receive the remoteproc name, NV partitions
or directory, start method and firmware from the device module
(`hardware.aurora.modem`, `hardware.polaris.radio`) instead of selecting them
by device name.

Keep board-specific scripts beside their device module; for example, the Polaris
UFS safe-mode script lives in `modules/devices/polaris/`. Device-specific package
implementations live in `pkgs/`; this boundary does not make those tools accept
arbitrary hardware.

## Validation

`tests/mobile-module-boundary.nix` imports only the shared modules and configures
an unregistered device label, explicit partitions, DTB and firmware package. It
checks standard/vendor FAT policies, direct-kernel selection, recovery inputs and
missing-firmware rejection on both build platforms. Its fixtures support
evaluation only and are not bootable images.

`tests/eval-platforms.nix` covers the five supported devices and their existing
artifact contracts. Run the checks in the [development guide](development.md)
when changing a common option or moving policy between modules. Build and hardware
validation remain separate from these evaluations.
