# Hardware support

[Usage guide](README.md) · [中文](hardware.zh.md)

## Hardware adaptation

“Configured” describes repository support, not a fresh device test.

| Area | Adaptation | Status |
| --- | --- | --- |
| Boot and storage | SDM660 kernel/DTB, Android boot/recovery, measured eMMC storage roles, ext4 `userdata` | Configured; not boot-tested |
| Display and input | 8-inch LTE panel, FT5406 touch, recovery keys | Configured |
| GPU and video | Adreno firmware and kernel drivers | Configured; end-to-end use unverified |
| USB | NCM/SSH in the system; ACM+NCM/SSH in recovery; optional system ACM | Configured; validate the selected transport on hardware |
| Wi-Fi, Bluetooth, modem | WCN3990 and stock partition firmware loader; optional per-tablet addresses | Configured; identity must be supplied per tablet |
| Audio | ADSP, ALSA UCM and routing | Configured; speaker routing unverified |
| Camera and sensors | Kernel device-tree support | User-space path unverified |
