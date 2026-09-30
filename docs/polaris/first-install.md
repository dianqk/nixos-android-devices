# First install on Polaris

[中文](first-install.zh.md) · [Device guide](README.md) · [Manual storage commands](manual-storage.md)

Polaris uses physical `system` as FAT32 `/boot`, `userdata` as ext4 `/`, and
`boot` for U-Boot. GPT geometry and partition types stay unchanged. This device
has **no A/B slots**; use `boot` and `recovery` without slot suffixes.

You need an unlocked phone, a Linux build host with Nix flakes enabled, USB
fastboot/SSH access, and room for the system closure plus at least 1 GiB on
userdata. Formatting erases the selected partition.

## Identify this phone

From this repository, build and temporarily boot RAM recovery. Replace
`FASTBOOT_SERIAL` with the phone's serial from `fastboot devices`. The first
fastboot command checks the target and image; `--execute` boots it.

```sh
nix build .#devices.polaris.recovery -o tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery --execute
```

Set up `RECOVERY_HOST` and its host key using the [connection guide](../recovery.md).
Recovery does not mount or write partitions at startup. Inspect the layout:

```sh
ssh -T RECOVERY_HOST 'lsblk -b -o NAME,SIZE,PARTUUID,PARTLABEL,START,FSTYPE,LABEL,UUID'
```

Confirm unique `system`, `userdata`, `boot` and `misc` GPT names on the built-in
UFS. The reboot helper requires a 4 MiB `misc` partition. Recovery checks the
board, controller, partition names and filesystem labels. For exact per-phone
UUID and geometry checks, supply a measured
[`storage-roles.example.sh`](../../devices/polaris/storage-roles.example.sh)
through `hardware.polaris.storageRolesFile`.

## Build matching system and recovery

Copy the [consumer flake](../../examples/consumer/flake.nix) and follow the
[configuration guide](../configuration.md). Select `device = "polaris"`, set the
build host architecture and a unique USB serial, and add your SSH public key.
Keep the root label (default `NIXOS`) and any storage contract shared between
system and recovery. The sample starts a console system with radios/audio off.

From your configuration directory, with the files tracked by Git:

```sh
nix build .#system -o tmp/systemd-artifacts/system
nix build .#bootstrap-info -o tmp/systemd-artifacts/bootstrap-info
nix build .#recovery -o tmp/systemd-artifacts/recovery
nix profile install .#mobile-device
```

Build all three outputs from the same locked configuration. The system already
includes its matching U-Boot image.

## Install from RAM recovery

Temporarily boot the recovery built from your configuration and reconnect SSH:

```sh
mobile-device --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/recovery
mobile-device --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/recovery --execute
```

If userdata is not an empty ext4 filesystem with the configured label, check
and explicitly format it. **This erases userdata.**

```sh
mobile-device recovery --target RECOVERY_HOST format-userdata
mobile-device recovery --target RECOVERY_HOST format-userdata --execute
```

Prepare physical `system` as FAT32. A matching FAT filesystem is checked and
retained; otherwise this erases its contents. GPT geometry stays unchanged.

```sh
mobile-device recovery --target RECOVERY_HOST prepare-boot
mobile-device recovery --target RECOVERY_HOST prepare-boot --execute
```

Check and install the system:

```sh
SYSTEM=$(readlink -f tmp/systemd-artifacts/system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info tmp/systemd-artifacts/bootstrap-info --execute
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
