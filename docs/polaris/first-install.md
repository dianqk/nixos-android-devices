# First install on Polaris

[中文](first-install.zh.md) · [Device guide](README.md) · [Storage preparation](manual-storage.md)

Polaris uses physical `system` as FAT32 `/boot`, `userdata` as ext4 `/`, and
`boot` for U-Boot. GPT geometry and partition types stay unchanged. This device
has **no A/B slots**; use `boot` and `recovery` without slot suffixes.

You need an unlocked phone, a Linux build host with Nix flakes enabled, USB
fastboot/SSH access, and a userdata partition of at least 16 GiB (the
`androidDevices.recovery.minimumRootBytes` default) with room for the system
closure plus 1 GiB. Formatting erases the selected partition.

## Android base before installation

**The Polaris adaptation baseline is the latest LineageOS 22.2 build for
`polaris`. Prepare that release before installing NixOS.** Here, “latest” means
the latest build within the 22.2 series, not a newer LineageOS major release.
No exact build date is pinned by this guide.

Before replacing Android, verify and record the installed build:

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.lineage.version
adb -s SERIAL shell getprop ro.build.fingerprint
```

Confirm `polaris` and a `22.2-…` LineageOS version. Complete Android preparation
before formatting `system` and `userdata` for NixOS; Polaris has no second slot
in which to retain Android. NixOS updates do not install or update LineageOS.

## Identify this phone

From this repository, build and temporarily boot RAM recovery. Replace
`FASTBOOT_SERIAL` with the phone's serial from `fastboot devices`. The first
fastboot command checks the target and image; `--execute` boots it.

```sh
nix build .#devices.polaris.recovery -o result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

Set up `RECOVERY_HOST` and its host key using the [connection guide](../recovery.md).
Full recovery may briefly access an existing Linux root for its SSH identity;
it does not format storage and leaves no target mounted. Inspect the layout:

```sh
ssh -T RECOVERY_HOST 'lsblk -b -o NAME,SIZE,PARTUUID,PARTLABEL,START,FSTYPE,LABEL,UUID'
```

Confirm unique `system`, `userdata`, `boot` and `misc` GPT names on the built-in
UFS. Recovery requests require a 4 MiB `misc` partition. Recovery checks the
board, controller, partition names, kernel geometry and filesystem labels. For
exact per-phone checks, add measured values to `hardware.polaris.storageRoles`
(see [single-slot devices](../recovery.md#single-slot-devices-clover-and-polaris)).

## Build matching system and recovery

Copy the [consumer flake](../../examples/consumer/flake.nix) and follow the
[configuration guide](../configuration.md). Select `device = "polaris"`, set the
build host architecture and a unique USB serial, and add your SSH public key.
Keep the root label (default `NIXOS`) and any `storageRoles` shared between
system and recovery. The sample starts a console system with radios/audio off.

From your configuration directory, with the files tracked by Git:

```sh
nix build .#system -o result-system
nix build .#bootstrap-info -o result-bootstrap-info
nix build .#recovery -o result-recovery
nix profile install .#mobile-device
```

Build all three outputs from the same locked configuration. The system already
includes its matching U-Boot image.

## Install from RAM recovery

Temporarily boot the recovery built from your configuration and reconnect SSH:

```sh
mobile-device --serial FASTBOOT_SERIAL fastboot boot result-recovery
mobile-device --serial FASTBOOT_SERIAL fastboot boot result-recovery --execute
```

If userdata is not an empty ext4 filesystem with the configured label, check
and explicitly format it. **This erases userdata.**

```sh
mobile-device recovery --target RECOVERY_HOST format-root
mobile-device recovery --target RECOVERY_HOST format-root --execute
```

Prepare physical `system` as FAT32. A matching FAT filesystem is checked and
retained; otherwise this erases its contents. GPT geometry stays unchanged.

```sh
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

Check and install the system:

```sh
SYSTEM=$(readlink -f result-system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info --execute
```

The [first installer](../initial-install.md) verifies the closure, installs EFI
files, then writes U-Boot to `boot`. An incomplete installation blocks reboot;
stay in recovery and follow the installer's failure guidance. After success:

```sh
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

Verify SSH, the [generation menu](boot-menu.md) and independent RAM recovery.
Subsequent [system updates](../usb-signaller.md) maintain EFI files without
rewriting U-Boot; recovery `deploy` updates an existing system.
