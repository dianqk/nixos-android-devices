# Aurora audio

[中文](audio.zh.md)

Use the OS1.0.3.0.UNACNXM Android 14 firmware baseline. The Aurora module
installs AudioReach topology, UCM and the OEM dual-CS35L43 protection firmware
when `hardware.aurora.audio.enable` is enabled (the installed-system default).
Audio firmware and userspace routing are excluded from RAM recovery.

Stereo speaker playback through PipeWire works, with each channel reaching
its own amplifier. See [Known limits](#known-limits) for what is not verified.

## Per-handset speaker calibration

Retain the handset's original `persist/audio/crus_calr.bin` and
`persist/audio/crus_calr.txt` while Android root access is available. The text
file identifies the top (`T`) and bottom (`B`) raw calibration integers;
use these integers, not the resistance values in parentheses. Never copy
another handset's values or run a new calibration merely to initialize Linux.

The existing firmware override accepts `speakerCalibration` alongside
`bluetoothNvm`. Keep both in the same override:

```nix
{ inputs, pkgs, ... }: {
  hardware.aurora.firmwarePackage =
    inputs.androidDevices.legacyPackages.${pkgs.stdenv.buildPlatform.system}
      .devices.aurora.firmware.override {
        firmwareVariant = "android14";
        bluetoothNvm = ./hmtnv20.b2e;
        speakerCalibration = builtins.fromJSON
          (builtins.readFile ./aurora-speaker-calibration.json);
      };
}
```

The JSON file must contain `top` and `bottom`, each a positive integer no
larger than 16777215. Keep it and the Bluetooth NVM private. The public firmware
contains product tuning coefficients, not personal calibration. UCM loads the
protection DSP and applies these values to each `CAL_R_SEL` control before
enabling the amplifiers. Without the override, factory calibration is not
injected; acoustic protection must not be considered validated.

## Playback and diagnostics

The speaker PCM uses stereo 48 kHz **S32_LE** end to end. PipeWire/ALSA may
convert application formats, but raw `hw:0,0` playback must use S32_LE.
An S16_LE frontend connected directly to the S32_LE TDM backend crashes the
Android 14 `audio_process`/ADSP, so the topology advertises S32_LE for speaker
playback and the PCM driver accepts that format.

UCM matches both the card model and the kernel's `xiaomi-Xiaomi14Ultra` long
name. DSP firmware names are lowercase, as required by the upstream wm_adsp
filename normalization. The HiFi enable sequence initializes both amplifier digital
volumes to -12 dB; start application volume low and use gentle material.
After DSP preload, a bounded readiness check waits for both dynamic calibration
controls before writing factory values and enabling output. A timeout aborts
the enable sequence; it must not be bypassed with uncalibrated playback.

The HiFi verb enables the MultiMedia1 → secondary TDM backend before ACP
probes the playback PCM. Speaker device activation then loads/calibrates the
DSPs and enables the amplifiers. Putting the backend route only in the Speaker
sequence leaves the probe without a backend: PipeWire exposes Dummy Output
and reports the HiFi profile unsupported. Verb selection keeps the amplifiers
disabled, and leaving HiFi disconnects the route. With this ordering PipeWire
initializes the speaker sink automatically after a normal boot.

Useful checks:

```sh
cat /proc/asound/cards
aplay -l
alsaucm -c hw:0 list _verbs
amixer -c 0 cget "name=B DSP1 Protection 5f210 CAL_R_SEL"
amixer -c 0 cget "name=T DSP1 Protection 5f210 CAL_R_SEL"
journalctl -k -b | grep -E 'cs35l43|wcd939|APM|audio_process|fatal error'
```

A healthy start registers both CS35L43 A1 amplifiers and the WCD9395
SoundWire endpoints, loads the stock protection firmware and reads back the
factory calibration. The OEM firmware/coefficient pair reports minor
algorithm-version differences; the files match the stock Android 14 pair and
the messages are harmless.

## Volume stages

Check all volume stages before diagnosing silence: application stream gain,
PipeWire sink gain/mute, and the amplifier's digital volume multiply. UCM sets
the amplifier to -12 dB; a stream at linear gain 0.5 adds another approximately
-6 dB. Quiet source material can therefore remain quiet even at full desktop
volume. Read the sink's actual linear `channelVolumes` and `softVolumes` from
`pw-dump` rather than assuming an application's volume setting is the only
attenuation. Do not remove protection or raise amplifier gain because an
attenuated clip is quiet.

Successful PCM writes or clock/calibration readback do not prove audible
output; listen after changing the audio configuration.

## Known limits

- Microphone capture, headset audio/buttons and Bluetooth audio are not
  verified.
- Channel balance, loudness and protection under sustained or high-volume
  output are not verified.
- Without the per-handset calibration override, acoustic protection is not
  validated.

## Implementation notes

### Stereo framing

Use DSP_A (short frame sync, one-bit data delay), matching the OEM CS35L43
startup routine, with four 32-bit slots; I2S long-sync does not deliver both
channels. Channel zero reaches the top amplifier and channel one the bottom
amplifier. This mapping is fixed to the chassis and does not follow screen
rotation.

### Speaker TDM pins

Aurora uses the main TLMM GPIO 121 (clock), 123 (word select), 122
(data0) and 124 (data1), matching the stock `sec_tdm_pinctrl` node.
LPASS LPI GPIO 6–9 expose similarly named functions but are not the board's
speaker connection. With those incorrect pins, ALSA streams and DSP startup
succeed silently: both amplifiers report `CLOCK_OK=0` and zero `AUDIO_IN_MAX`.
Selecting the stock TLMM functions makes `CLOCK_OK=1` and the input peaks
nonzero. Check these controls during playback, since idle values differ.

### Shared supply constraints

BOB1 also supplies LDOs used by USB and the display. The mainline `pmic5_bob`
voltage table is `3000000 + n * 32000` microvolts. Do not fix its voltage to the
OEM initial request of 3296000: that value is not selectable, causing regulator
registration failure and removal of the other PM8550 regulators. This can
leave USB, storage and display waiting for supplies without a kernel panic.
The board uses the upstream SM8650-HDK range, 3296000–3960000, and declares
BOB1's downstream LDO dependencies so unused-regulator cleanup is safe.

Sources: [MiCode Aurora audio driver](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/tree/d2ddef03a379bc82c7bcd08481e29e08bbff80eb),
[AudioReach TDM API](https://github.com/AudioReach/audioreach-graphservices/blob/3094583c726710b66eb0204fc5d6a7b336d9e575/spf/api/modules/pcm_tdm_api.h),
[upstream SM8650 HDK](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-hdk.dts?h=v7.3-rc5).

### TDM clock polarity

The stock Android 14 live DT requests ADSP clock attribute 4
(`CLOCK_ATTRIBUTE_INVERT_COUPLE_NO`), while the MiCode CS35L43 startup and
handset log select `DSP_A | NB_NF` at the codec (`fmt=0x4004`). These settings
refer to separate ends of the link. Keep the CPU DAI at DSP_A/IB_NF to retain
that ADSP clock request, and the codec DAI at DSP_A/NB_NF to match its stock
sampling edge. Deriving both from one format would also set the codec's
ASP_CONTROL2 BCLK inversion bit.

Aurora supplies an explicit CPU TDM format; boards without that override retain
the existing codec-derived fallback. The change intentionally retains 48 kHz,
four 32-bit slots, DSP protection and calibration. The codec TX width differs
from the OEM playback callback (24 bits in Linux versus 32).

Sources: [MiCode codec startup and hw_params](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/blob/d2ddef03a379bc82c7bcd08481e29e08bbff80eb/asoc/codecs/cs35l43/cs35l43.c),
[MiCode ADSP TDM clock request](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/blob/d2ddef03a379bc82c7bcd08481e29e08bbff80eb/asoc/msm_common.c),
[AudioReach clock attributes](https://github.com/AudioReach/audioreach-graphservices/blob/3094583c726710b66eb0204fc5d6a7b336d9e575/spf/api/modules/audio_hw_clk_api.h).
