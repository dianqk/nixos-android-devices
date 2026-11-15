# Dodge audio

[中文](audio.zh.md)

The installed Dodge module enables AudioReach with a WCD9395 codec for built-in
microphones and USB-C analog headsets. Two Awinic PID `0x2308` amplifiers use
Secondary MI2S data line 1 for the speakers. Their provisional driver compatible
is `awinic,aw882308`; the shipping A1901 firmware labels them **AW88461**.

Speaker support is experimental. The driver enforces at least 30.1 dB hardware
attenuation and requires this board's OEM Music register tables. OEM HAL/ADSP
speaker calibration and dynamic protection are not implemented. A volume ceiling
does not replace that protection. OTP and persistent calibration are not written.
Built-in speaker playback works. Microphone and analog headset behavior remains
unverified.

`hardware.dodge.audio.enable` defaults to true for installed systems and false
for RAM recovery. The default [firmware archive](firmware.md) includes the two
OEM Music register tables, AudioReach topology and UCM profiles. A custom
`hardware.dodge.firmwareSource` must use the same Linux payload layout, including
`lib/firmware/qcom/sm8750/oneplus/dodge` and `share/alsa/ucm2`.
The firmware package's `audio` attribute refers to its single shared output.

Normal startup runs `dodge-audio.service`. It creates the static audio PD through
FastRPC, waits for listener initialization, then loads the AudioReach services.
UCM selects speaker, headphone and microphone routes as they are used; disabled
speaker routes mute both amplifiers. WirePlumber starts new playback routes at
30% volume; saved user volume remains effective, within the hardware ceiling.

Inspect initialization without playing or recording:

```sh
systemctl status dodge-audio.service
journalctl -b -u dodge-audio.service
cat /proc/asound/cards
aplay -l
arecord -l
wpctl status
```

The codec wiring and initial AudioReach/UCM data derive from
[Omarchy Mobile's Dodge audio support](https://github.com/derekross/omarchy-mobile/tree/10daa3dabd1cd7b629bed58c41f32b389efb6e1e/device/dodge/audio)
and its [kernel support](https://github.com/mrlund/linux-omarchy-mobile/tree/6cc4b65df980355e00417df3d4b7b8109e7d0d21).
The ACF parser checks the format documented by the
[OnePlus OEM driver](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750/tree/d50b305f7da9e14715a25120a4ac7b1a4b8b97c3/vendor/oplus/kernel/audio/codecs/aw882xx).
