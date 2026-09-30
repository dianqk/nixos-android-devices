# Xiaomi Pad 6S Pro 12.4 (sheng)

[中文](README.zh.md) · [All devices](../README.md) · [Hardware support](hardware.md)

Support: Tier 2. See [support criteria](../README.md#support-tiers).

An optional `boot-kernel` image boots a fixed Linux system directly.
U-Boot is the default. See [configuration and usage](../configuration.md#supplemental-direct-kernel-image-sheng-and-clover).

## Configure and install

1. Create a consumer flake using the [configuration guide](../configuration.md).
   Set `device = "sheng"` in `lib.mkSystem`, or import `nixosModules.sheng`.
2. Add the settings below to your installed configuration. Share device and
   storage identities with the separate recovery configuration; keep users,
   desktops and services in the installed system.
3. Read [installation preparation](first-install.md), confirm the measured
   storage layout and remaining manual steps, then build matching system, EFI
   files, U-Boot and recovery artifacts.

```nix
{
  androidDevices.usbSerial = "my-sheng-01";
  androidDevices.persistentImage.rootfs.label = "NIXOS";
  # Use this tablet's verified factory addresses when needed:
  # hardware.sheng.wifiMacAddress = "YOUR_FACTORY_WIFI_ADDRESS";
  # hardware.sheng.bluetoothAddress = "YOUR_FACTORY_BLUETOOTH_ADDRESS";
}
```

Optional capabilities are `hardware.sheng.sensors.enable`,
`services.fprintd.enable`, `hardware.sheng.thp.enable`,
`hardware.sheng.pen-status.enable` and `services.xiaomi-mipps-auth.enable`.
Sensors/devauth packages require Nixpkgs unfree permission. Enable only the
features you intend to use. `hardware.sheng.suspendWorkarounds.enable` defaults to
`false`; it enables downstream wake-source and Wi-Fi reload workarounds, not a
claim of validated suspend. Preserve the device's recovery firmware list because
ADSP firmware is also needed for the Type-C/USB path.

The default Sheng kernel and installed system example use pinned Linux 7.2.6.
The Nixpkgs 7.3-rc5 patch series remains available as `kernel-testing`; the RAM
recovery example selects it explicitly while its Wi-Fi path is investigated.
See the [kernel package notes](../../pkgs/linux-kernel/sm8550/sheng/PATCHES.md)
for source attribution and both build commands.

Sheng has booted through installed slot-B U-Boot/EFI with the 7.2.6 example.
USB/SSH and Wi-Fi work with 7.2.6. RAM boot has verified the visible U-Boot menu
and volume/power selection, but Linux display startup can leave the panel black.
Boot without a USB host remains unverified. See [known limitations](hardware.md#known-limitations).
Use a separate 1 GiB FAT `linux-boot` ESP and ext4 `linux`, with firmware in
`boot_b`. Preserve A and super. See [installation preparation](first-install.md)
for the remaining manual preparation steps.

## Use and troubleshoot

In your consumer flake, build `.#system`, `.#bootstrap-info` and `.#recovery`.
The repository examples use `.#devices.sheng.<role>`, for example `.#devices.sheng.system`.
`lib.mkArtifacts` selects matching artifacts from your configuration; see the
[artifact guide](../configuration.md#select-artifacts).

- Routine updates: [USB SSH](../usb-signaller.md).
- Failed boot or offline updates: [RAM recovery](../recovery.md).
- Wi-Fi, audio, display and other limitations: [hardware reference](hardware.md).
- Configuration/build problems: [troubleshooting](../configuration.md#update-recover-and-troubleshoot).
- Recovery image updates: [recovery operations](recovery.md).

## Firmware sources

Device-specific firmware is fetched from a pinned upstream commit; this repository
does not store its binary payloads.

- Source: [code002-2/sheng-firmware at `14a4d70`](https://github.com/code002-2/sheng-firmware/tree/14a4d70b0759bd0746264dc145f2d51a5a94902c).
- Used for: GPU, Wi-Fi, audio, touch, ADSP and optional fingerprint/sensor services.

See the [firmware license notes](../README.md#firmware-sources-and-licensing) for generic firmware
sources and licensing.
