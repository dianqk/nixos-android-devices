# Xiaomi 14 Ultra (aurora): experimental recovery and EFI system

[中文](README.zh.md)

Support: Tier 2. See [support criteria](../README.md#support-tiers).

Aurora provides an experimental B-slot U-Boot → systemd-boot → NixOS system
and independent RAM recovery. Follow the firmware, configuration and installation
steps below; consult [hardware support and implementation notes](hardware.md)
for audio, USB host, suspend and other validation limits.

## Required factory firmware before installation

**NixOS installation requires the Xiaomi China fastboot ROM OS1.0.3.0.UNACNXM, based on Android 14. Flash this exact
factory base before installing NixOS.** An arbitrary Android 14 ROM, another
region, or Android 16 is not an interchangeable prerequisite.

| Item | Required value |
| --- | --- |
| Device | Xiaomi 14 Ultra, `aurora` |
| Factory fastboot package | `aurora_images_OS1.0.3.0.UNACNXM_14.0` |
| Android release | `14` |
| Runtime incremental build | `V816.0.3.0.UNACNXM` |
| Android security patch | `2024-02-01` |
| NixOS runtime firmware selection | `hardware.aurora.firmwareVariant = "android14";` (default) |

Prepare and flash the matching factory base first, then boot stock Android and
check its identity before following the B-slot recovery/installation steps:

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.build.version.incremental
adb -s SERIAL shell getprop ro.build.version.security_patch
```

These properties confirm the running Android build; after mixed or partial
flashes they do not prove every firmware partition matches. Use the complete
matching factory fastboot package for initial preparation. Keep the bootloader
unlocked. Factory flashing can erase data and replace both slots, AVB and DTBO;
complete it **before** Linux partitioning/installation. Once the base is prepared,
preserve Android A and use only B for Linux. Do not rerun a factory flash script
as a routine NixOS update or assume it restores the original userdata/GPT layout.

The module, standalone firmware package and repository examples default to
Android 14. Select the same variant for recovery and the installed system;
custom firmware-package/NVM overrides must match too. Rebuild the initrd and
reboot when changing variants. The [legacy Android 16 variant](firmware.md#legacy-android-16-variant)
is not a supported installation base, and Android 14 runtime firmware on an
Android 16 base is not verified.
Factory reflashing or Android OTA may change the base; recheck it before using
NixOS again. See [firmware contents and limits](firmware.md).

Before the first B-slot boot, also verify the [factory display firmware](#keep-b-slot-boot-display-firmware-intact).

## Configure and build

Use the exported module with the public build environment:

```nix
androidDevices.lib.mkSystem {
  device = "aurora";
  buildSystem = "aarch64-linux"; # or "x86_64-linux"
  nixpkgsConfig.allowUnfree = true; # OEM GPU/OEM firmware
  modules = [ {
    hardware.aurora.firmwareVariant = "android14";
    androidDevices.recovery.enable = true;
    androidDevices.initrdUsb = {
      enable = true;
      acm.enable = true;
      network.enable = true;
      address = "172.16.46.1/24";
    };
    boot.kernelParams = [ "clk_ignore_unused" "pd_ignore_unused" ];
  } ];
}
```

The repository example can be built with:

```sh
nix build .#devices.aurora.recovery --out-link result-recovery
```

The image selects Linux 7.3-rc6 with the Aurora patch queue, an appended board
DTB and a systemd initrd in an Android header-v0 container. Kernel and initrd
are self-contained. The
board DT enables USB OTG with a peripheral default and a 5-Gbit/s limit, using
the PM8550B eUSB2 repeater, QMP combo PHY and WCD9395 mux. Supplies, orientation
GPIO and fixed memory reservations are checked against the factory device tree.

## Experimental U-Boot

See [Android/U-Boot compatibility and A/B limits](../android-uboot-compatibility.md)
for the supported boot paths.

`nix build .#devices.aurora.u-boot --out-link result-u-boot`
builds the USB-console RAM firmware without changing the Linux recovery. ACM,
six UFS LUNs and read-only GPT/block access have been tested. See the
[firmware guide](../../pkgs/u-boot/sm8650/README.md) for prerequisites, automatic
reset behavior and limitations. Installed EFI-to-Linux handoff is verified.
Keep the independent recovery in `recovery_b` and use the checked
[installation workflow](../u-boot-install.md) for `boot_b`; preserve A.

## RAM boot prerequisites

Keep the stock A slot intact and use B for experiments. Back up device-specific
calibration/NV state and `dtbo_b` separately; confirm that factory images and
bootloader access are available. Stock DTBO contains downstream references
that the mainline DT does not provide. An already zero-filled `dtbo_b` needs
no write. After preparing the required factory base above, do not erase `dtbo_a` or
rerun factory flashing scripts for this RAM test.

Some bootloader versions (for example the Android 16 OS3.0.7.0.WNACNXM base)
also verify the active slot's physical AVB chain during `fastboot boot`. An
empty `boot_b` then causes an invalid AVB footer/header error and automatic
fallback to A before Linux runs, even after a successful download. Inspect the
OEM logs at `/dev/logfs/UefiLog*.txt` from stock Android when this happens. A
usable B-slot verification setup is a prerequisite; changing the RAM image alone
does not repair missing on-disk chain metadata. On an unlocked bootloader,
setting only `vbmeta_b`'s verification-disabled flag (2) passes authentication;
`vbmeta_system_a/b` can stay unchanged. Use the matching factory `vbmeta.img`
as the restore source and verify the written flags before another boot attempt.
The standard fastboot option is `--disable-verification` with `flash`; it is not
a standalone `disable-verify` command. Never omit the explicit `_b` partition.

ABL also rejects a zero OS version in this mode. The module supplies the stock
boot header's 14.0.0 / 2026-02-01 metadata through
`androidDevices.boot.android.osVersion` and `osPatchLevel`; this metadata
boots on the required Android 14 base. It is not the required ROM's security-patch date
or the Linux recovery's operating system version.
The DT exports symbols and an `arch_timer` label for the firmware's hypervisor
overlay, which can be applied even when `dtbo_b` is empty. Check the UEFI log
for overlay failures separately from Linux driver failures.

`fastboot boot` does not select a slot. Select B explicitly, verify the reported
slot, then boot the image using the intended device serial:

```sh
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL set_active b
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL boot result-recovery
```

The OEM bootloader's exact DTBO selection behavior is not established by these
commands. Preserve the image and boot logs when diagnosing failure. This image
provides the ACM console, USB NCM/SSH, UFS block devices and native N1 display.
The full recovery uses the Rust daemon, VT UI and interactive `recovery shell`.
The USB serial console has root privileges. Connect through `/dev/serial/by-id/` after enumeration.

The example also provides NCM Ethernet at `172.16.46.1/24`, with DHCP for the
host and SSH on port 22. ACM and NCM enumerate together; see
[connectivity](connectivity.md) for USB3 status and limits. The default recovery login is passwordless `root` over this
USB network. For key-only access, set
`androidDevices.initrdUsb.ssh.requirePublicKey = true` and provide
`androidDevices.initrdUsb.authorizedKeys`. Full recovery reuses or creates its
own host key on a verified clean Linux root, falling back to RAM when unavailable;
see [SSH identity and connection setup](../recovery.md#configure-and-connect).
Read `/run/mobile-recovery/ssh_host_ed25519_key.pub` through ACM to verify it
before connecting. No target remains mounted after identity preparation.

From the recovery shell, return to fastboot with
`recovery reboot-bootloader --confirm`. Select A on the host before a
normal Android reboot, provided no persistent recovery request is pending:

```sh
fastboot -s SERIAL set_active a
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL reboot
```

A previous `fastboot reboot recovery` can leave `boot-recovery` in the shared
BCB (`misc`). Selecting A does not clear that command and can boot stock recovery
instead of Android. Inspect the BCB before diagnosing this as a slot failure;
do not erase `misc`, which also contains other boot state. Stock recovery ADB can
return to the bootloader with `adb -s SERIAL reboot bootloader`.

## Install the independent recovery on B

After verifying a RAM boot with the prerequisites above, the same self-contained
image can be installed in `recovery_b`. Confirm product `aurora`, active slot B
and that the image fits the reported recovery partition (100 MiB on the
required factory base). Keep `recovery_a` and the rest of A intact:

```sh
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL getvar partition-size:recovery_b
fastboot -s SERIAL flash recovery_b result-recovery
fastboot -s SERIAL reboot recovery
```

Partition-backed recovery boot, image-length readback verification, ACM and NCM
are verified. The environment runs in RAM. SSH identity preparation may briefly mount the
verified Linux root; no target remains mounted afterward.
This does not provide a B-slot Android fallback or an installed Linux system.

## First partition, installation and updates (experimental)

The full recovery includes a [Rust daemon, UI and shell](../../pkgs/mobile-recovery-screen/daemon.md)
for first installation and offline `nixos-rebuild`. Its initrd has no Python
runtime or shell storage/install backend. Standard NixOS tools run from
the installed target closure and may use that closure's own Python dependency.
First partitioning, installation, incremental updates and installed EFI boot are
verified on hardware. The U-Boot artifact searches the outer GPT
`linux-boot` ESP for `EFI/BOOT/BOOTAA64.EFI` immediately after enabling ACM,
passes the relocated ABL device tree to EFI, and offers the maintenance menu if loading returns.

Build the example system and closure metadata with:

```sh
nix build .#devices.aurora.system --out-link result-system
nix build .#devices.aurora.boot-files --out-link result-boot-files
nix build .#devices.aurora.bootstrap-info --out-link result-bootstrap-info
```

From a healthy, independent B recovery:

```sh
recovery prepare-install --check
recovery prepare-install --confirm-erase-userdata
```

The second command **destroys Android userdata**. It retains approximately half
of the original userdata allocation for Android, and divides the other half into
an aligned 1 GiB FAT32 `linux-boot` ESP and ext4 `linux` root. It does not resize
F2FS or preserve Android apps, encryption keys or ADB authorization. It leaves
Android A, super, metadata, calibration and recovery unchanged. Android's
hardware-wrapped encrypted userdata requires a separate factory reset before
Android can be used again; creating an unencrypted F2FS filesystem here would
not initialize that encryption stack.

Preparation refuses an existing Linux layout, ambiguous partition labels,
mounted disks, active device-mapper holders, non-4-KiB UFS, GPT CRC errors or
inconsistent primary/backup copies. It writes the backup GPT first, preserves all
unrelated entries and disk bytes, and verifies both copies before formatting.
GPT evidence is retained in `/run/mobile-recovery/gpt-TASK_ID`; copy it to the host.
An interrupted GPT transaction requires explicit repair; never rerun blindly or
reboot on a write/readback error.

The slot gate validates a bootable B selection using Qualcomm GPT attributes
(active bit50, priority48–49, retry51–53, success54, unbootable55), with primary
and backup CRC/entry agreement. Conflicting cmdline/bootconfig suffixes are
rejected. This identifies the **configured next-boot slot**, not the slot that
loaded the current RAM image; it never invents a `slot_suffix` parameter.

After preparing storage, use the [shared first-install workflow](../initial-install.md)
with host name `aurora`. It verifies the closure and Nix database, installs and
checks the EFI generation, and writes `boot_b` firmware last. Keep recovery_b
independently bootable. Do not flash experimental firmware before a successful
RAM EFI/kernel handoff and software recovery-return test.

For later updates from recovery:

```sh
recovery mount-target --rw
recovery rebuild boot --flake /path/to/config#aurora
recovery unmount-target
recovery deploy-check-boot
recovery reboot-system --confirm
```

This reuses the installed Nix store and standard generation installer; `switch`
and `test` are refused inside recovery. Normal system updates change EFI files,
not Android boot firmware. Use `recovery generations` and `recovery select-generation NUMBER --confirm`
while mounted read-write for rollback.

Wi-Fi, Bluetooth, USB3 and DisplayPort status, including the per-device
Bluetooth identity setup, is listed in [connectivity](connectivity.md).

OEM GPU/OEM firmware is included by the module and also available as
`devices.aurora.firmware`; see its
[provenance and validation](firmware.md) and the
[connectivity preparation](connectivity.md) for remaining hardware dependencies.

## Boot menus and wired charging

Hold Volume Down at U-Boot takeover for its maintenance menu; normal boot has
no U-Boot countdown. Volume keys navigate and a short power press selects.
Systemd-boot additionally offers reboot, poweroff, OEM bootloader, recovery B
and Android A (with confirmation for special targets). Android selection is
persistent; use OEM fastboot to select B again when returning to NixOS.

A dedicated RAM-only wired charger is installed as
`/EFI/android-devices/charger.efi`. Exact ABL `androidboot.mode=charger` selects
it automatically; the U-Boot menu also has **Start wired charging**. It reads
battery/USB telemetry, blanks after 20 seconds, toggles display with a short
power press, and requests normal boot after a two-second hold. Confirmed cable
removal powers off after five seconds. Wireless charging is outside this board
configuration. No charging limits are written. Key navigation, off-mode entry,
display toggling and unplug behavior are not verified yet.

## Troubleshooting

### Keep B-slot boot display firmware intact

During initial B-slot preparation, explicitly flash `imagefv_b` from the required
factory package using the command below, then preserve it across NixOS updates.
Do not assume that a working Android A proves this B partition is populated.
It is part of the OEM boot display path, even when `boot_b` contains U-Boot. An empty `imagefv_b` can
leave both OEM fastboot and U-Boot/EFI physically black while USB and framebuffer
rendering still work. Android A can display normally in the same condition;
compare the slot used by the boot firmware, not only the previously running OS.

If this symptom occurs, inspect the factory UEFI logs (available under
`/dev/logfs` in rooted Android). The confirmed failure reports
`pil-imagefv Failed to load metadata` and a zero-length `logo.img`.
For an existing installation, check `imagefv_b` against the factory image before
changing panel shutdown, virtual terminals, or reset mode. Restore only the affected B partition from
**OS1.0.3.0.UNACNXM**, without running the full factory flashing script:

```sh
fastboot -s SERIAL flash imagefv_b /path/to/aurora_images_OS1.0.3.0.UNACNXM_14.0/images/imagefv.elf
fastboot -s SERIAL set_active b
fastboot -s SERIAL reboot bootloader
```

The matching `imagefv.elf` is 6,299,448 bytes, SHA-256
`96d1f21d8c2802c6144832ab9117e6fd4bf9df01647298befb2449090e577d00`.
Verify the B-slot fastboot display and then a Linux-to-bootloader round trip.
This targeted repair does not require erasing `misc` or modifying Android A.

## Hardware references

See [hardware support, validation limits and driver implementation](hardware.md),
[firmware sources](firmware.md), [connectivity and device identity](connectivity.md),
and [audio and calibration](audio.md).
