# Support status: Xiaomi Pad 6S Pro 12.4 (sheng)

[中文](status.zh.md) · [Device guide](README.md) · [Hardware support](hardware.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi Pad 6S Pro 12.4 (sheng) | Qualcomm SM8550 | Nixpkgs Linux 7.3-rc5 with Sheng patches | 2026-10-30 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 7 | 7 | 2 | 21 | 5 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (`boot_b`) → systemd-boot on FAT `linux-boot` → Linux, root on ext4 `linux`; boot without a USB host attached is unverified. |
| Generation update and rollback | Partial | New generations boot by default without rewriting U-Boot; older generations were only selected during bring-up, not in a recorded rollback. |
| RAM recovery | Works | ABL boots `recovery_b` independently; USB SSH, offline system deployment and recovery self-update work. |
| First installation from recovery | Untested | The system was deployed from recovery onto manually prepared partitions; `prepare-install` and `install-initial` are untested. |
| Reboot to bootloader or recovery | Works | Reboot arguments `bootloader` and `recovery` reach fastboot and RAM recovery. The EFI menu entries are untested. |
| Internal storage | Works | UFS; separate `linux` and `linux-boot` partitions sit beside Android, which stays intact. |
| microSD card | N/A | The tablet has no microSD slot. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | Dual-DSI NT36532E panel at 3048×2032, 120 Hz, taken over directly from U-Boot. (Verified on 2026-10-06.) |
| Backlight and screen off | Untested | Software sets and reads brightness; brightness changes and screen off and on are not yet verified on the panel. |
| Touchscreen | Works | NT36532E touch through the THP service; the stylus is untested. (Verified on 2026-10-05.) |
| Hardware buttons | Untested | Volume and power keys drive the U-Boot and recovery menus; their desktop actions are untested. |
| External display (USB-C DisplayPort) | Untested | A 4K monitor worked on an earlier kernel; the current kernel and USB role policy are not retested. |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Untested | Freedreno (Adreno 740) renders the desktop and glmark2 in software checks; on-screen output is not yet verified. |
| Vulkan acceleration | Untested | Turnip (Adreno 740) renders a Vulkan demo in software checks; on-screen output is not yet verified. |
| Hardware video decode | Untested | Iris decodes H.264, HEVC, VP9 and AV1 pixel-identically to software and mpv plays via VA-API; on-screen playback is not yet verified. |
| Speaker | Broken | All six CS35L43 amplifiers bind, but the UCM lookup fails, so PipeWire has no output. |
| Headphone jack | N/A | The tablet has no 3.5 mm headphone jack. |
| Microphone | Broken | A capture PCM exists, but the UCM lookup fails, so PipeWire has no input. |
| Camera | Untested | libcamera captures front scenes and rear test patterns; image quality is not yet evaluated and the ISP is uncalibrated. |
| Camera flash | Untested | Flash LED class devices are enabled; the flash is untested. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | WCN7850 autoconnects at 80 MHz with two streams and carries SSH, including after suspend; throughput is unmeasured. |
| Bluetooth | Partial | LE and BR/EDR discovery work; pairing and audio are untested on the current kernel. |
| USB networking (device mode) | Partial | NCM SSH works in the system and recovery at 10 Gb/s, but the host sometimes needed a manual address. |
| USB host / OTG | Untested | A USB game controller worked on an earlier kernel; the current kernel is untested. |
| Mobile data | N/A | Wi-Fi-only tablet without a cellular modem. |
| Voice calls | N/A | Wi-Fi-only tablet without a cellular modem. |
| SMS | N/A | Wi-Fi-only tablet without a cellular modem. |
| GNSS (GPS) | Untested | Receiver presence is not established. |
| NFC | Untested | NFC presence is not established. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | Fuel gauge readings are plausible while charging; a discharge is not yet tested. |
| Charging | Partial | The battery charged from 3% to 82%, with MiPPS fast charging; a full charge cycle is not yet tested. |
| Suspend | Partial | Suspend and resume succeed and Wi-Fi recovers; power draw and other peripherals are unverified. |
| Shutdown and reboot | Partial | Reboot works repeatedly; power-off and cold boot are not yet verified. |
| CPU frequency scaling | Untested |  |
| Thermal management | Untested |  |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | Auto-rotation worked on an earlier kernel; the optional sensor stack is untested on the current kernel. |
| Magnetometer | Untested |  |
| Ambient light sensor | Untested |  |
| Proximity sensor | Untested | Sensor presence is not established. |
| Hall sensor (cover) | Untested | The Hall input is described in the device tree; cover behavior is untested. |
| Vibration | Untested | Vibration motor presence is not established. |
| Fingerprint reader | Untested | The FPC1553 driver and fprintd are packaged; enrollment and verification are untested. |

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
