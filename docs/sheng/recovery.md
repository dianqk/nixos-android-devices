# Sheng recovery operations

[中文](recovery.zh.md) · [Device overview](README.md)

This guide covers entering RAM recovery, offline system deployment and updating
`recovery_b`. For routine system updates, use the [USB SSH guide](../usb-signaller.md).
For first installation and firmware layout, see [installation preparation](first-install.md).

`SYSTEM_HOST` and `RECOVERY_HOST` are your OpenSSH host aliases with separately
pinned host keys; see [connection setup](../recovery.md). `--target` selects SSH;
`--serial` is only for fastboot. The `mobile-device` mutation commands below
perform checks only when `--execute` is omitted.

## Enter RAM recovery

Run `mobile-device` on the build computer from this repository root; the script
paths below are relative to it.

```sh
mobile-device recovery --target SYSTEM_HOST enter \
  --script devices/sheng/request-recovery.sh \
  --support-script devices/sheng/slot-gate.sh --support-env SHENG_SLOT_GATE \
  --execute
mobile-device recovery --target RECOVERY_HOST status
```

The request checks the installed Sheng system, bootloader evidence for B,
UFS/GPT identity and the 4 MiB `misc` partition. It changes only the 32-byte
BCB command to `boot-recovery`, verifies the whole partition and then the host
tool requests a normal reboot. An unknown existing BCB command is refused.

## Update from RAM recovery

```sh
mobile-device recovery --target RECOVERY_HOST deploy tmp/systemd-artifacts/system
mobile-device recovery --target RECOVERY_HOST deploy tmp/systemd-artifacts/system --execute
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
mobile-device recovery --target RECOVERY_HOST install-image tmp/systemd-artifacts/recovery \
  --installer devices/sheng/install-recovery.sh \
  --partition /dev/disk/by-partlabel/recovery_b \
  --support-script devices/sheng/check-recovery-image.sh --support-env SHENG_IMAGE_CHECK \
  --execute
mobile-device recovery --target RECOVERY_HOST reboot recovery --execute
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

The support script permits updating an older recovery that lacks the packaged
image checker. New recovery images also include `sheng-install-recovery` and
`sheng-check-recovery-image`; `recovery install-recovery --check|--execute
IMAGE SHA256 EXPECTED_OLD_SHA256` invokes the installer on the device.

The installer fixes its destination to `recovery_b`, checks B-slot provenance,
Sheng/UFS/GPT identity, capacity, transfer hash and the existing partition hash.
It accepts only a complete 100 MiB Android v0 image with an appended Sheng
root DT compatible, the RAM-recovery command line, and the repository's
unsigned AVB recovery hash descriptor. It then verifies the full partition
against the image SHA-256. A truncated image, system boot image, other board's
image, or stale partition hash is refused before writing. This is format and
integrity validation; it does not establish publisher authenticity.

Stock `vbmeta_b` chains `recovery_b` even for normal B boots. Keep the complete
AVB footer rather than flashing a short payload or changing vbmeta flags.
Recovery updates do not select slots or mark a boot successful. Automatic
Linux boot-success acknowledgement is not enabled.
