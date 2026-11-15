# Support status: Xiaomi 14 Ultra (aurora)

[中文](status.zh.md) · [Device guide](README.md) · [Hardware support](hardware.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi 14 Ultra (aurora) | Qualcomm SM8650 (Snapdragon 8 Gen 3) | Linux 7.3 with Aurora patches | 2026-10-30 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 17 | 10 | 6 | 7 | 2 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (`boot_b`) → systemd-boot on the FAT `linux-boot` ESP → Linux 7.3, root on `linux`; slot A stays Android. |
| Generation update and rollback | Works | Rolling back to an older generation and returning both booted; `boot_b` stayed unchanged. |
| RAM recovery | Works | Recovery boots from `recovery_b` independently of U-Boot, with USB NCM/SSH and a persistent host key. |
| First installation from recovery | Works | `prepare-install` splits the original userdata allocation; installation and the first EFI boot passed. |
| Reboot to bootloader or recovery | Works | Reboot arguments `bootloader` and `recovery` reach OEM fastboot and the stored recovery. |
| Internal storage | Works | UFS with MCQ; Android A, super and calibration partitions are preserved. |
| microSD card | N/A | The device has no microSD slot. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | N1 1440×3200 DSC panel at 30/60/120 Hz; a brief noise flash before the Linux console remains. (Verified on 2026-10-09.) |
| Backlight and screen off | Works | Brightness slider and screen off/on work without corruption after wake. (Verified on 2026-10-09.) |
| Touchscreen | Works | In-kernel driver for the Android 16 controller firmware; palm rejection and edges are untested. (Verified on 2026-10-24.) |
| Hardware buttons | Untested | Power and volume keys enumerate and the power key wakes from suspend; desktop actions are unchecked. |
| External display (USB-C DisplayPort) | Works | A DP monitor shows the desktop; DP audio, other modes and hotplug are untested. (Verified on 2026-10-08.) |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Works | Adreno 750 through Freedreno renders the desktop; glmark2 validation passed on the former Android 14 base. (Verified on 2026-10-24.) |
| Vulkan acceleration | Untested | vkmark ran through Turnip without faults; on-screen output is not yet verified. |
| Hardware video decode | Partial | VA-API over Iris V4L2 played ordinary video on the former Android 14 base; not rechecked on Android 16. (Verified on 2026-10-08.) |
| Speaker | Partial | Stereo music played from the speakers on the former Android 14 base; not rechecked on Android 16. (Verified on 2026-10-08.) |
| Headphone jack | N/A | No 3.5 mm jack. |
| Microphone | Untested | Microphone capture is unverified. |
| Camera | Partial | The four rear cameras capture RAW and processed images at 30 fps through libcamera and PipeWire, one camera at a time; the front camera is not yet enabled. Autofocus, stabilisation and image tuning are not implemented. |
| Camera flash | Broken | No flash LED driver is integrated. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | WCN7850 associates on 5 GHz (EHT), gets DHCP and carries traffic; reconnects after resume. |
| Bluetooth | Partial | BR/EDR and LE pairing, L2CAP data and GATT reads work; audio and HID profiles are untested. |
| USB networking (device mode) | Works | NCM with DHCP and SSH in the system and recovery, at 5 Gbit/s in the system. |
| USB host / OTG | Broken | USB host mode and data-role swap are not supported yet. |
| Mobile data | Works | Experimental opt-in: LTE/5G NR registration with IPv4 and IPv6 data. |
| Voice calls | Broken | No voice (VoLTE/IMS) stack is integrated. |
| SMS | Partial | Sending and receiving worked on the former Android 14 base; not rechecked on Android 16. |
| GNSS (GPS) | Untested | No location fix has been obtained. |
| NFC | Broken | No NFC driver is integrated. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Works | ADSP battery telemetry is consistent; the charge counter follows discharge in coarse steps. |
| Charging | Partial | 9 V USB PD charging was observed; no full charge cycle, and wireless charging is not supported. |
| Suspend | Works | s2idle standby of over 2 h resumed cleanly at about 28 mA; `deep` is not usable. |
| Shutdown and reboot | Partial | Reboots now complete reliably; power-off and cold boot are not yet verified. |
| CPU frequency scaling | Partial | All four CPU policies reach their top frequencies under load and drop back when idle; performance is not yet benchmarked. |
| Thermal management | Partial | Temperatures are reported; throttling under sustained load is unverified. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Works | SSC accelerometer drives desktop rotation; rechecked only in software on Android 16. (Verified on 2026-10-07.) |
| Magnetometer | Untested |  |
| Ambient light sensor | Partial | The front sensor streams lux to automatic brightness; curve tracking is unverified. |
| Proximity sensor | Untested | Sensor presence is not established. |
| Hall sensor (cover) | Untested | Sensor presence is not established. |
| Vibration | Broken | No vibration motor driver is integrated. |
| Fingerprint reader | Broken | No fingerprint driver is integrated. |

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
