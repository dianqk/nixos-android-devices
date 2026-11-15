# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” describes repository support, not a fresh device test.

| Area | Adaptation | Status |
| --- | --- | --- |
| Boot and storage | SM8550 kernel/DTB, A/B boot and recovery, manual GPT preparation, ext4 `linux` root | Installed slot-B U-Boot/EFI and independent RAM recovery verified; fresh partitioning untested |
| Display and input | Panel, NT36532E touch, recovery keys | U-Boot menu and volume/power selection verified by RAM boot; patched 7.3 display takeover verified; touch unverified |
| GPU and video | Adreno and video firmware, kernel drivers | Hardware OpenGL/Vulkan verified; 7.3 H.264/HEVC 8-bit decode passes, FFmpeg Main10 fails |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi and Bluetooth | WCN7850 firmware and Bluetooth drivers | 7.3 negotiates 80 MHz EHT/NSS 2 at about 1.3 Gbit/s; Bluetooth discovery passes, pairing untested |
| Audio | ADSP firmware, topology, SoundWire and CS35L43 drivers | 7.3 detects all six amplifiers and ALSA PCMs; tested example has no active PipeWire output route |
| Sensors, fingerprint, pen | ADSP sensor services, FPC1553 and pen utilities | Optional; end-to-end use unverified |
| Camera | CAMSS/flash-class drivers, libcamera sensor gain helpers | Front scene capture and main-camera colour bars verified; uncalibrated ISP |

## Known limitations

The packaged kernel is Nixpkgs Linux 7.3. The hardware results on this page
were obtained with the 7.3-rc5 queue. See
the [kernel patches](../../pkgs/linux-kernel/sm8550/sheng/PATCHES.md).

What works with 7.3 on the installed system: direct 3048×2032 desktop display
at 120 Hz without cycling DSI power, Wi-Fi autoconnect and scanning, and SSH
over USB and Wi-Fi. Keep a working rollback generation.

Known issues and unverified areas:

- Boot without a USB host attached, suspend, and full colour fidelity are not
  verified.
- Video: FFmpeg's `h264_v4l2m2m` and `hevc_v4l2m2m` decode 1080p H.264 and HEVC
  Main pixel-identically to software decoding. HEVC Main10 fails at
  capture-buffer initialization (`EINVAL`). VA-API, mpv, zero-copy presentation
  and audio/video synchronization are covered by the
  [video guide](../video.md), not by these checks.
- Wi-Fi: 5 GHz connections negotiate 80 MHz EHT with two spatial streams
  (PHY rate about 1.1–1.3 Gbit/s). Throughput and 160/320 MHz operation are not
  measured.
- Bluetooth: LE and BR/EDR discovery work; pairing and audio are not verified.
  Configure the tablet's own Bluetooth address.
- Audio: the community UCM, audio topology and six CS35L43 protection firmware
  pairs restore automatic HiFi discovery, three playback PCMs and one capture
  PCM. The default PulseAudio microphone path starts and produces PCM buffers.
  Audible recording, speaker quality and DisplayPort playback are unverified.
  See the [audio data and firmware troubleshooting notes](../../pkgs/sheng/README.md).
- Speaker orientation: the module provides
  [speaker routing data](../configuration.md#speaker-routing-for-screen-orientation)
  for card `XiaomiPad6SPro`. Each amplifier's `<amp> ASPRX1 Slot Position`
  selects slot 0 (left) or 1 (right). `normal` (native 3048×2032 landscape, T
  amplifiers at the left edge) and `180` (slots swapped) are verified. `90` and
  `270` are unverified and keep the `normal` routing until the portrait speaker
  layout is checked.
- Camera: libcamera captures front OV32D40 scenes at 3264×2448 and rear S5KJN1
  colour bars at 4080×3060. Rear scene quality, autofocus, flash, calibrated
  colour and the depth sensor are not verified.
- USB negotiates 10 Gb/s in recovery and the installed system; sustained
  throughput is not measured. Keep the module's ADSP firmware in recovery:
  without it Type-C/UCSI does not start and USB is limited to 480 Mb/s.
- Kernel logs contain early display-SID SMMU faults, CPU feature variation
  warnings, CDSP subsystem-event/APM command timeouts, audio warnings and a
  missing-backend-DAI warning. They are known and do not indicate a new fault.

## Optional settings

Sheng uses the shared NCM system / ACM+NCM recovery USB policy. Dual-role
and Type-C support remain enabled; automatic cable-role transitions still
require hardware validation. The module also owns the WCN7850 P2P
NetworkManager exclusion.
Set `hardware.sheng.wifiMacAddress` to this
unit's known factory address. `hardware.sheng.suspendWorkarounds.enable`
is opt-in (default `false`): it filters unused wake sources and cold-cycles
`ath12k_wifi7` across suspend. Suspend remains unverified in the minimal example.

Suspend uses `deep` only (`hardware.sheng.suspend.memSleep`). The device
module declares wakeup sources for the shared
[wakeup policy](../configuration.md#suspend-wakeup-sources): `powerKey`,
`rtc`, `cover` (gpio-keys: opening the cover wakes through the Hall switch,
closing a keyboard cover through the tablet-mode switch), `usbPower` (USB
supply and UCSI source supplies; plug and unplug wake are not yet confirmed)
and `wirelessCharging` (untested). For example, to keep only the confirmed
sources:

```nix
androidDevices.power.wakeup = {
  enable = true;
  keep = [ "powerKey" "rtc" "cover" ];
};
```
