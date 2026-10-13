# Boot-menu power and reboot actions

[中文](boot-actions.zh.md)

All five device modules enable **Reboot The System**, **Power Off The System**,
**Reboot to bootloader**, and **Reboot to recovery** in systemd-boot. Asphalt, Sheng and
Aurora also enable **Reboot to Android**. These run before Linux. Keep independent
RAM recovery available when updating firmware.

| Device profile | Recovery | Android | Firmware backend |
| --- | --- | --- | --- |
| Polaris / Clover | OEM recovery target | Not enabled | Qualcomm PON |
| Asphalt / Sheng / Aurora | NixOS RAM recovery installed in `recovery_b` | Android `boot_a` | Qualcomm SDAM + GPT A/B + UFS boot LUN |

The reboot targets are not yet verified on hardware on any device; compilation and simulated fault tests do not
verify the OEM firmware's behavior or installed recovery.

## Configure

Import the exported device module, such as `nixosModules.sheng`. Device modules
supply defaults; the shared module uses explicit options rather than device-name
selection. Individual actions can be disabled:

```nix
{
  androidDevices.boot.actions = {
    reboot = true;
    poweroff = true;
    bootloader = true;
    recovery = true;
    recoveryTarget = "slot-b"; # Asphalt/Sheng; "oem" for Polaris/Clover
    android = true;           # Requires the Qualcomm A/B firmware backend
  };
}
```

The helper is shared across profiles. Firmware builds select an explicit reusable
`pon` or `qcom-ab` profile; the latter includes the SDAM and UFS slot backend.
Native and cross builds use the same policy and different compiler platforms.
RAM recovery configurations do not install this EFI menu or helper.

## Automatic slot B confirmation

Sheng, Asphalt and Aurora share one U-Boot patch and Qualcomm GPT/UFS backend. After
`fatload` / `bootefi` successfully loads `/EFI/BOOT/BOOTAA64.EFI` from the unique
`linux-boot` ESP and sets up its load options, U-Boot marks **`boot_b` successful**
before starting the EFI image. This acknowledges the firmware/storage/EFI-load
stage; it does not certify that the generation menu is displayed or Linux works.
Other EFI paths, devices and partitions do not trigger confirmation. This hook
does not cover EFI BootOrder/boot-manager entry execution.

Only the successful bit and required CRCs in both GPT copies change. Android A,
type and unique GUIDs, active flags, priorities, retry counters, UFS boot LUN,
BCB and partition contents are preserved. Already-successful B needs no writes.
The last allowed attempt with zero remaining retries can still be confirmed;
Android A bootability, an empty BCB and `recovery_b` are not prerequisites.

The common firmware profile explicitly enables confirmation and supplies the ESP
name and EFI path. Polaris and Clover do not enable it. Different partition/LUN
locations are discovered at runtime; this Qualcomm backend is not suitable for
devices using AOSP `misc` boot-control metadata. Asphalt has prior hardware
evidence for this minimal successful-bit update; the new hook and Sheng's OEM
behavior still need hardware validation.

Asphalt permits a zero-metadata layout on LUN6 and LUN7 **only for successful
B confirmation**. This compatibility setting comes from one observed unit; it
is not a claim about every Asphalt's factory layout. Each enabled candidate LUN
is checked at runtime: its complete LBA0, LBA1 and final blocks must be readable.
If all three are zero-filled it may be omitted from GPT checks; otherwise it
must pass the same complete dual-GPT checks as every other GPT-bearing LUN.
Thus other Asphalt units with valid GPTs on these LUNs remain supported. Absent
or disabled candidate LUNs need no exception. A zero metadata block does not
mean the whole LUN is empty; firmware never formats a LUN to satisfy this check.
All enabled LUNs must still be present. Other devices default to no exceptions;
Android and recovery actions do not use this confirmation-only exception.

The firmware settings are built into U-Boot, rather than set with `setenv`:

```text
CONFIG_EFI_MOBILE_BOOT_ACTION=y
CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB=y
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM=y
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP="linux-boot"
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH="/EFI/BOOT/BOOTAA64.EFI"
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK=192
```

The final setting is a decimal bitmask: 192 selects bits 6 and 7 on Asphalt.
The shared profile accepts an explicit `confirmationNonGptLunMask`, default 0;
it never selects exceptions by device name. Do not copy Asphalt's mask to other
hardware without verifying that hardware's layout. Read failures, bad CRCs and conflicting copies remain errors, including on
candidate LUNs. Nonzero metadata never qualifies for the zero-metadata exception.

A confirmation error is logged and EFI execution continues. Returned write or
readback errors attempt GPT restoration; failed restoration disables further
confirmation and special boot actions in that U-Boot session. Backup-first writes
and readback do not make an interrupted GPT update atomic across power loss.
Install rebuilt U-Boot in `boot_b` to enable this behavior; updating EFI files
alone does not update firmware.

## Android slot-switch checks

The Android action changes the persistent active slot to A and requests an OEM
reboot. It does not chainload Android's kernel from U-Boot. Its layout policy is
independent of automatic B confirmation:

```text
CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK=192
```

The shared firmware profile's `androidNonGptLunMask` defaults to 0; Asphalt uses
192 for the observed LUN6/7 candidates. Recovery keeps the full GPT requirement.
Every enabled LUN remains accounted for. Only configured candidates whose LBA0,
LBA1 and last blocks all read as zero qualify; any nonzero metadata undergoes
full GPT validation. A LUN with a boot ID cannot use this exception.

Before offering Android and again before executing, firmware binds UFS boot
selector IDs 1 and 2 to the physical LUNs containing `xbl_a` and `xbl_b`.
Missing, duplicate, disabled or misplaced boot-ID mappings refuse the action.
The configuration descriptor must enable the boot feature. Selector values
are not assumed to equal ordinary LUN numbers.

An empty BCB command alone does not exclude an OTA snapshot operation. Firmware
also reads the 64-byte Virtual A/B record at `misc + 32 KiB`. This implementation
accepts only version 2 with its known magic, a source slot of 0 or 1, zero reserved
bytes and status NONE. The source slot records a historical write and need not
match the current B slot. UNKNOWN, SNAPSHOTTED, MERGING, CANCELLED, unsupported
formats and read errors refuse the action; firmware never clears or cancels
snapshot state. Supporting another format or CANCELLED requires further review.
Other system-space records are preserved and need not be zero.

These checks establish metadata prerequisites, not the integrity or successful
boot of every Android/early-firmware payload. Preserve an independently verified
recovery and return-to-B procedure before a real slot-switch trial. Firmware
logs identify GPT LUN, boot mapping, snapshot or slot/request failures.

## Build, install and update

Build matching system, boot-files and U-Boot outputs using the
[configuration guide](configuration.md), then follow the checked
[U-Boot installation workflow](u-boot-install.md). On Asphalt/Sheng, preserve
Android A and install NixOS recovery in **`recovery_b`**, separately from U-Boot
in **`boot_b`**. See the [recovery guide](recovery.md). The menu does not install
or replace either image; it can check partition metadata, not certify the
recovery payload.

The EFI helper and entries are installed with the initial boot-files bundle and
subsequent standard NixOS bootloader updates. Disabling an action removes its
entry on the next update; disabling all special actions removes the helper.

An ordinary `nixos-rebuild boot` updates EFI files but does not replace U-Boot in
the physical boot partition. An existing installation needs a separate checked
U-Boot update to provide the interface. Old firmware refuses unsupported actions
and returns to the menu. The new `recovery-b` capability is distinct from OEM
recovery, so an old PON backend cannot execute it by mistake.

## Use and troubleshoot

Special entries show a confirmation screen with **Cancel** selected. Use volume
up/down to select and a short power press to confirm; serial/USB ACM console
input can also be used. Escape cancels. There is no timed automatic execution,
even if a special entry is saved as the default. Cancellation and returned
operation errors return to the generation menu.

Bootloader means the **OEM bootloader fastboot**, distinct from U-Boot fastboot
and Android userspace fastbootd. Reboot and shutdown use systemd-boot's built-in
entries and do not switch slots.

For Polaris/Clover, recovery requests the OEM recovery target using its installed
contents; it does not directly launch an EFI NixOS recovery. These actions modify
only PON's reason byte, preserve bit 0, verify readback and request PSCI reset.
They write no partition or slot metadata; existing BCB requests may affect the
resulting target.

For Asphalt/Sheng:

- **Recovery** requires B active and bootable, UFS boot LUN 2, consistent GPTs
  and `recovery_b`. It changes only SDAM reboot-mode bits and preserves bit 0.
- **Android** requires a bootable A, the same verified active-B slot state and a NUL-empty
  BCB command in `misc`, verified boot-LU mapping and a known snapshot NONE state.
  A pending recovery/OTA command is refused rather than
  silently cleared. It changes paired partition type GUIDs and active flags,
  selects `boot_a` at priority 3 with seven retries, clears A's success/unbootable
  flags, and selects UFS boot LUN 1. B's success/retry flags survive; its priority
  becomes 2. XBL selection uses the boot LUN and leaves its entries unchanged.
  Android A selection persists until another authorized slot change, such as
  OEM fastboot `set_active b` or Android's boot-control interface. Selecting B
  again resets its success/retry state according to that interface.
- **Bootloader** needs only the SDAM/PSCI backend; unavailable storage does not
  prevent entering OEM fastboot.

Slot checks require every enabled UFS LUN to be present, 4096-byte logical
sectors, supported GPT headers and 128-byte entries on GPT-bearing LUNs, matching primary/backup
arrays with valid CRCs, unique names and complete consistent A/B pairs. Unknown
or corrupt layouts, inconsistent slot/boot-LUN state, a missing recovery
partition or outstanding BCB command cause refusal without a reset or write.
If an action is unavailable, inspect these conditions through Linux or RAM
recovery before retrying. The special menu remains visible for diagnosis even
when firmware declines its capability.

GPT writes preserve partition contents, unique GUIDs, geometry, PMBR and padding.
They update only changed metadata blocks, backup before primary, and verify
uncached readback. The fixed U-Boot SCSI write path uses FUA for durable writes.
On returned I/O, readback or reset errors, the backend attempts to restore GPTs,
boot LUN and the original reason, tries all restorations, and reports an
aggregate restoration error. A failed restore disables further special actions
for that firmware session; inspect state before rebooting or retrying.

A multi-LUN GPT/boot-LUN switch cannot be atomic across sudden power loss. Use a
reliable power supply; the rollback guarantee covers returned errors, not power
failure. No partition payload, Android super contents or fuses are written.

A watchdog setup failure returns promptly to the parent menu. An entry that
cannot load at all follows systemd-boot's configured `reboot-on-error` policy.
