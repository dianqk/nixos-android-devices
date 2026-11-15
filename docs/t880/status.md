# Support status: Alldocube iPlay 80 mini Ultra (t880)

[中文](status.zh.md) · [Device guide](README.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Alldocube iPlay 80 mini Ultra (t880) | MediaTek MT6897 (Dimensity 8300) | Linux 7.3.1 with T880 patches | 2026-11-10 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 16 | 13 | 8 | 4 | 1 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | Stock LK → U-Boot (`boot_a`) → systemd-boot on FAT `linux-boot` → Linux, root on `linux`; Android stays on slot B. |
| Generation update and rollback | Works | New generations boot by default and a rollback boots the older one; `boot_a` stays unchanged. |
| RAM recovery | Partial | Host-supplied RAM recovery boots through U-Boot USB fastboot; a working slot-A U-Boot is required. |
| First installation from recovery | Works | `prepare-install`, `install-image` and `install-initial` installed and booted the system. |
| Reboot to bootloader or recovery | Works | Reboot arguments `bootloader` and `recovery` reach LK fastboot and RAM recovery; the U-Boot menu keys are untested. |
| Internal storage | Works | UFS 4.0 at HS-G5 x2 with eight hardware queues (MCQ); sequential reads reach 4.3 GB/s. Linux partitions are split from the original userdata allocation. |
| microSD card | Partial | A card is detected at UHS-I SDR104, read and hot-removed; mounting and writing are untested. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Partial | 1600×2560 through mediatek-drm at 60-144 Hz. Wake restores clear output after display power cycling; intermittent half-black boots remain unresolved. (Verified on 2026-10-17.) |
| Backlight and screen off | Partial | 1024-level PWM brightness control works. Display power-off intermittently fails to complete. (Verified on 2026-10-15.) |
| Touchscreen | Works | Novatek NT36523N multi-touch in the desktop. (Verified on 2026-10-15.) |
| Hardware buttons | Partial | Power and volume keys generate events. The power key toggles display power with the display limits above; volume actions need audio support. (Verified on 2026-10-16.) |
| External display (USB-C DisplayPort) | Partial | 720p60, 1080p60, 1440p60 and 4K30 source modes produce output through a 1080p60 capture device. Display off/on and repeated boots work; physical reconnect and other monitors remain untested. |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Works | Panthor with a Mesa that supports Mali v11 renders the desktop; glmark2 runs at 265 MHz-1.4 GHz. (Verified on 2026-10-16.) |
| Vulkan acceleration | Untested | PanVK (not conformant) passes a dEQP-VK subset and vkmark in software checks; on-screen output is not yet verified. |
| Hardware video decode | Partial | 8-bit V4L2/VA-API H.264/HEVC, VP9 profile 0 and AV1 Main decode, including crop, seek and stable exported surfaces. CPU conversion/replay can be costly; 10-bit and VP8 are not exposed. |
| Speaker | Broken | The AFE and AW88261 amplifiers are not integrated. |
| Headphone jack | Broken | Wired headsets use USB-C analog audio, which is not integrated. |
| Microphone | Broken | The MT6368 codec and its microphones are not integrated. |
| Camera | Broken | No camera ISP driver is available. |
| Camera flash | Broken | The rear flash LED driver is not integrated. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | Out-of-tree connsys drivers with the stock firmware files; SSH over Wi-Fi works. |
| Bluetooth | Partial | A2DP (LDAC), AVRCP volume/playback controls and BLE keyboard/mouse input work. Audio has intermittent dropouts; opt-in mSBC and CVSD carry both directions, with CVSD also showing occasional short transients. Controller idle/wake and BlueZ power-off/reopen work. Classic HIDP is untested. |
| USB networking (device mode) | Works | NCM with DHCP and SSH at SuperSpeed in the system and recovery. |
| USB host / OTG | Untested | The port switches to the host role and xHCI binds; no USB device has been tested. |
| Mobile data | Works | 5G NR and LTE data through ModemManager; the modem starts once per boot. |
| Voice calls | Broken | Voice calls and the modem audio path are not integrated. |
| SMS | Works | Sending and receiving work on 5G NR (over IMS) and LTE. |
| GNSS (GPS) | Broken | GNSS depends on closed vendor userspace and is not integrated. |
| NFC | Untested | Presence not established. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | MT6375 gauge values are plausible while charging; an unplugged discharge check is pending. |
| Charging | Partial | Bounded 5 V charging at about 9 W works and ends at hardware termination; battery care is available but off by default; when enabled it holds the battery at 75-80 % while plugged in (`nexusctl battery full-charge` charges once to 100 %). |
| Suspend | Broken | Suspend is not implemented; only CPU core idle states work. |
| Shutdown and reboot | Works | Power-off and reboot complete; with USB attached the device powers on again by itself. |
| CPU frequency scaling | Works | `mtk-cpufreq-hw` with schedutil scales the three clusters up to 2.2, 3.2 and 3.35 GHz (at its top step the prime core runs at about 3.0 GHz, as on stock Android); per-core throughput equals stock Android. Multi-core results are lower under sustained load because the firmware temperature target throttles the CPUs. Geekbench 7 1247 single-core / 3565 multi-core: [Geekbench 7](https://browser.geekbench.com/v7/cpu/645266) |
| Thermal management | Works | 28 LVTS zones; CPU and GPU throttle near 95 °C; there is no skin temperature control. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Partial | Auto-rotation followed the device but 180° off; the orientation fix awaits a hand test. (Verified on 2026-10-20.) |
| Magnetometer | Partial | The QMC6308 is an IIO magnetometer (`scp-magn`) through the SCP sensor hub; the response to orientation is not yet verified. The ICM4N607 gyroscope is available as `scp-gyro`. |
| Ambient light sensor | Works | JSA1130 through the SCP sensor hub as IIO illuminance; optional automatic brightness. |
| Proximity sensor | N/A | The stock sensor list has no proximity sensor. |
| Hall sensor (cover) | Partial | Cover close/open is reported and turns the screen off; one session hung after repeated cover cycles. (Verified on 2026-10-20.) |
| Vibration | Works | `regulator-haptic` on the MT6368 VIBR rail. (Verified on 2026-10-16.) |
| Fingerprint reader | Untested | Presence not established; the vendor device tree has a Goodix node and no driver is integrated. |

## Status legend

| Status | Meaning |
| --- | --- |
| Works | The complete function passed a real-device test. |
| Partial | A useful subset works, or a known reliability or coverage gap remains. |
| Broken | The hardware exists, but the integration is missing or does not work. |
| Untested | The hardware exists, but there is no sufficient real-device result yet. |
| N/A | The device does not have this hardware. |

“Works” requires:

- Installed boot (U-Boot, systemd-boot, Linux): The vendor bootloader starts U-Boot from the device's boot partition, which boots the installed NixOS generation through systemd-boot.
- Generation update and rollback: A new generation boots by default and an older generation boots again after a rollback, without rewriting U-Boot.
- RAM recovery: Recovery boots from its own partition, independent of the installed U-Boot, and its USB SSH and storage operations work.
- First installation from recovery: Recovery prepares the partitions and `install-initial` installs a verified closure and EFI generation that boots through separately installed U-Boot.
- Reboot to bootloader or recovery: Rebooting with the bootloader and recovery arguments reaches the vendor bootloader and RAM recovery.
- Internal storage: The internal UFS/eMMC holds the ext4 root and FAT /boot and survives reboots and updates.
- microSD card: A card is detected, mounted, read and written.
- Built-in display: The native panel shows the desktop at its full resolution.
- Backlight and screen off: Brightness changes and the panel turns off and on again.
- Touchscreen: Touch input maps correctly to the panel in the desktop.
- Hardware buttons: Power and volume keys reach the desktop and trigger their actions.
- External display (USB-C DisplayPort): A monitor attached through USB-C shows an extended desktop.
- OpenGL ES acceleration: The desktop and a GL benchmark render through the hardware driver without GPU faults.
- Vulkan acceleration: A Vulkan application renders through the hardware driver.
- Hardware video decode: A common codec plays through V4L2 hardware decoding.
- Speaker: Playback is audible from the built-in speakers.
- Headphone jack: Playback is audible from wired headphones and switches automatically.
- Microphone: The built-in microphone records intelligible audio.
- Camera: An application captures images from the built-in cameras.
- Camera flash: The flash LED turns on and off.
- Wi-Fi: Associates with an access point, gets an address and carries traffic.
- Bluetooth: Pairs with a device and uses a profile such as audio or input.
- USB networking (device mode): The host reaches SSH over the USB NCM link with DHCP.
- USB host / OTG: A USB device attached to the port enumerates and works.
- Mobile data: A SIM card connects to the cellular network and carries data.
- Voice calls: Calls are placed and received with audio in both directions.
- SMS: Messages are sent and received.
- GNSS (GPS): A location fix is reported to userspace.
- NFC: A tag or reader is detected.
- Battery status: Capacity, voltage, current and charge state are plausible over a discharge.
- Charging: The battery charges from a USB charger to full within safe limits.
- Suspend: The device suspends, saves power and resumes with working peripherals.
- Shutdown and reboot: Power-off and reboot complete without hangs, and the device cold boots again.
- CPU frequency scaling: CPU frequency follows load on every cluster.
- Thermal management: Temperatures are reported and throttling engages under sustained load.
- Accelerometer (auto-rotation): The desktop rotates with the device.
- Magnetometer: Readings change with orientation.
- Ambient light sensor: Readings follow the light and can drive automatic brightness.
- Proximity sensor: Readings change when an object approaches.
- Hall sensor (cover): Closing and opening a cover is reported and can turn the screen off.
- Vibration: The motor vibrates on request.
- Fingerprint reader: A finger is enrolled and verified.
