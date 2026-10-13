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
with active slot B on Asphalt/Sheng/Aurora. Recovery images must target the recovery
partition. Arbitrary DTBO, rootfs, stock/vendor images without a supported DTB, and unknown
products are outside this command's scope. Image filenames and per-device serial
allowlists are not used as board identity. Both check and execute validate again;
only `--execute` sends the final boot/flash command. Size and SHA-256 are printed
for review; these structural checks do not authenticate an image's publisher.

Some Asphalt OEM bootloaders report the SoC product `taro`. That product alone
does not identify a tablet. For Asphalt/taro, the CLI accepts the OEM
`modelname` only when it is exactly `TB320FC`, with an explicit `--serial` matching
fastboot `serialno`. It rechecks this model, serial, B slot, image and capacity
on every check and execution. Other nonempty model names are refused, including
when a recovery identity is supplied. Missing/unsupported modelname can use the
trusted recovery observation below; malformed responses and transport errors
are refused. No generic taro product allowlist is used.

For a tablet already verified in independent NixOS RAM recovery, supply a trusted
device identity JSON record
with `--device-identity FILE` and an explicit `--serial`:

```json
{
  "version": 1,
  "serial": "YOUR_DEVICE_SERIAL",
  "product": "taro",
  "compatible": ["lenovo,asphalt", "qcom,sm8475"],
  "source": "nixos-ram-recovery",
  "collected_at": "2026-10-02T08:00:00+00:00",
  "boot_id": "12345678-1234-1234-1234-123456789abc"
}
```

Record the actual complete `/proc/device-tree/compatible` list, serial from
`/proc/cmdline`, `/proc/sys/kernel/random/boot_id`, collection time and observed
OEM product after confirming the matching tablet and RAM recovery. Replace all
example values. This record is a trusted observation, not cryptographic hardware
authentication; DT compatible originates in the boot image. The supported
supplement is limited to Asphalt with product `taro`. Both check and execution
match the explicit serial, record and current fastboot `serialno`, then retain
the image, B slot, partition and capacity checks. Supplied invalid records are
always refused.

```sh
mobile-device --serial YOUR_DEVICE_SERIAL fastboot flash ./u-boot.img \
  --partition boot_b --device-identity ./device-identity.json
# Repeat the same command with --execute after reviewing its checked target.
```

### Asphalt DTBO erase

Asphalt's U-Boot/mainline B boot path requires disabling the stock `dtbo_b`
overlay. Android/LineageOS installation may restore an incompatible overlay.
Use this separate, explicit operation only when restoring that B boot path;
preserve Android A and recovery. No zero image is needed.

The CLI requires `--device asphalt`, live OEM product/modelname `taro`/`TB320FC`,
an explicit matching serial, active B and exactly 24 MiB `dtbo_b` capacity.
A recovery identity record cannot substitute for the live model in this operation.

```sh
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b
# Review the checked target, then repeat with --execute.
```

Erase accepts no image. Other boards, slots and partition targets are unsupported.
An erase failure is reported without automatically flashing a replacement image.

## RAM recovery

Every device's recovery runs the Rust recovery daemon and exposes the
`/bin/recovery` client; the host tool calls it automatically and refuses a
recovery without the daemon protocol. Configure `target` for SSH.
All five boards expose [shared `install-initial`](../../docs/initial-install.md).
Prepare the empty root and FAT boot partition separately; installation does not
partition or format storage. Follow the matching first-install guide before
formatting:
[Asphalt](../../docs/asphalt/first-install.md),
[Polaris](../../docs/polaris/first-install.md),
[Sheng](../../docs/sheng/first-install.md),
[Aurora](../../docs/aurora/README.md),
[Clover](../../docs/clover/first-install.md).

Single-slot Polaris and Clover use physical `system` as FAT32 `/boot`. After
`format-root`, check `recovery prepare-boot`, then explicitly run
`recovery prepare-boot --execute`. GPT geometry is unchanged.

```sh
mobile-device --config device.toml recovery status
mobile-device --config device.toml recovery reboot system
mobile-device --config device.toml recovery reboot system --execute

# Only for a first installation, after checking the device guide.
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
```

To enter recovery from an installed system, choose **Reboot to recovery** in
the systemd-boot menu.

Update a firmware or recovery image with the checked daemon operations:

```sh
mobile-device recovery --target HOST install-image ./recovery.img \
  --partition /dev/disk/by-partlabel/recovery_b
mobile-device recovery --target HOST install-image ./recovery.img \
  --partition /dev/disk/by-partlabel/recovery_b --execute
```

`--partition` is the `/dev/disk/by-partlabel/` path of `boot` or `recovery`
(`boot_b`/`recovery_b` on A/B devices). The
daemon validates the image identity, size and target before writing and reads
it back.

## Installed system scripts

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
