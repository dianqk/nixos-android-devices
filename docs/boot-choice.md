# Dodge same-slot boot choice

[中文](boot-choice.zh.md)

Dodge can keep Android and NixOS in one Android slot and choose the next boot
target without switching A/B slots. This is an experimental, host-validated
feature; it is not a general Android ROM installer or a replacement for
independent RAM recovery.

## Components

- `boot-selector-builder`: host producer for the guarded early selector.
- `boot-choice-native`: static AArch64 Linux `boot-choice` owner CLI.
- `boot-choice-template`: baseline-independent Dodge template with matching
  U-Boot raw/ELF/config and EFI helper.
- `boot-choice-efi`: freestanding UEFI helper used by the NixOS module.
- `boot-choice-kernelsu`: self-contained KernelSU Manager ZIP.

Build from this checkout:

```sh
nix build "git+file://$PWD#boot-selector-builder" --out-link result-builder
nix build "git+file://$PWD#boot-choice-native" --out-link result-native
nix build "git+file://$PWD#boot-choice-template" --out-link result-template
nix build "git+file://$PWD#boot-choice-kernelsu" --out-link result-kernelsu
```

The KernelSU ZIP is `result-kernelsu/dodge-boot-choice-kernelsu.zip`. Its module
contains the native owner, template, matching firmware/helper and hashes; it
does not contain an Android boot image, APK, Python, Nix or compiler.

## Requirements

- Keep working Android, independent RAM recovery and rollback assets.
- Install or patch KernelSU into the supported current Android kernel first;
  this module does not install KernelSU.
- The booted slot must use supported kernel-only BOOT4: no boot ramdisk or boot
  signature, uncompressed MZ ARM64 Image, bounded AVB framing and the original
  kernel footprint within 48 MiB. Other layouts are refused.
- On current KernelSU, a mounting metamodule such as meta-overlayfs is needed
  for `system/bin/boot-choice` to appear in Android PATH. The Manager WebUI and
  native operation do not depend on that overlay.

## KernelSU install and use

1. Copy the ZIP to Android and install it in KernelSU Manager. The standard
   installer extracts files and runs `customize.sh`; no recovery `META-INF`
   installer is supplied.
2. The module copies template assets into a private temporary directory under
   `/data/adb` and invokes the native owner once. Copy/protection failure stops
   before image writes; cleanup failure after a verified commit is reported, not
   hidden as rollback.
3. Read the native output. `install TEMPLATE` adopts the actual fresh booted
   baseline or validates/updates an owned image. Changed images preserve the
   preference and increment the sequence; identical content is a no-op.
4. Manager stages updates for the next Android boot. Opening the module WebUI is
   read-only. The explicit **切换到 NixOS / 切换到 Android** buttons call
   `boot-choice reboot TARGET` once per click; they lock while busy and show
   native errors without automatic retry.
5. The module `action.sh` is read-only status. Entry, refresh, URL parameters and
   startup never choose a target or request a reset.

With an Android system overlay:

```sh
su -c 'boot-choice status'
su -c 'boot-choice reboot nixos'
```

Without an overlay, use the module's `bin/boot-choice` directly. In NixOS with
`hardware.dodge.bootChoice.enable = true`:

```sh
sudo boot-choice status
sudo boot-choice reboot android
```

## Native template workflow

Runtime packing needs no Python, Nix or compiler:

```sh
result-native/bin/boot-choice image embed "$(realpath result-template)" \
  fresh-baseline.img embedded.img
result-native/bin/boot-choice image update "$(realpath result-template)" \
  previous-owned.img updated.img
result-native/bin/boot-choice image restore embedded.img original.img
```

Inputs and outputs are bounded ordinary files, never block devices. Output
creation is exclusive, mode 0600, synchronized and read back. Existing outputs
are not overwritten. File packing does not grant live device write authority;
use the native live commands for device writes.

## Safety limits

- Host builds and tests do not prove hardware, EFI runtime or power-loss
  acceptance.
- Full-image writes are not power-loss atomic before OEM AVB/EFI. Keep the
  original image and independent recovery.
- The early volume-key picker is read-only and applies only to the current boot.
- Persistent preference comes from explicit CLI/WebUI actions, not from menu
  browsing, boot arguments or module startup.
- `hardware.dodge.bootChoice.enable` is opt-in and requires matched firmware,
  helper and a separate deployment trial.

See [Dodge firmware](dodge/firmware.md), [recovery](recovery.md) and
[boot actions](boot-actions.md) for the surrounding deployment contracts.
