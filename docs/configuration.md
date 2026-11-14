# Configure your own system

Device-specific settings use `hardware.<device>.*` for `asphalt`, `polaris`, `sheng`, `aurora`, `clover`, `marble`, `t880`, `dodge` and `unicorn`.
Shared boot, USB and recovery settings use `androidDevices.*`.

[中文](configuration.zh.md) · [Installation guides](README.md) · [USB access](usb-signaller.md)

Use a Linux computer with Nix flakes enabled. Choose `x86_64-linux` or
`aarch64-linux` for the **build computer**; all supported devices run AArch64. An
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
2. Optionally set `androidDevices.usbSerial`. Each model defaults to one fixed
   name (`POLARIS`, `ASPHALT`, …; `RECOVERY_POLARIS`, … in RAM recovery); override
   it only to tell several units of one model apart.
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
configuration. Device names are `asphalt`, `polaris`, `sheng`, `aurora`, `clover`, `marble`, `t880`, `dodge` and `unicorn`.
`modules` holds your ordinary NixOS modules; optional `specialArgs`, `overlays`,
and `nixpkgsConfig` configure arguments and packages.

| Setting supplied by the device module | Asphalt | Polaris | Sheng | Aurora | Clover LTE |
| --- | --- | --- | --- | --- | --- |
| Installed boot | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI |
| Root GPT partition | `linux` | `userdata` | `linux` | `linux` | `userdata` |
| Default ext4 label | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` |
| USB NCM address, if selected | `172.16.43.1/24` | `172.16.42.1/24` | `172.16.45.1/24` | `172.16.46.1/24` | `172.16.44.1/24` |

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
```

Use `asphalt`, `sheng`, `aurora`, `clover`, `marble`, `t880`, `dodge` or `unicorn` in place of `polaris` for the other boards.
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
The `demo` account uses UID 1001, leaving UID 1000 available for a personal
account on a fresh installation. Existing account IDs and file ownership need
separate review when changing from an older example installation.
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

## Suspend wakeup sources

Device modules may declare named wakeup sources in
`androidDevices.power.wakeup.sources` (each a list of sysfs device paths); see
the device's hardware notes for its names and verified wake behavior. The policy
is off by default. To use it, enable it and list the sources to keep:

```nix
androidDevices.power.wakeup = {
  enable = true;
  keep = [ "powerKey" ];
};
```

Every other device wakeup (`power/wakeup`) is then disabled at boot, when a
device appears or binds, and again right before each system sleep; kept sources
keep the setting their driver chose. Check the result with
`grep -l enabled $(find /sys/devices -path '*/power/wakeup')` and the
`android-devices-wakeup-policy` service log. Whether and when the system
suspends (systemd sleep settings, idle daemons, menus) remains your own
configuration.

## Speaker routing for screen orientation

Applications send left and right channels to the speaker sink, and the sink
always plays them on the same physical speakers. After a rotation, left and
right can come from the wrong edges. Device modules with several speakers may
describe, per output transform, the ALSA mixer settings that keep left and
right on the matching edges in
`androidDevices.audio.orientation.routes.{normal,"90","180","270"}`. The policy
is off by default:

```nix
androidDevices.audio.orientation.enable = true;
```

This installs `/etc/android-audio-orientation.json`, the
`android-audio-orientation` command and the `android-audio-orientation` user
service. Your compositor integration triggers the change: call the command
from your rotation handler with the new output transform, as the desktop user:

```sh
android-audio-orientation apply 90
android-audio-orientation status
```

`apply` sets only the listed controls, after checking that each exists, and
records the orientation in `$XDG_RUNTIME_DIR`. Activating the audio profile
rewrites the controls, so the user service reapplies the recorded orientation
(`normal` if none) whenever WirePlumber starts or restarts. Flipped transforms
mirror the image and are rejected; no routing applies to them. An orientation
without data leaves the routing unchanged. See the device's hardware notes for
which orientations are verified.

## System clock from a read-only RTC

Some PMIC RTCs keep counting while the phone is off but cannot be set from
Linux, so every boot starts the clock at the RTC's raw count (for example
1970-01-10). Device modules for such boards enable
`androidDevices.clock.rtcOffset` (Aurora, Clover and Polaris; installed system
only), which keeps a userspace offset as Android's time daemon does:

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Restore the clock from RTC + saved offset at boot and save the offset. |
| `rtc` | `"rtc0"` | RTC class device (`/sys/class/rtc/<rtc>`). |

`rtc-offset-restore.service` runs before `time-set.target` and
systemd-timesyncd. It sets the clock to the RTC count plus the saved offset,
only forward, and creates `/run/rtc-offset/restored`. A saved RTC count above
the current one means the RTC was reset; the saved offset is then discarded and
the clock waits for NTP. Results before 2026-01-01 are rejected. The offset
(`/var/lib/rtc-offset/offset`: RTC seconds and offset seconds) is saved after
each systemd-timesyncd synchronisation (`rtc-offset-save.path`) and at shutdown
(`rtc-offset-shutdown.service`), only when the clock was synchronised or
restored during that boot. The first boot after installation or an RTC reset
still needs NTP once. Check with
`journalctl -b -u rtc-offset-restore -u rtc-offset-save -u rtc-offset-shutdown`.

Do not enable it for an RTC that Linux can set (`allow-set-time` or an
`offset` nvmem cell in its device tree node); the kernel then keeps the time
itself.

## Real-time task frequency clamp

`androidDevices.power.rtUtilClampMin` (default `0`) sets
`kernel.sched_util_clamp_min_rt_default` in the installed system. The kernel
default (1024) runs every real-time wakeup, such as a threaded touch interrupt,
at the highest CPU frequency, and through CPU bandwidth votes also raises the
DDR frequency while the device is idle. Pixel device init files use 0. Set it to
`null` to keep the kernel default.

## Thermal charge current cap

Some charger firmware leaves thermal charge limiting to the operating system,
as Android's thermal daemons do. `androidDevices.charging.thermalLimit`
writes a charge current cap that follows temperature. Device modules provide
the inputs; Aurora sets steps from its stock thermal configuration, with
the battery temperature as the sensor. The service is disabled by default:

| Option | Meaning |
| --- | --- |
| `enable` | Run `charge-thermal-limit.service` (default `false`). |
| `currentFile` | Writable cap in µA, for example `constant_charge_current`. |
| `sensors` | Temperature files with a factor to m°C; the highest reading controls the cap. |
| `steps` | `{ trip; clear; current; }` with ascending trips in m°C and caps in µA. |
| `defaultCurrent` | Cap below the first step and after the service stops. |
| `interval`, `refreshPolls` | Poll period (5 s) and rewrite period of an unchanged cap (12 polls). |

A step applies from its trip temperature until the temperature falls below its
clear temperature. Without a readable sensor the last (lowest) cap applies.

## Battery care charge window

`androidDevices.charging.window` keeps the battery partly charged while the
device is plugged in: charging stops at the end threshold and resumes below
the start threshold, and the device runs from the charger meanwhile. It uses
the battery's standard `charge_control_start_threshold` and
`charge_control_end_threshold`, which the charger driver enforces. It is off by
default; the T880 module supplies its battery path and a 75/80 % example:

| Option | Meaning |
| --- | --- |
| `enable` | Run `charge-window.service`. |
| `battery` | power_supply directory of the battery. |
| `startThreshold`, `endThreshold` | Resume below / stop at these levels (default 75 and 80 %). |
| `requestGroup` | Group that may request a one-off full charge (default `users`). |

For a full charge (before travel), create `/run/charge-window/full-charge`
(`nexusctl battery full-charge` in the example session). The window is lifted
until the charger reports the battery full or is unplugged, then returns.
`/run/charge-window/state` reads `window START END`, `full-charge` or `off`.
Stopping the service turns the window off (0/100 %).
Check with `journalctl -b -u charge-thermal-limit`, and compare `current_now`
with the cap while charging before relying on it.

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
| Two units of one model share a USB serial and MAC | Set a distinct `androidDevices.usbSerial` for each unit |
| Missing rootfs UUID on another device | Set `androidDevices.persistentImage.rootfs.uuid` before building its optional image |
| No desktop after boot | Device modules do not start one; configure and launch your chosen desktop |
| USB exists but SSH fails | Check host DHCP/address, your public key, and `journalctl -u sshd -u usb-signaller`; see [USB troubleshooting](usb-signaller.md) |
| Storage contract rejected | Re-read the actual device layout and follow its first-install guide; build a matching recovery |
