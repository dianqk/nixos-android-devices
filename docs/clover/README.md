# Xiaomi Mi Pad 4 8-inch LTE (clover)

[中文](README.zh.md) · [All devices](../README.md) · [Support status](status.md) · [Hardware support](hardware.md)

Status: see the [hardware page](hardware.md) and [support status](status.md).

An optional `boot-kernel` image boots a fixed Linux system directly.
U-Boot is the default. See [configuration and usage](../configuration.md#supplemental-direct-kernel-image-sheng-and-clover).

The EFI menu includes [power and special reboot actions](../boot-actions.md).
These require matching U-Boot; their hardware behavior remains unverified.

## Configure and install

1. Create a consumer flake using the [configuration guide](../configuration.md).
   Set `device = "clover"` in `lib.mkSystem`, or import `nixosModules.clover`.
2. Optionally add the settings below to your installed configuration. Share
   device and storage identities with the separate recovery configuration;
   keep users, desktops and services in the installed system.
3. Read [installation preparation](first-install.md), check the storage layout
   and remaining manual steps, then build matching system, EFI files, U-Boot
   and recovery artifacts.

```nix
{
  # Optional: pin this tablet's measured partitions (see installation preparation):
  hardware.clover.storageRoles = {
    root = { partuuid = "YOUR_USERDATA_PARTUUID"; bytes = YOUR_USERDATA_BYTES; };
    firmware = { partuuid = "YOUR_BOOT_PARTUUID"; bytes = 67108864; };
    recovery = { partuuid = "YOUR_RECOVERY_PARTUUID"; bytes = 67108864; };
    misc = { partuuid = "YOUR_MISC_PARTUUID"; bytes = 1048576; };
    # Optional: number, offset and root.fsUuid to keep an existing filesystem.
  };
}
```

The module targets the 8-inch LTE model. Without measurements, the system and
recovery find each eMMC partition by its unique stock GPT name; measured roles
must be identical in both configurations. Optional `hardware.clover.wifiAddress` and
`bluetoothAddress` must use this tablet's own factory identities. This board has
no A/B slots. Do not reuse Asphalt/Sheng partition names or slot commands.

Clover uses U-Boot/systemd-boot with physical `system` as FAT `/boot` and
`userdata` as ext4 root. U-Boot/EFI installation, updates, rollback and
independent recovery are verified on hardware. The [shared first installer](../initial-install.md)
supports prepared partitions; see [installation preparation](first-install.md).

The default kernel is Nixpkgs Linux 7.3 with [sourced Clover patches](../../pkgs/linux-kernel/sdm660/clover/PATCHES.md).
It boots the installed system and recovery; see [hardware support](hardware.md).

## Use and troubleshoot

In your consumer flake, build `.#system`, `.#bootstrap-info` and `.#recovery`.
The repository examples use `.#devices.clover.<role>`, for example `.#devices.clover.system`.
`lib.mkArtifacts` selects matching artifacts from your configuration; see the
[artifact guide](../configuration.md#select-artifacts).

- Routine updates: [USB SSH](../usb-signaller.md).
- Failed boot or offline updates: [RAM recovery](../recovery.md).
- Wi-Fi, audio, display and other limitations: [hardware reference](hardware.md).
- Configuration/build problems: [troubleshooting](../configuration.md#update-recover-and-troubleshoot).
- Intermittent data corruption (checksum mismatches, crashing programs): the
  kernel includes the boot memory test. Add `boot.kernelParams = [ "memtest=17" ];`
  to test RAM with all patterns at boot and reserve weak cells; reserved
  cells appear as `bad mem addr` lines in `dmesg`. It adds about one second to
  boot. Fewer passes, such as `memtest=4`, can miss pattern-sensitive cells.

The desktop example uses Niri's OpenGL ES/EGL renderer and does not require
Vulkan. Mesa's Freedreno supports Adreno 5xx GL/GLES; its Turnip Vulkan driver
does not support this GPU generation. This establishes API compatibility,
not a successful Clover boot or physical display test. Run the [basic hardware
suite](../../tests/basic/README.md) with `--skip vulkan`.
See [Niri's renderer](https://github.com/niri-wm/niri/blob/v26.04/src/backend/tty.rs)
and [Mesa's driver support](https://docs.mesa3d.org/drivers/freedreno.html).

## Firmware sources

Device-specific firmware is fetched from a pinned upstream commit; this repository
does not store its binary payloads.

- Archive: [`clover-firmware-c850ad5-20261115.tar.zst`](https://github.com/dianqk/nixos-android-devices/releases/download/firmware/clover-firmware-c850ad5-20261115.tar.zst), assembled from [setotau/firmware-xiaomi-clover at `c850ad5`](https://github.com/setotau/firmware-xiaomi-clover/tree/c850ad5d11315e690df8244670241e3d5a8436dc).
- Used for: WCN3990 board data.

See the [firmware license notes](../README.md#firmware-sources-and-licensing) for generic firmware
sources and licensing.
