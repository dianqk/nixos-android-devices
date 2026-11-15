# OnePlus 13 (dodge)

[中文](README.zh.md) · [All devices](../README.md) · [Support status](status.md)

Dodge is an experimental OnePlus 13 port. NixOS boots through U-Boot and
systemd-boot, and the same-slot boot-choice product can select Android or NixOS
in the current slot without switching A/B. Keep working Android, independent RAM
recovery and rollback assets.

## Storage and boot

- UFS `linux-boot` holds the FAT ESP; ext4 `linux` is the NixOS root.
- Installed systems use U-Boot `boot_b` and systemd-boot. Android remains on
  slot A.
- U-Boot is an embedding component for the same-slot product, not a standalone
  flashable boot image. Use the matching producer/helper or retain the existing
  independent U-Boot/Android bootstrap.
- RAM recovery is a host-supplied FIT payload; it is independent of the
  installed U-Boot. See [recovery](../recovery.md).

## Firmware and features

The default [firmware package](firmware.md) is
`dodge-firmware-LineageOS-24.0-5dd12b17e7-20261115.tar.zst` from the repository
`firmware` release. It contains GPU, Wi-Fi, Bluetooth, ADSP, CDSP, modem, SoCCP,
video, audio and SSC runtime data. Allow the unfree `dodge-firmware` package.

- Display, touch, USB NCM/SSH, USB host/DP, Wi-Fi and basic Bluetooth are
  available; see [status](status.md) for tested limits.
- AudioReach speakers and microphones: [audio](audio.md).
- Wireless charging and the optional voltage-care policy:
  [wireless charging](wireless-charging.md).
- Touch and display wake: [touch](touch.md).
- SSC sensors: [sensors](sensors.md).
- Same-slot Android/NixOS selection: [boot choice](../boot-choice.md).

## Build

```sh
nix build .#devices.dodge.recovery --out-link result-recovery
nix build .#devices.dodge.boot-firmware --out-link result-firmware
nix build .#devices.dodge.firmware --out-link result-device-firmware
nix build .#devices.dodge.kernel --out-link result-kernel
```

Use the matching NixOS module `nixosModules.dodge` and
`hardware.dodge.*` options. Device configuration, first installation and
recovery commands are covered by the shared
[installation guide](../README.md) and [recovery guide](../recovery.md).

Suspend, sustained thermal policy, complete charge cycles and some peripheral
combinations remain unverified. Do not treat host checks as hardware
acceptance.
