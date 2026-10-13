# Xiaomi Mi MIX 2S (polaris)

[中文](README.zh.md) · [All devices](../README.md) · [Hardware support](hardware.md)

Support: Tier 2. See [support criteria](../README.md#support-tiers).

## Configure and install

Prepare the **latest LineageOS 22.2 build for polaris** first. See the
[Android baseline and identity checks](first-install.md#android-base-before-installation).

1. Create a consumer flake using the [configuration guide](../configuration.md).
   Set `device = "polaris"` in `lib.mkSystem`, or import `nixosModules.polaris`.
2. Add the settings below to your installed configuration. Share the root
   filesystem label with the separate recovery configuration; keep users,
   desktops and services in the installed system.
3. Follow [first installation](first-install.md) to inspect partitions, build
   matching system/bootstrap-info/recovery artifacts and install them.

```nix
{
  androidDevices.usbSerial = "my-polaris-01";
  androidDevices.usb.ssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY" ];
}
```

For a USB-only console, set `hardware.polaris.radio.enable = false` and
`hardware.polaris.audio.enable = false`. Both default to `true`. When using radios,
set `hardware.polaris.radio.identityFile` to the device-side Wi-Fi address file,
`snapshotDirectory` to the verified read-only calibration snapshot, and
`bluetoothIdentityFile` to the Bluetooth address file. These paths refer to files
on the phone, not build-input files. The module does not collect calibration or
invent factory identities. With no snapshot directory, RMTFS does not start.
The snapshot is served through the shared [modem services](../modem.md) as
`modem-rmtfs.service` and `modem-tqftpserv.service`.
If you do not have verified radio data, start with the USB console configuration.
Use normal NixOS options to enable NetworkManager, Bluetooth and PipeWire.

Polaris defaults to U-Boot/EFI: physical `system` is FAT `/boot` and `userdata`
is the ext4 root. Connect and update using [USB SSH](../usb-signaller.md);
use the [boot menu guide](boot-menu.md) to select generations.

## Use and troubleshoot

In your consumer flake, build `.#system`, `.#bootstrap-info` and `.#recovery`.
The repository examples use `.#devices.polaris.<role>`, for example `.#devices.polaris.system`.
`lib.mkArtifacts` selects matching artifacts from your configuration; see the
[artifact guide](../configuration.md#select-artifacts).

- Off-mode charging: [setup, controls and limits](charging.md).
- Routine updates: [USB SSH](../usb-signaller.md).
- Failed boot or offline updates: [RAM recovery](../recovery.md).
- Wi-Fi, audio, display and other limitations: [hardware reference](hardware.md).
- Configuration/build problems: [troubleshooting](../configuration.md#update-recover-and-troubleshoot).
- Camera commands and limitations: [cameras](hardware.md#cameras).

## Firmware sources

Device-specific firmware is fetched from a pinned upstream commit; this repository
does not store its binary payloads.

- Source: [MollySophia/firmware-xiaomi-polaris at `d88ffb2`](https://github.com/MollySophia/firmware-xiaomi-polaris/tree/d88ffb2ee182d07567bf280fc4a8493f975ae977).
- Used for: Device-specific modem, Wi-Fi, Bluetooth, GPU, IPA and multimedia firmware.

See the [firmware license notes](../README.md#firmware-sources-and-licensing) for generic firmware
sources and licensing.
