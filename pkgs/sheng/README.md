# Sheng audio data

[中文](README.zh.md)

The Sheng module installs its own ALSA UCM configuration and selected device
firmware. Consumers do not need to set a PulseAudio source or an ALSA device
number in individual applications.

The two Sheng UCM files retain map220v's author headers and are copied unchanged
from [ianchb/debian-sheng at da1d2761](https://github.com/ianchb/debian-sheng/tree/da1d2761dbc1ccaea0122f8b0c2dce2d52edaeb2/alsa-xiaomi-sheng/usr/share/alsa/ucm2/Xiaomi/sheng).
A relative `conf.d/sm8550/xiaomi-XiaomiPad6SPro12.4.conf` link matches the ALSA
card's long name; the existing `Xiaomi-Pad6SPro.conf` entry remains available.
The community configuration keeps the six CS35L43 DSP protection paths and
DisplayPort route. It replaces the older local routing patch.

Only the audio topology and the six CS35L43 protection firmware/coefficient
pairs come from [ianchb/sheng-firmware at 053da477](https://github.com/ianchb/sheng-firmware/tree/053da477a5c338ac28d7c1c869e8c3ff7ca24d11).
Every file has its own fixed hash. Wi-Fi, Bluetooth, ADSP and other device
firmware come from the per-device archive referenced by `firmware-source.nix`.
These packaged files do not write per-device calibration partitions.

After changing the topology, reboot into the updated installed system. Check
`wpctl status` for real audio sources and the HiFi profile before diagnosing an
application's microphone. A bounded capture to a discard sink establishes
streaming only; speaker playback, acoustic quality and DisplayPort require
separate validation.

The Linux firmware loader tries uncompressed files across all firmware search
paths before trying compressed files. A legacy uncompressed topology under
`/lib/firmware` can therefore shadow a newer `.bin.zst` in the configured Nix
firmware directory. Check the effective hashes and preserve any old file before
removing that shadow; this package does not delete user-managed firmware.
