# mobile-device

[中文](README.zh.md)

`mobile-device` is a host-side Python CLI for Android fastboot, a NixOS RAM
recovery, and an installed NixOS mobile system. Install it with
`nix profile install .#mobile-device` or run it with
`nix run .#mobile-device -- ...`. `fastboot`, `nix`, and `ssh` are provided
by the package. Recovery commands use SSH; set TOML `target` or `recovery --target HOST`.
See [connection setup](../../docs/recovery.md).

Supply an already built image or system and, when multiple devices are
connected, `--serial` for fastboot or `recovery --target HOST` for SSH. Commands that write a partition, select a system, or
reboot through the installation/deployment commands run a check by default; add
`--execute` to carry them out. Explicit `mount`, `unmount`, file transfers and
`rebuild boot` act immediately; rebuild requires an already mounted writable target.

## Optional device defaults

Put local defaults in a TOML file outside the tool source. Command-line options
override them. Omit values you do not use.

```toml
serial = "YOUR_FASTBOOT_SERIAL"
result_file = "/run/YOUR_INITIAL_INSTALL_RESULT"
boot_image = "YOUR_BOOT_IMAGE_NAME"
update_program = "YOUR_SYSTEM_UPDATER_NAME"
target = "YOUR_SSH_HOST"
```

Use `mobile-device --config device.toml ...`. A single connected fastboot target can also be selected automatically when no serial is given.
Pass `--config` and `--serial` before the command group.

## Fastboot

```sh
mobile-device --serial SERIAL fastboot boot ./recovery.img
mobile-device --serial SERIAL fastboot boot ./recovery.img --execute
mobile-device --serial SERIAL fastboot flash ./recovery.img --partition recovery
mobile-device --serial SERIAL fastboot flash ./recovery.img --partition recovery --execute
```

The check parses Android v0-v2 ARM64 boot images and their actual DTB root
compatible, matches the connected fastboot product, and checks flash capacity.
It accepts only `boot`/`recovery` on Clover/Polaris, or explicit `boot_b`/`recovery_b`
with active slot B on Asphalt/Sheng. Recovery images must target the recovery
partition. DTBO, rootfs, stock/vendor images without a supported DTB, and unknown
products are outside this command's scope. Image filenames and per-device serial
allowlists are not used as board identity. Both check and execute validate again;
only `--execute` sends the final boot/flash command. Size and SHA-256 are printed
for review; these structural checks do not authenticate an image's publisher.

## RAM recovery

Every device exposes `/bin/recovery`; the host tool calls it automatically.
No command selector or TOML command setting is needed. Configure `target` for SSH.
All four boards expose [shared `install-initial`](../../docs/initial-install.md),
using `/run/mobile-initial-install.result` by default. Prepare the empty root and
FAT boot partition separately; installation does not partition or format storage.
All EFI recovery updates automatically use `/run/mobile-offline-deploy.result`.
Follow the matching first-install guide before formatting:
[Asphalt](../../docs/asphalt/first-install.md),
[Polaris](../../docs/polaris/first-install.md),
[Sheng](../../docs/sheng/first-install.md),
[Clover](../../docs/clover/first-install.md).
Polaris uses `format-userdata`; the other three devices use `format-root`.

Polaris additionally uses physical `system` as FAT32 `/boot`. After preparing
ext4 userdata, check `recovery prepare-boot`, then explicitly run
`recovery prepare-boot --execute`. For an existing system, the complete Nix
store must reside on userdata before repurposing system. GPT geometry is unchanged.

```sh
mobile-device --config device.toml recovery status
mobile-device --config device.toml recovery reboot system
mobile-device --config device.toml recovery reboot system --execute

# Only for a first installation: explicit ext4 format of existing userdata.
mobile-device --config device.toml recovery format-userdata
mobile-device --config device.toml recovery format-userdata --execute

# For Y700 2023, Sheng, and Clover LTE, after checking the device guide.
mobile-device --config device.toml recovery format-root
mobile-device --config device.toml recovery format-root --execute

# The matching bootstrap-info output contains registration and store-paths.
mobile-device --config device.toml recovery install-initial /nix/store/...-nixos-system-polaris-version \
  --bootstrap-info ./result-polaris-bootstrap
mobile-device --config device.toml recovery install-initial /nix/store/...-nixos-system-polaris-version \
  --bootstrap-info ./result-polaris-bootstrap --execute

# Update an installed system.
mobile-device --config device.toml recovery deploy /nix/store/...-nixos-system-device-version
mobile-device --config device.toml recovery deploy /nix/store/...-nixos-system-device-version --execute

# Optional Nix daemon socket copy with progress on the recovery screen.
mobile-device --config device.toml recovery copy /nix/store/...-nixos-system-device-version
```

For an installed system that needs a device-specific recovery request script:

```sh
mobile-device recovery --target HOST enter \
  --script ./request-recovery.sh \
  --support-script ./storage-roles.sh --support-env STORAGE_ROLES
mobile-device recovery --target HOST enter \
  --script ./request-recovery.sh \
  --support-script ./storage-roles.sh --support-env STORAGE_ROLES --execute
```

The script must accept `--check` and `--execute`. The support environment
variable name is supplied by the caller; Polaris' scripts use
`POLARIS_STORAGE_ROLES`.

For a recovery image installer already supplied by the repository, use
`recovery install-image IMAGE --installer SCRIPT --partition DEVICE_PATH`
with the same optional `--support-script` and `--support-env` pair. The host
calls the installer's `--check` or `--execute` mode. The installer must accept
`MODE IMAGE IMAGE_SHA256 OLD_PARTITION_SHA256`.

## Installed system update

Supply a built NixOS system and the updater/boot-image names inside it. If the
connection drops during an update, inspect the updater's systemd journal on
the device.

```sh
mobile-device --config device.toml system update /nix/store/...-nixos-system-device-version
mobile-device --config device.toml system update /nix/store/...-nixos-system-device-version --execute
mobile-device --config device.toml system --via ssh update /nix/store/...-nixos-system-device-version --execute
```

Without a config, add `--boot-image NAME --update-program NAME` after the
system path, and `--target HOST` before `update` for SSH. The default systemd
unit is `mobile-device-update`; use `--unit NAME` for another update service.

Run device-specific cleanup or diagnostics scripts through the same transport:

```sh
mobile-device --config device.toml system script ./prune-system.sh
mobile-device --config device.toml system script ./prune-system.sh --execute
mobile-device --config device.toml system --via ssh script ./prune-system.sh --execute
```

`system script` passes `--check` by default and no option with `--execute`.
Run `mobile-device --help` and the command-specific `--help` for all options.

## Target mounts and offline rebuild

```sh
mobile-device --config device.toml recovery mount
mobile-device --config device.toml recovery target-status
mobile-device --config device.toml recovery unmount
mobile-device --config device.toml recovery mount --rw
mobile-device --config device.toml recovery rebuild boot --store-path /nix/store/...-nixos-system-device-version
mobile-device --config device.toml recovery unmount
```

Mount/unmount and shell/file operations run directly. Offline rebuild is an
explicit write operation and accepts only boot; destructive partition/installer
commands retain their check/--execute interface. `shell`, `exec`, `push`, `pull`
provide the supported management operations. File transfers verify SHA-256.
