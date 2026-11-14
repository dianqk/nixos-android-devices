# Xiaomi 12S Pro (unicorn)

[中文](README.zh.md) · [All devices](../README.md) · [Support status](status.md)

Unicorn uses U-Boot → systemd-boot → Linux, with a separate RAM recovery.
The kernel follows the repository's locked Linux 7.3.4. Unicorn has a separate
SM8475 patch queue; the existing Asphalt queue is unchanged. Hardware results
below were recorded on 7.3-rc6; the rebase requires renewed hardware acceptance.

## Configure and build

Select `device = "unicorn"` in `lib.mkSystem`, or import `nixosModules.unicorn`.
See the [configuration guide](../configuration.md) for a consumer flake.
The repository console example enables USB NCM at `172.16.47.1`, ACM login,
root SSH with an empty password and NetworkManager.
Set your own credentials and USB identity before personal deployment.
[USB2 modes](usb.md) cover OTG, MTP and tethering.
[Additional USB modes](usb-gadgets.md) cover HIDRAW, native touch, image-backed storage and UVC.

```sh
nix build .#devices.unicorn.kernel
nix build .#devices.unicorn.u-boot
nix build .#devices.unicorn.recovery
nix build .#devices.unicorn.system
nix build .#devices.unicorn.boot-files
nix build .#devices.unicorn.bootstrap-info
```

The [kernel guide](../../pkgs/linux-kernel/sm8475/unicorn/PATCHES.md) describes
patches and configuration. [Firmware inputs](../../pkgs/unicorn/README.md) are
hash-checked and marked unfree; private identity and calibration stay on-device.

## Storage and installation

This port uses the entire original userdata extent: a 1 GiB FAT32 ESP named
`linux-boot`, followed by an ext4 root named `linux`. Preparing this layout
erases all Android userdata. Other partition boundaries, including A, super,
firmware and calibration, are preserved. The Android EFI boot action is disabled.
U-Boot occupies `boot_b`; independent project recovery occupies `recovery_b`.

From matching RAM recovery on active slot B, inspect and then prepare storage:

```sh
recovery prepare-install --check
recovery prepare-install --confirm-erase-userdata
```

Preparation refuses an existing Linux layout. Install and independently verify
`recovery_b` before replacing the boot image. Follow the [first installer](../initial-install.md)
with matching `system` and `bootstrap-info` artifacts to install the closure,
EFI files and U-Boot. Subsequent system updates use the ESP and leave U-Boot
unchanged; rebuild and explicitly install U-Boot when its patches change.

## Hardware support

| Area | Current support and limits |
| --- | --- |
| Boot and storage | UFS boot, EFI generation updates, independent recovery and Linux-only layout verified; bounded file I/O and suspend/resume checks passed |
| Display and GPU | 1440×3200 DSC, A730 rendering and six fixed modes at 24/30/40/60/90/120 Hz verified; 60 Hz preferred |
| Touch and keys | FingerTipS multitouch; console volume keys, short power press for display off/on, long press for orderly shutdown |
| Wi-Fi | 2.4/5 GHz connection, transfer and reconnect verified; NetworkManager supplies a stable local address |
| Bluetooth | Pairing, headset playback and RFCOMM transfers verified with a separately provisioned factory address; intermittent firmware-download timeout remains possible; HFP and concurrent Wi-Fi/audio acceptance pending |
| Audio | Internal speakers and microphone recording/playback verified with private runtime inputs; USB-C digital and analogue accessories remain unverified; analogue routing is incomplete |
| Camera | JN1 ultra-wide/telephoto RAW10 capture verified on the previous kernel; front/main identification still NACKs. All four sensors have source implementations; the current kernel needs hardware verification. See [camera details](camera.md) |
| Fingerprint | Unsupported |
| Sensors and other peripherals | DSP, battery, NFC, haptics and infrared drivers included; dedicated SSC sensor data/services and full peripheral acceptance remain incomplete |

SoundWire resume, audio routing and display-off commit fixes are retained.
Analogue headset cross-connection/impedance messages remain a known limitation.
The table describes individual validated paths; new combinations still need
hardware verification.

## Private audio inputs

The module installs AudioReach topology by default. Enable the UCM speaker and
microphone paths after provisioning this handset's private runtime data:

```nix
hardware.unicorn.audioRuntime = {
  enable = true;
  inputDirectory = "/var/lib/unicorn-audio/private";
};
```

The directory must be root-owned, mode `0700`, on the root filesystem, without
symlink ancestors. It contains `cs35l41-dsp1-spk-prot.wmfw`,
`T-cs35l41-dsp1-spk-prot.bin`, `B-cs35l41-dsp1-spk-prot.bin`, `crus_calr.bin`
(8 bytes), `t-music.be32` (300 bytes), `b-music.be32` (64 bytes), and a
`manifest.json` with `format = "unicorn-speaker-runtime-v1"` and a `files`
object mapping those six names to `{ "bytes": ..., "sha256": "..." }`.
Files must be root-owned private regular files. Preparation verifies the inputs
and creates the driver firmware names under `/run/unicorn-audio`; private data
never enters the Nix store. The kernel retains amplifier readiness, calibration
and protection checks.

## Bluetooth identity

Set `hardware.unicorn.bluetoothIdentityFile` to an absolute device-side path
string such as `"/var/lib/mobile-identity/bluetooth-address"`. The root-owned
`0600` file contains this handset's verified factory public Bluetooth address
in colon-separated display order. The service validates and reads it back before
starting BlueZ. The default is `null`; recovery does not provision identities.
Do not infer the Bluetooth address from Wi-Fi or copy another handset's address.

## Optional display and console settings

`hardware.unicorn.display.seamless.enable` defaults to `false`. Its default
allowlist is `[ 60 120 ]`; 60↔120 Hz active switching passed repeated hardware
checks at three brightness levels. Other active transitions and panel idle at
10/1 Hz remain experimental. Configure `seamless.refreshRates` and
`idleRefreshRate` explicitly; recovery excludes these settings. Generic VRR
is not advertised.

`hardware.unicorn.hardwareKeys.enable` defaults to `false` and is enabled by
the console example. Short presses toggle the text console; long presses request
shutdown. `powerOffHoldSeconds` defaults to 3 and accepts 1–6 seconds.
`screen.enable`, `powerOff.enable` and `volume.enable` independently control
these actions and volume keys. Desktop sessions should handle their own keys.

Wired charging: [authentication, telemetry and hardware acceptance](charging.md).
