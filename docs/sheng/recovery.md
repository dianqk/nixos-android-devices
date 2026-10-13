# Sheng recovery operations

[中文](recovery.zh.md) · [Device overview](README.md)

This guide covers entering RAM recovery, offline system deployment and updating
`recovery_b`. For routine system updates, use the [USB SSH guide](../usb-signaller.md).
For first installation and firmware layout, see [installation preparation](first-install.md).

`RECOVERY_HOST` is your OpenSSH host alias for recovery, with its own pinned
host key; see [connection setup](../recovery.md). `--target` selects SSH;
`--serial` is only for fastboot. The `mobile-device` mutation commands below
perform checks only when `--execute` is omitted.

## Enter RAM recovery

From the installed system, reboot and choose **Reboot to recovery** in the
systemd-boot menu (see [boot actions](../boot-actions.md)). It boots the NixOS
RAM recovery in `recovery_b` without changing Android A. Then connect:

```sh
mobile-device recovery --target RECOVERY_HOST status
```

## Update from RAM recovery

```sh
mobile-device recovery --target RECOVERY_HOST deploy result-system
mobile-device recovery --target RECOVERY_HOST deploy result-system --execute
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

Use the system matching your configured root label and hostname. The recovery
imports and verifies the missing closure, selects the new generation and
installs its EFI files on FAT `/boot`. U-Boot firmware stays unchanged.
Retained generations and the Linux home remain available. A pending deployment must be resumed before booting.

## Update recovery itself

Run this while the current recovery is resident in RAM, with all block
filesystems unmounted and swap disabled:

```sh
mobile-device recovery --target RECOVERY_HOST install-image result-recovery \
  --partition /dev/disk/by-partlabel/recovery_b \
  --execute
mobile-device recovery --target RECOVERY_HOST reboot recovery --execute
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

The Rust daemon owns recovery writes. On-device commands are
`recovery update-recovery IMAGE --check` and `--confirm`. It requires B, matching
board/partition identities, a complete 100 MiB image and a valid unsigned AVB
recovery hash, then verifies the full partition after writing. Format/integrity
checks do not establish publisher authenticity.

Stock `vbmeta_b` chains `recovery_b` even for normal B boots. Keep the complete
AVB footer rather than flashing a short payload or changing vbmeta flags.
Recovery updates do not select slots or mark a boot successful. Automatic
Linux boot-success acknowledgement is not enabled.
