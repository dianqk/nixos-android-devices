# T880 first installation

[中文](install.zh.md) · [T880 guide](README.md)

This guide prepares an Alldocube iPlay 80 mini Ultra (T880) for NixOS on slot A
while Android stays on slot B. It is experimental. Partitioning **erases
Android userdata**; keep your own backup of anything you need.

Requirements: an unlocked bootloader, Android working on slot B, `fastboot`
and `adb` on the host, and this repository's `mobile-device` tool
(`nix run .#mobile-device -- …`). Build the images:

```sh
nix build .#devices.t880.u-boot --out-link t880-u-boot.img
nix build .#devices.t880.recovery.payload --out-link t880-recovery.itb
```

The U-Boot image fills the 64 MiB `boot_a` partition with an AVB hash footer;
the stock LK needs that footer. The recovery FIT is at most 128 MiB.

## 1. U-Boot on slot A

From Android: `adb reboot bootloader`. In LK fastboot (product
`p5n1_kb_t880_8883_b0`):

```sh
fastboot getvar product
fastboot flash boot_a t880-u-boot.img
fastboot set_active a
fastboot reboot
```

U-Boot appears as a USB fastboot device with the tablet's serial number. If no
USB host connects within 90 seconds, U-Boot lets the watchdog reset the
tablet; after a few attempts LK returns to Android on slot B.

## 2. Start the recovery from RAM

Set `SERIAL` to the verified U-Boot USB fastboot serial. Transfer the raw FIT
without an Android boot-image wrapper:

```sh
fastboot -s "$SERIAL" stage t880-recovery.itb
fastboot -s "$SERIAL" oem 'run:bootm ${fastboot_addr_r}'
```

Host `fastboot boot` may wrap a raw FIT in an Android header; use `stage` here.
The OEM command uses a colon after `run`. USB disconnects when U-Boot jumps,
so the final command may report a status-read disconnect.

The recovery shows its menu on the screen and offers USB networking:
`ssh root@172.16.47.1` (the `mobile-device recovery --target` below uses the
same address).

## 3. Split userdata

Check first. Without a size this lists the Android userdata sizes on offer
(32/64/128/256/512 GiB, those that leave `linux-boot` and `linux` at least 64 GiB;
see [recovery](../recovery.md#ab-devices-preparing-linux-storage)); with a size
it prints the planned table. Neither changes anything:

```sh
mobile-device recovery --target root@172.16.47.1 prepare-install
mobile-device recovery --target root@172.16.47.1 prepare-install --android-userdata 64G
```

The plan only touches the userdata span: Android `userdata` keeps the chosen
size, followed by `linux-boot` (FAT, 1 GiB) and `linux` (ext4, the rest).
The GPT grows from 82 to 84 entries; every other
entry is unchanged. When the table is right:

```sh
mobile-device recovery --target root@172.16.47.1 prepare-install \
  --android-userdata 64G --gpt-backup ./t880-gpt-original --execute
```

This downloads the original GPT (both copies) to `./t880-gpt-original` first,
then partitions. The recovery writes the backup GPT copy before the primary
and verifies each, restoring the original automatically if a step fails. The
new Android userdata is left unformatted (its first 8 MiB are zeroed); the
`metadata` partition is not touched.

## 4. Re-initialise Android on slot B

Android formats its smaller userdata with its own recovery:

1. In the NixOS recovery menu choose "Enter fastboot" (or run `mobile-device
   recovery --target root@172.16.47.1 reboot bootloader --execute`).
2. `fastboot set_active b`, then `fastboot reboot recovery`.
3. Choose "Wipe data/factory reset", then reboot to Android.

To return to NixOS later: `adb reboot bootloader`, then `fastboot set_active a`
and `fastboot reboot`.

## 5. Install NixOS

Boot the recovery again if needed (from Android: `adb reboot bootloader`,
`fastboot set_active a`, `fastboot reboot`; U-Boot waits in USB fastboot
while `linux-boot` is empty, then use the raw FIT staging commands in step 2). Build the system and its closure
information, check, then install:

```sh
nix build .#devices.t880.system --out-link t880-system
nix build .#devices.t880.bootstrap-info --out-link t880-bootstrap-info
mobile-device recovery --target root@172.16.47.1 install-initial \
  ./t880-system --bootstrap-info ./t880-bootstrap-info
mobile-device recovery --target root@172.16.47.1 install-initial \
  ./t880-system --bootstrap-info ./t880-bootstrap-info --execute
mobile-device recovery --target root@172.16.47.1 reboot system --execute
```

This streams the closure to the empty ext4 `linux`, installs systemd-boot and
verifies the generation in `linux-boot`. U-Boot installed in step 1 then loads
systemd-boot from
`linux-boot` and marks slot A successful in misc, so LK stops counting down
its retries. Later updates use the usual NixOS generations; earlier
generations stay selectable in the systemd-boot menu.

The recovery is reached from Linux with `systemctl reboot
--reboot-argument=recovery`, from U-Boot fastboot with `fastboot reboot
recovery`, or from the U-Boot menu (hold Volume Down).

## Undo the partitioning

Boot the recovery (steps 1–2) and write the saved GPT back:

```sh
mobile-device recovery --target root@172.16.47.1 restore-gpt \
  --gpt-backup ./t880-gpt-original --execute
```

Then wipe data from the stock recovery on slot B (step 4).

## If something goes wrong

- Before rebooting, the recovery session can restore the saved GPT itself.
- LK fastboot (from U-Boot with `fastboot reboot-bootloader`, from Linux with
  `reboot bootloader`, from Android with `adb reboot bootloader`) can always
  reflash `boot_a` or select slot B.
- The preloader and LK read the primary GPT and fall back to the backup copy;
  the recovery keeps one valid copy at every step of its write.
