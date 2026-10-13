# Configure your own system

Device-specific settings use `hardware.{asphalt,polaris,sheng,aurora,clover}.*`.
Shared boot, USB and recovery settings use `androidDevices.*`.

[中文](configuration.zh.md) · [Installation guides](README.md) · [USB access](usb-signaller.md)

Use a Linux computer with Nix flakes enabled. Choose `x86_64-linux` or
`aarch64-linux` for the **build computer**; all five devices run AArch64. An
x86_64 build uses the cross toolchain for this repository's compiled device
packages. Upstream system packages remain native AArch64 so their binary caches
can be reused.

## Build platforms and remote builders

| Work | AArch64 build computer | x86_64 build computer |
| --- | --- | --- |
| Repository kernels, U-Boot and patched/compiled programs | Native compilation | Cross compilation |
| Ordinary upstream system packages | Native cache, then local build | Same ARM native cache, then local QEMU build |
| Project firmware, scripts, prebuilt binaries, initrd/boot/rootfs images | Local packaging | Local packaging with x86_64 tools |
| Generated upstream NixOS configuration | Local ARM build | Local QEMU build |
| Fastboot and kernel development tools | Run on the initiating computer | Run on the initiating computer |

Both build platforms can complete a system without another ARM computer. On an
x86_64 **NixOS build host**, enable the standard emulator support and activate
that host configuration before building:

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
nix.settings.builders-use-substitutes = false;
```

This registers QEMU and advertises `aarch64-linux` to Nix, including sandbox
support. Configure this on the build computer, not in the phone's modules.
Other Linux distributions need an AArch64 binfmt interpreter usable inside
Nix's sandbox and `extra-platforms = aarch64-linux` in the daemon configuration;
setting `extra-platforms` alone does not install an emulator.

```sh
nix build .#system --option builders-use-substitutes false \
  --out-link result-system
```

Nix substitutes available native ARM packages first; uncached upstream jobs and
generated NixOS configuration can execute through QEMU. Those jobs may be slow.
Project packaging executes host tools without emulating the packaged programs;
its input closure can still contain ARM jobs needing emulation. Device scripts
retain ARM interpreters and runtime dependencies. Compiled project packages use
the selected toolchain; native and cross compiler outputs need not share caches.

A remote builder remains optional. `builders-use-substitutes = false` keeps
binary-cache downloads on the initiating host, which transfers inputs to any
configured remote builder. Do not clear `extra-platforms` when using local QEMU.

The distinction between image assembly tools and target contents also appears in
[nix.dev's image example](https://nix.dev/tutorials/nixos/building-and-running-docker-images.html).
The [NixOS binfmt module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/binfmt.nix)
manages emulator registration and Nix platform/sandbox settings together.

## Start with a consumer flake

Copy [this complete flake](../examples/consumer/flake.nix) into a new configuration
directory as `flake.nix`. It uses only exported modules and library functions;
there is no dependency on an `examples/` path in the upstream input.

Before building for installation, edit these values:

1. Set `buildSystem` to your computer's architecture.
2. Set `androidDevices.usbSerial` to a unique, stable identifier for this device.
3. Add your SSH public key to `users.users.root.openssh.authorizedKeys.keys`.
   Without a key, the default console system has no configured login credential.
4. For Polaris, inspect the [stock GPT partition names](polaris/first-install.md#identify-this-phone).
   Recovery resolves them on the built-in UFS and checks the root filesystem
   label. An exact per-phone storage contract is optional.
5. Keep the initial `system.stateVersion` when updating the configuration later.

Track the files in Git before using Nix:

```sh
git init
git add flake.nix
nix flake lock
nix eval .#nixosConfigurations.phone.config.system.build.toplevel.drvPath
nix build .#system -o result-system
nix build .#boot -o result-boot
nix build .#boot-files -o result-boot-files
nix build .#bootstrap-info -o result-bootstrap-info
nix build .#recovery -o result-recovery
```

These commands only build files. The guides name output links `result-<role>`;
any path works if you use it consistently. Follow the device's [first-install guide](README.md)
to prepare storage and install them. Build firmware/boot files only when the guide
requires them. Keep system, bootstrap-info and boot-files from the same locked flake.

## Supplemental direct-kernel image (Sheng and Clover)

U-Boot remains the default: `boot` and `u-boot` still produce U-Boot firmware.
For an existing installation, `boot-kernel` additionally packages Linux, a
matching direct-boot initrd and the board DTB as an Android boot image:

```sh
nix build .#devices.sheng.boot-kernel --out-link result-boot-kernel
# For Clover, replace sheng with clover; build only the device you need.
```

These are repository examples. For your own configuration, `lib.mkArtifacts`
exports `boot-kernel` for Sheng/Clover, backed by
`config.system.build.mobileDirectBootImage`. Build it with the same locked
configuration as `system` and `bootstrap-info`. It targets that exact system
closure, not whichever generation the system profile selects later. Install
and retain that complete closure on the existing ext4 root before booting;
keep a GC root for it while keeping the fallback image. Building the image
alone does not deploy the system or register a GC root on the device.

The image requires the configured ext4 root and FAT `/boot`. Its initrd selects
the matching system closure and refuses an incomplete deployment.

The image replaces U-Boot only if you explicitly install it to the device's
boot partition (Sheng: `boot_b`, preserve A; Clover: `boot`, no slots). It does
not write rootfs, EFI files or recovery. Validate a RAM boot first where
supported. Use the checked `mobile-device fastboot` workflow for Clover;
if image/target validation refuses it, investigate rather than bypassing it.
No flashing is performed by the build command.

`nixos-rebuild boot` continues to maintain EFI generations, not the flashed
fallback image. Rebuild and deploy `boot-kernel` separately to update this
fixed-generation fallback. Restoring the matching `u-boot` artifact restores
EFI menu booting. Direct-kernel boot remains unverified on both devices.

## Choose a device and role

`lib.mkSystem { device; buildSystem; modules; }` returns a normal NixOS system
configuration. Device names are `asphalt`, `polaris`, `sheng`, `aurora` and `clover`.
`modules` holds your ordinary NixOS modules; optional `specialArgs`, `overlays`,
and `nixpkgsConfig` configure arguments and packages.

| Setting supplied by the device module | Asphalt | Polaris | Sheng | Aurora | Clover LTE |
| --- | --- | --- | --- | --- | --- |
| Installed boot | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI |
| Root GPT partition | `linux` | `userdata` | `linux` | `linux` | `userdata` |
| Default ext4 label | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` |
| USB NCM address, if selected | `172.16.43.1/24` | `172.16.42.1/24` | `172.16.45.1/24` | `172.16.42.1/24` (shared default) | `172.16.44.1/24` |

All devices default to the ext4 label `NIXOS`. For an existing installation,
keep its configured label and recovery storage contract consistent; changing
this default does not relabel the filesystem.

`androidDevices.persistentImage.rootfs.label` is the single filesystem-label
setting (default `NIXOS`) for the image, formatter and recovery. GPT names such
as `linux` and `userdata` are separate from this ext4 label.

For Asphalt/Sheng, share `androidDevices.boot.uefi.espSizeBytes` between system
and recovery. It defaults to 1073741824 (1 GiB); set another measured byte size,
or `null` to accept an existing ESP's size while retaining free-space checks.
`androidDevices.recovery.minimumRootBytes` defaults to 17179869184 (16 GiB)
and can be adjusted for a smaller closure. Recovery validates unique GPT roles,
controller, types, bounds and non-overlap without fixing Linux partition numbers
or the order of root and ESP. Stock-layout planners still protect their recognized
Android prefix; custom layouts require manual preparation against the actual GPT.

Device modules supply hardware, persistent-system defaults and recovery tools.
They do not create a demo user or select a desktop. Supply your own USB serial.
To use the sample flake for another board, change `device`, remove the two
`hardware.polaris.*.enable` lines, and configure that board's storage identities.
USB NCM is enabled by default in installed systems. Enable
`androidDevices.usb.ssh.enable` and configure your SSH keys for remote access.
System ACM is optional (`androidDevices.usb.acm.enable = true`); repository
examples enable it explicitly. U-Boot uses ACM; RAM recovery directly configures
ACM+NCM in its initrd without usb-signaller. The normal boot initrd has USB
management off by default, then usb-signaller starts in stage 2.
All installed configurations use EFI; prepare and validate the FAT `/boot` before installation.

Set `androidDevices.recovery.enable = true` in a **separate** system to obtain RAM
recovery. Share only hardware/storage identities between installed and recovery
configurations. Do not import your desktop, user services or installed USB SSH
policy into recovery. Recovery uses [ACM/NCM and OpenSSH](recovery.md) and does not start the installed system.
`hardware.<device>.systemHostName` sets the installed hostname expected by recovery;
set the same value in both configurations when renaming a device.

Advanced consumers can import `nixosModules.<device>` directly with
`lib.mkBuildEnvironment { buildSystem; overlays; config; }.nixosSystem`.
Each device module imports and enables both common Android-device support and
its board-specific support. For example:

```nix
imports = [ inputs.androidDevices.nixosModules.polaris ];
androidDevices.usbSerial = "my-polaris-01";
```

Use `asphalt`, `sheng`, `aurora` or `clover` in place of `polaris` for the other boards.
No separate common-module import or `androidDevices.enable = true` is needed.
Device modules do not select a desktop or supply device identities.

## Add a desktop or services

Desktop environments, users, authentication and generic system profiles use
ordinary NixOS configuration. The public device modules do not export desktop policy or
a general-purpose minimal-system profile. The consumer sample imports Nixpkgs'
`profiles/minimal.nix` directly; you can omit it or add services normally.

For Niri/Foot, add your own module to the installed system, for example:

```nix
{
  users.users.alice = {
    isNormalUser = true;
    initialPassword = "change-before-use"; # Or use hashedPasswordFile.
    extraGroups = [ "video" "input" "render" ];
  };
  programs.niri.enable = true;
  programs.foot.enable = true;
}
```

Log in on a local tty and run `niri-session`. Configure Niri's outputs,
keybindings, terminal and startup in your own configuration. The
[desktop example](../examples/desktop.nix) demonstrates a full session, including
explicit demo-user autologin and an always-visible wvkbd keyboard at the bottom
with reserved screen space. Copy and adapt the parts you want rather than
importing it as an upstream interface. The example uses `/etc/niri/config.kdl`,
selected through `NIRI_CONFIG`, and starts `niri-session` from the demo tty1 login.
`example.desktop.scale` sets the internal display scale in these example files;
it is not an exported hardware-module option.
Niri uses its default screen orientation: the examples add no output transform,
rotation metadata override or automatic rotation client. Sensor support remains
available for diagnostics and an explicitly configured rotation policy.
The touchscreen is mapped to `DSI-1`. Windows use full-width columns without gaps,
leaving wvkbd's reserved area visible. Super+Return opens a terminal, Super+Left/Right
changes columns, Super+Up/Down changes workspaces, Super+O opens the overview,
Super+Q closes a window, and Super+Shift+E exits the session. Print takes a screenshot;
for a specific path use `niri msg action screenshot-screen --path /tmp/screen.png`.
Other compositors use their normal NixOS
modules as well. Panel rotation/scale and UI preferences belong to that session.

On Polaris, `hardware.polaris.radio.enable` and `hardware.polaris.audio.enable`
default to `true`. The consumer console sample turns both off. To add Wi-Fi or
audio later, remove those overrides; configure the [radio identities](polaris/README.md)
and enable NetworkManager/PipeWire as needed. No internal module must be disabled
or re-imported. Audio and radio share the DSP service mapper where needed.
Other boards retain their device-specific hardware defaults; see their option
and hardware notes before enabling optional sensors or fingerprint services.

Media applications use upstream FFmpeg by default, including Polaris/Asphalt.
`androidDevices.video.ffmpegPackage` remains overridable; the
[restricted local H.264/HEVC profile](video.md) and device V4L2 fixes are opt-in
for diagnostics or specialized local-media builds.
Normal NixOS configuration still controls Bluetooth, PipeWire, Wi-Fi credentials,
users, packages and application services.

For camera tools, set `environment.systemPackages = [ config.androidDevices.camera.package ];`
in a module accepting `config`. This selects libcamera with the mobile sensor
adaptations. Use `cam --list` to enumerate cameras; consult the board hardware
reference for capture commands and limitations.

## Select artifacts

`lib.mkArtifacts configuration` provides these derivations:

| Attribute | Use |
| --- | --- |
| `system` | Installed NixOS closure; also `config.system.build.toplevel` |
| `bootstrap-info` | Registration/closure metadata matching that system |
| `boot` | Android boot image: U-Boot for installed EFI, Linux for RAM recovery |
| `kernel` | Device kernel package |
| `rootfs` | Optional ext4 image for persistent systems; Polaris defaults its image UUID from `androidDevices.usbSerial`, unrelated to recovery first installation |
| `boot-files` | Initial EFI file tree; available for every installed system |

The rootfs image grows within its existing partition. It is not a disk image and
contains no GPT. Rootfs `name`, `label`, `padding`, `device` and `maximumBytes`
can be customized. Building only `system` and `bootstrap-info` does not require
creating a rootfs image. The Polaris first installer consumes the system
closure and metadata; do not substitute a rootfs image for those inputs.

## Update, recover and troubleshoot

After a successful first installation, an EFI system with USB SSH can be updated
from the build computer:

```sh
nixos-rebuild boot --flake .#phone --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

Check `readlink /run/current-system` and the services you changed after reboot.
Use `boot` when changing USB/SSH so activation does not interrupt its own transfer.
For a failed boot, use the device's RAM recovery and the
[`mobile-device` deployment guide](../pkgs/mobile-device/README.md).

| Symptom | Check or next action |
| --- | --- |
| Unknown `androidDevices.*` option | Import the device module or use `mkSystem`; update the locked input if the option was added recently |
| Missing USB serial | Set `androidDevices.usbSerial` in shared device configuration |
| Missing rootfs UUID on another device | Set `androidDevices.persistentImage.rootfs.uuid` before building its optional image |
| No desktop after boot | Device modules do not start one; configure and launch your chosen desktop |
| USB exists but SSH fails | Check host DHCP/address, your public key, and `journalctl -u sshd -u usb-signaller`; see [USB troubleshooting](usb-signaller.md) |
| Storage contract rejected | Re-read the actual device layout and follow its first-install guide; build a matching recovery |
