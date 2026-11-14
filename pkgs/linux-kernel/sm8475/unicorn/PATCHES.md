# Xiaomi 12S Pro kernel support

[中文](PATCHES.zh.md) · [Device guide](../../../../docs/unicorn/README.md)

The queue targets the repository's locked Linux 7.3.4. [`series.nix`](series.nix)
imports the [Unicorn SM8475 queue](../README.md), selected subsystem fixes and
Unicorn drivers. [`config.nix`](config.nix) supplies board overrides on top of
`kernel.config`, common policy and the shared SoC configuration.

| Area | Implementation |
| --- | --- |
| Platform | Shared TLMM, SoC description, UBWC and GCC power management; Unicorn clock, PHY and GPU OPP settings |
| UFS | Shared clock-parent, OPP, RCG and Hibern8 fixes; SM8475 low-gear initialization and controller timing |
| USB | PTN3222 eUSB2 repeater, PMIC GLINK/UCSI, DWC3 role switch, xHCI and USB Audio |
| Display/GPU | A730 revision and shared GMU integration; L2S 1440×3200 DSC panel at 24/30/40/60/90/120 Hz, 60 Hz preferred |
| Touch | ST FingerTipS SPI multitouch |
| DSP/battery | ADSP/SLPI services and board-specific battery message layout |
| Wireless | External WLAN/Bluetooth power sequencer, PCIe SID mapping and UART consumers |
| Audio | WCD938x, AudioReach shared-memory endpoints, 96 kHz TDM and CS35L41 speakers; SoundWire ports/resume and 400 kHz speaker I2C |
| Camera | CAMSS, separate CSI2 PHYs, CCI and PM8008; native S5KJN1 ultra/tele and OV32B40 front RAW10 pipelines |
| Other | SN NCI reader mode, AW86927 force feedback, infrared, board supplies and thermal cooling |

`panel.patch` contains the final panel and DRM runtime integration, including
fixed per-lane bandwidth, OEM command streams, active mode switching and panel
idle transactions. The latter two are opt-in; generic VRR is not advertised.
`dpu-disabled-commit.patch` avoids reading CTL state for a disabled encoder.
`dpu-debugfs-state-lock.patch` serializes CRTC debugfs reads.

The camera implementation includes separate CSI PHY interfaces and lookup
dependencies from Linux commit `067c5c24cef23d913b67eaaf71ae67e7169a6620`.
Callbacks use the locked kernel APIs. Asphalt retains integrated CSIPHY;
the two camera queues are selected independently. Sensor sources and capture
limits are documented in the [camera guide](../../../../docs/unicorn/camera.md).

## Configuration and firmware

Storage, USB administration, display and touch are built in for module-free
RAM recovery. Audio, DSP services, wireless, cameras, NFC, haptics and infrared
are modules. The installed system and recovery share one kernel derivation.

The device module provides GPU, DSP and radio firmware through
`hardware.firmware`, with GPU/PAS files in the initrd. Speaker firmware,
coefficients, calibration and Music parameters are private runtime inputs;
protection rejects missing or invalid inputs. See the
[device guide](../../../../docs/unicorn/README.md) for configuration and current
hardware support. IMX707 and complete analogue headset routing remain unsupported.

## Build

```sh
nix build .#devices.unicorn.kernel
nix build .#devices.unicorn.recovery
```

The builder verifies requested overrides after `olddefconfig`. Use
`tools/kernel-queue.py --help` to import or independently verify an evaluated
queue. Shared SM8475 changes require replay and build checks for both Unicorn
and Asphalt. Build success alone does not establish hardware acceptance.
Kernel files retain their copyright and SPDX notices.
