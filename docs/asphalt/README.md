# Lenovo Legion Y700 2023 (TB320FC) (asphalt)

[中文](README.zh.md) · [All devices](../README.md) · [Hardware support](hardware.md)

Support: Tier 2. See [support criteria](../README.md#support-tiers).

## Configure and install

1. Create a consumer flake using the [configuration guide](../configuration.md).
   Set `device = "asphalt"` in `lib.mkSystem`, or import `nixosModules.asphalt`.
2. Add the settings below to your installed configuration. Share device and
   storage identities with the separate recovery configuration; keep users,
   desktops and services in the installed system.
3. Read [installation preparation](first-install.md), confirm the measured
   storage layout and remaining manual steps, then build matching system, EFI
   files, U-Boot and recovery artifacts.

```nix
{
  androidDevices.usbSerial = "my-asphalt-01";
  androidDevices.persistentImage.rootfs.label = "NIXOS";
  # Optional factory identity files:
  # hardware.asphalt.radio.wifiAddressFile = ./wifi-address;
  # hardware.asphalt.radio.bluetoothAddressFile = ./bluetooth-address;
}
```

Optional identity files are build inputs. The Wi-Fi file holds the factory
MAC; the Bluetooth file holds the saved Qualcomm NVM address in controller byte
order, which the service reverses for BlueZ. Recovery does not run these identity
services. The root filesystem lives in a dedicated physical `linux` partition,
not in Android super. B-slot boot-success acknowledgement is not automatic;
see the [hardware limitations](hardware.md) before relying on repeated reboots.

Asphalt has booted through U-Boot/EFI and passed generation updates and rollback.
Use a separate 1 GiB FAT `linux-boot` ESP and ext4 `linux`, with firmware in
`boot_b`. Preserve A and super. See [installation preparation](first-install.md)
for the remaining manual preparation steps.

## Use and troubleshoot

In your consumer flake, build `.#system`, `.#bootstrap-info` and `.#recovery`.
The repository examples use `.#devices.asphalt.<role>`, for example `.#devices.asphalt.system`.
`lib.mkArtifacts` selects matching artifacts from your configuration; see the
[artifact guide](../configuration.md#select-artifacts).

- Routine updates: [USB SSH](../usb-signaller.md).
- Failed boot or offline updates: [RAM recovery](../recovery.md).
- Wi-Fi, audio, display and other limitations: [hardware reference](hardware.md).
- Configuration/build problems: [troubleshooting](../configuration.md#update-recover-and-troubleshoot).
- Camera commands and limitations: [cameras](hardware.md#cameras).

## Firmware sources

Device-specific firmware is fetched from a pinned upstream commit; this repository
does not store its binary payloads.

- Source: [dianqk/firmware-lenovo-asphalt at `207d466`](https://github.com/dianqk/firmware-lenovo-asphalt/tree/207d4668183032c1d9f196f195e9ecef98949d06).
- Used for: Touch, GPU, audio, video, WCN6855 board data and OnePlus Wi-Fi firmware.

The upstream repository documents the Lenovo Android image provenance, the
OnePlus Wi-Fi source, and SHA256 checksums for its 41 files. Override the default
Wi-Fi board data with `hardware.asphalt.wifiBoardFile` when needed; device
addresses are supplied separately.

See the [firmware license notes](../README.md#firmware-sources-and-licensing) for generic firmware
sources and licensing.
