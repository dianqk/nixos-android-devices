# Rust recovery service

Every device's full recovery runs `mobile-recovery-daemon`, the VT screen and the
`recovery` Rust client. The ACM console starts `recovery shell`; SSH users can
run the same commands directly. Project Python tooling runs only on the host. Standard NixOS tools invoked
inside the installed target (including nixos-rebuild-ng and its EFI installer)
may use that system's own Python dependency; this interpreter is not copied into
the recovery initrd. Recovery does not fall back to project scripts.

The daemon has no board-name branches. Each device module supplies explicit
inputs in `/etc/mobile-recovery.json`: the slot model (`ab` for Asphalt, Sheng
and Aurora; `single` for Clover and Polaris), device-tree and firmware
compatibles, storage controller, the boot-request mechanism (reboot argument or
`boot-recovery` BCB, with an optional recovery reboot argument), single-slot
storage roles, an optional UFS safe-mode controller and deployment requirements.

```sh
recovery help
recovery capabilities
recovery status --json
recovery shell
recovery task TASK_ID
recovery cancel TASK_ID
```

The service starts without mounting or changing storage. A single worker owns
storage operations and child processes. Concurrent operation requests fail with
the current task snapshot. Queries and subscribers remain available. Task state
includes its ID, target, operation, phase, measured progress, bounded logs and
result/error. The UI uses the same snapshots as the CLI. Unknown totals are shown
as unknown, rather than estimated percentages.

Cancel is accepted only in phases marked cancellable. GPT writes, formatting,
the Nix build, profile/EFI activation, firmware writes and reboot cannot be cancelled. Cleanup
finishes before another operation can start. Failed cleanup or a worker panic
blocks further jobs; inspect mounts and children before restarting the service.
Systemd uses `KillMode=control-group` and does not automatically restart a failed
service. The service has no persistent job database or power-loss replay.

## Storage and updates

Use the [Asphalt](../../docs/asphalt/first-install.md), [Sheng](../../docs/sheng/first-install.md),
[Aurora](../../docs/aurora/README.md), [Polaris](../../docs/polaris/first-install.md)
or [Clover](../../docs/clover/first-install.md) guide for destructive preparation,
first installation and required hardware validation. `install-initial` requires
an already prepared empty ext4 root and FAT ESP; it never repartitions implicitly.
It validates the registered closure, NAR contents, device identity and both fstab
entries, installs and checks EFI, then writes and reads back matching firmware.
An incomplete installation leaves its existing pending marker and requires
explicit inspection/preparation, not automatic continuation.

`mobile-device recovery --target HOST deploy SYSTEM --execute` queries missing
store paths and streams only those paths into the installed Nix database. The
service verifies the whole requested closure before selecting a profile. Normal
updates never write Android boot firmware.

Single-slot devices resolve each storage role (root, ESP, firmware, recovery,
misc) as the unique GPT name on the controller's non-removable disk, check the
kernel geometry and every measured field, and accept 512-byte as well as 4 KiB
logical sectors; root and ESP may sit on different disks. `format-root` formats
the root role, `prepare-boot` the FAT boot partition after verifying the root,
and `safe-ufs` applies a configured UFS safe mode. The installed system's
`mobile-storage-roles.json` must equal the recovery's roles.

For an offline rebuild or generation selection:

```sh
recovery mount-target --rw
recovery rebuild boot --flake /etc/nixos#aurora
recovery generations
recovery select-generation 12 --confirm
recovery unmount-target
recovery deploy-check-boot
```

Target mounts belong to the daemon's private mount namespace. Use `target-status`,
`generations` and `rebuild` through the daemon; an SSH shell does not see its
`/mnt`. This keeps temporary chroot mounts out of other recovery services and
allows complete unmounting between operations.

`rebuild boot` uses the installed `nixos-rebuild build`, then validates the
resulting board and root/ESP entries before invoking the standard Nix profile and
EFI installer. It exposes neither recovery PID1 nor its Nix sockets inside the
chroot. `switch`, `test`, remote deployment and alternate profiles are refused.
Use `select-generation` for rollback. Failed operations retain pending markers;
these are not a promise of automatic recovery after power loss.

Firmware and recovery updates are separate operations:

```sh
recovery update-firmware /tmp/u-boot.img --check
recovery update-firmware /tmp/u-boot.img --confirm
recovery update-recovery /tmp/recovery.img --check
recovery update-recovery /tmp/recovery.img --confirm
```

Updates write only the configured firmware or recovery role (`boot_b`/`recovery_b`
on A/B devices; `boot`/`recovery` on Clover and Polaris). Structural checks
validate the Android header, ARM64 payload, real DTB root compatible and recovery
role. A, DTBO, super and calibration are not write targets. Root users can still
run ordinary diagnostic tools manually; the daemon is not a root sandbox.

To cancel a stale one-time recovery/bootloader request, including before Linux is
installed:

```sh
recovery clear-boot-request --check
recovery clear-boot-request --confirm
```

This validates the device, the configured slot (active B on A/B devices) and the
misc partition, then clears only its 32-byte BCB command. It accepts known
recovery/bootloader commands, preserves the rest of misc and verifies a
full-partition readback. The check is read-only; neither operation changes slots
or reboots. On A/B devices, select Android A separately in the bootloader. `reboot-system` still requires a validated installed Linux system.

## Local protocol and host transfers

The root-only Unix socket is `/run/mobile-recovery/control.sock`; there is no TCP
listener. A version-1 request is a bounded JSON line, for example:

```json
{"version":1,"command":{"action":"status"}}
```

`capabilities`, `status`, `task`, `watch`, `submit`, `input` and `cancel` are control
actions. `watch` returns the latest snapshot after a sequence number, or a
20-second timeout. Reconnects obtain a complete snapshot; subscribers never hold
up the worker. Recent completed tasks are retained in bounded RAM history.

For automation, `recovery submit OPERATION ...` returns the task ID and a one-use
input token when the operation requires data. A separate connection invokes
`recovery input TASK_ID TOKEN` and reads stdin. Binary data uses 64-KiB maximum
frames, each prefixed by a big-endian 32-bit length; a zero length explicitly
completes the transfer. EOF without that completion frame is an error, including
a disconnect after a seemingly complete tar archive. Tokens cannot be reused or
attached to another task. `recovery task TASK_ID` returns the authoritative result.
The host CLI handles this protocol and does not poll legacy result files.

Once input is complete, local verification and installation survive CLI/UI
exit or SSH disconnection. A stalled/incomplete transfer fails and leaves the
appropriate pending marker. Reconnect and inspect the task instead of starting
a duplicate installation.

## Validation status

Sparse-file GPT tests exercise a 1-TB-class 4-KiB disk, the OEM's 64-entry table
and nonadjacent backup array. Tests cover CRC errors, incomplete transactions,
stale plans, B selection, task exclusion/cancellation, child failures, framed
input interruption, protocol bounds, manifest guards and image identities.
Host-only tests and image builds do not establish real-device partitioning,
first boot, USB stability or EFI/kernel handoff.

If first installation fails after the closure was registered and its system
profile selected, repeat the host `mobile-device recovery install-initial`
command with `--resume` and the same system/bootstrap-info. Preview is read-only;
add `--execute` to finish. The daemon requires the matching pending marker and
profile, rejects other pending operations, and rechecks the full closure before
installing EFI files and writing firmware last. It does not retransmit the
closure. Failures before profile selection still require a fresh empty root.
