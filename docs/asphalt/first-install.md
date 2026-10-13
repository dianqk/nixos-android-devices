# Asphalt installation and boot restoration

[中文](first-install.zh.md) · [Device guide](README.md)

Choose the path that matches the device:

- **Existing NixOS installation:** if Android/LineageOS replaced the B boot
  image or DTBO but the Linux root and ESP remain, use [boot restoration](#restore-an-existing-efi-installation).
  Do not repartition, format or rerun first installation.
- **First installation:** prepare the firmware base and use the explicit
  [destructive storage preparation](#prepare-storage-for-first-installation).

## Android base before installation

**The Asphalt adaptation uses the Lenovo TB320FC ROW ZUI 17.0.339 Android 15
base. Prepare this base before installing NixOS.** The Android system used
during adaptation was a LineageOS Android 16 GSI on top of that Lenovo base:

| Item | Development baseline |
| --- | --- |
| Device / region | Lenovo Y700 2023, `TB320FC`, ROW |
| Lenovo build | `TB320FC_ROW_OPEN_USER_Q00031.0_V_ZUI_17.0.339_ST_251219` |
| Vendor fingerprint | `Lenovo/TB320FC/TB320FC:15/AQ3A.240812.002/ZUI_17.0.339_251219_ROW:user/release-keys` |
| Android system used during adaptation | LineageOS `23.2-20260524-VANILLA-EXT4-GSI`, Android 16 |

Before replacing Android, check the device and vendor build separately from
the running system:

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.vendor.build.version.incremental
adb -s SERIAL shell getprop ro.vendor.build.fingerprint
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.lineage.version
```

The captured `ro.vendor.build.version.release` reports `13` despite the Android
15 vendor fingerprint; do not use that property alone to identify the base.
The GSI's Android 16 version also does not identify the Lenovo firmware base.
These properties record the observed build, not the version of every boot or
security firmware partition after mixed or partial flashes. Other Lenovo base
versions have not been established as equivalent by this adaptation.
Complete base preparation before first-install Linux partitioning; afterward
preserve Android A and super, and use B for Linux. NixOS updates do not update
the factory base. Restoring an existing installation does not establish that a
recent Android install preserved every firmware partition; do not infer the base
from the LineageOS version or reflash factory firmware as an incidental restore step.

## Restore an existing EFI installation

Use this path only when the existing FAT `linux-boot` ESP and ext4 `linux` root
are retained. If their state is uncertain, inspect them read-only in trusted
recovery first; partition names alone do not establish usable filesystems.
Preserve Android A, super, recovery, calibration and all existing user data.
An Android installation can replace B recovery with Lineage recovery; do not
assume the previous NixOS RAM recovery is still present. Use the
[recovery guide](../recovery.md) to establish trusted recovery access if needed.

From your [consumer flake](../configuration.md), build its matching U-Boot
`boot` artifact and host CLI. `boot` contains U-Boot firmware, not the Linux
kernel or a root filesystem image:

```sh
nix build .#boot --out-link result-boot
nix build .#mobile-device --out-link result-mobile-device
export PATH="$PWD/result-mobile-device/bin:$PATH"
```

In OEM fastboot, complete the [identity and B-slot checks](#verify-oem-fastboot-and-select-b)
below before checking and explicitly flashing **only `boot_b`**:

```sh
mobile-device --serial SERIAL fastboot flash \
  result-boot --partition boot_b
mobile-device --serial SERIAL fastboot flash \
  result-boot --partition boot_b --execute
```

Review the printed board, target, size and SHA-256 before the execute command.
Then [erase B DTBO and boot](#erase-b-dtbo-and-boot). Do not replace recovery or
write a filesystem image as part of this restoration. Once NixOS is reachable,
verify its existing root/ESP, selected EFI generation and retained rollback,
then use [standard NixOS SSH updates](../usb-signaller.md#standard-updates).
Prefer `nixos-rebuild boot` followed by a controlled reboot for management-stack
changes. Repartitioning and DTBO erase are not routine system-update steps.

## Prepare storage for first installation

Use the Rust daemon NixOS recovery on slot B; verify that it is actually running
and reachable over SSH. Preserve A, super, calibration and independent recovery.
The recovery initrd contains no Python. Standard NixOS installation/update tools
may use Python from the target system inside chroot.

Starting from the original userdata layout, check and explicitly execute
**destructive** preparation below. Android and Linux each receive approximately
half of the original userdata allocation; the Linux half contains a separate FAT
ESP (1 GiB by default) and ext4 root. Android userdata is destroyed and requires
a separate factory reset. Already partitioned devices are refused by this
operation. Never run it to repair an existing installation's boot path.

```sh
ssh RECOVERY_HOST 'recovery prepare-install --check'
ssh RECOVERY_HOST 'recovery prepare-install --confirm-erase-userdata'
```

Then follow [first installation](../initial-install.md) to import the matching
system, install EFI and write U-Boot to `boot_b` last. That installer does not
reboot and already writes the matching firmware: **do not repeat the manual
`boot_b` flash from the restoration procedure**. After successful installation,
return from NixOS recovery to OEM fastboot:

```sh
mobile-device recovery --target RECOVERY_HOST reboot bootloader
mobile-device recovery --target RECOVERY_HOST reboot bootloader --execute
```

Complete the checks and DTBO erase below before the first normal U-Boot boot.
Do not rely on `fastboot boot` to launch RAM recovery on Asphalt; OEM support
has not been established. Existing systems can use `recovery rebuild boot` or
host-side `mobile-device recovery deploy` for offline updates. Root/ESP ordering
and alignment gaps remain supported; ordinary updates do not repartition.

To erase only an existing Linux root, check `recovery format-root --check`, then
use `--confirm`. This is a separate destructive reinstall operation, not boot
repair; it leaves Android and the ESP intact. The daemon preparation and
first-install operations have not been hardware-validated on every device.

## Verify OEM fastboot and select B

Replace `SERIAL` with the physical tablet's serial, and inspect these read-only
results before changing slots or writing firmware:

```sh
fastboot -s SERIAL getvar serialno
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar modelname
fastboot -s SERIAL getvar unlocked
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL getvar partition-size:boot_b
fastboot -s SERIAL getvar partition-size:dtbo_b
```

Require the matching serial, OEM product `taro`, exact modelname `TB320FC` and
an unlocked bootloader. `dtbo_b` must be exactly 24 MiB (`0x1800000`); the checked
U-Boot flash also validates its image and `boot_b` capacity. A `taro` product
alone does not identify Asphalt. Stop on an unexpected identity or capacity.

If B is not already active, select it explicitly **after** confirming that
identity; this does not flash A:

```sh
fastboot -s SERIAL set_active b
fastboot -s SERIAL getvar current-slot
```

Both checked flash and erase require current slot B and revalidate the device
on execution. Do not bypass a refused check with raw fastboot writes. See
[the CLI identity rules](../../pkgs/mobile-device/README.md#fastboot).

## Erase B DTBO and boot

An Android/LineageOS install can restore incompatible stock overlays. With the
verified tablet in OEM fastboot and B active, use the image-free operation:

```sh
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b --execute
```

Review the check before executing. This requires live `taro`/`TB320FC`, matching
explicit serial, current B and exact 24 MiB capacity; recovery identity records
cannot replace the live model for erase. No zero DTBO image is needed. Only
`dtbo_b` is erased; preserve `dtbo_a`, A, super, recovery and calibration.
If erase fails, inspect the error rather than automatically flashing another image.
After successful U-Boot installation/restoration and DTBO preparation, reboot:

```sh
fastboot -s SERIAL reboot
```

Verify the EFI generation, running kernel, root/ESP, SSH and rollback after boot.
EFI loading is distinct from a healthy Linux boot. Independently verify the
available recovery before relying on it for later maintenance.
