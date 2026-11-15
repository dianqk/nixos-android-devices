# Support status: Xiaomi Redmi Note 12 Turbo / POCO F5 (marble)

[中文](status.zh.md) · [Device guide](README.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi Redmi Note 12 Turbo / POCO F5 (marble) | Qualcomm SM7475 (Snapdragon 7+ Gen 2) | Linux 7.3 with Marble patches | 2026-11-02 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 6 | 11 | 3 | 20 | 2 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (`boot_b`) → systemd-boot on the `linux-boot` ESP → Linux 7.3; U-Boot marks slot B successful. |
| Generation update and rollback | Partial | New generations boot by default; a rollback to an older generation is not recorded. |
| RAM recovery | Partial | Recovery boots RAM-only through `fastboot boot` with USB SSH and storage operations; it is not installed to its own partition. |
| First installation from recovery | Works | `prepare-install`, `format-root` and `install-initial` installed a system that boots from `boot_b`. |
| Reboot to bootloader or recovery | Partial | Rebooting to the bootloader from recovery reaches fastboot; the recovery argument and the installed system's reboot modes are unchecked. |
| Internal storage | Partial | Root and ESP live on UFS; a fix for UFS link failures under load has passed only short write and suspend tests. |
| microSD card | N/A | The phone has no microSD slot. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Untested | The panel showed the desktop with a diagnostic kernel; the later release-kernel fix is only checked in software. |
| Backlight and screen off | Untested | Brightness values and DPMS off/on change in software; the effect on the panel is not yet verified. |
| Touchscreen | Untested | The Goodix touchscreen reports input; mapping in the desktop is not yet verified. |
| Hardware buttons | Untested | Power and volume keys work in U-Boot and the power key wakes from suspend; desktop actions are not yet verified. |
| External display (USB-C DisplayPort) | N/A |  |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Untested | The niri desktop renders on the Adreno GPU in software checks; on-screen output with the current kernel is not yet verified and no GL benchmark has been run. |
| Vulkan acceleration | Untested |  |
| Hardware video decode | Untested | Iris decodes H.264, HEVC and VP9 frame-identical to software; on-screen playback is not yet verified. |
| Speaker | Works | Both speakers play music cleanly at the stock level; there is no speaker protection, so keep moderate volumes. (Verified on 2026-10-25.) |
| Headphone jack | Broken | The wired headset path (headphones, headset microphone, jack detection) is not ported. |
| Microphone | Partial | The bottom microphone records with signal; other microphones are not set up. (Verified on 2026-10-25.) |
| Camera | Partial | The wide, ultra-wide, macro and front cameras capture RAW and processed images at 30 fps through libcamera and PipeWire, one camera at a time. Picture orientation and colour are not yet verified; autofocus, flash and image tuning are not implemented. |
| Camera flash | Untested |  |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | WCN6855 associates and carries traffic; its firmware crashed after two of eight resumes and recovered. |
| Bluetooth | Partial | Pairs with Secure Simple Pairing. With a headset, audio playback (A2DP, including LDAC) and remote control (AVRCP volume in both directions, play and pause) work. Hands-free audio (HFP) connects with CVSD, mSBC and LC3-SWB and carries audio in both directions; audio to the headset is mostly clean, but the headset microphone direction has dropouts and clicks. |
| USB networking (device mode) | Works | SSH over USB NCM works in RAM recovery and the installed system. |
| USB host / OTG | Untested |  |
| Mobile data | Untested | The modem starts and ModemManager lists it; no SIM test is recorded. |
| Voice calls | Broken | Voice call audio routes are not ported. |
| SMS | Untested |  |
| GNSS (GPS) | Broken | Location needs patched libqmi and ModemManager, which are not integrated. |
| NFC | Untested | Not set up. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | The battery manager reports capacity and charge counter, used for suspend drain; a full discharge is unchecked. |
| Charging | Partial | Charges at about 1.3 A from a USB charging downstream port (CDP, 1.45 A input limit); fast charging adapters and a full charge are not yet checked. |
| Suspend | Partial | s2idle reaches SoC sleep and wakes by RTC and power key; drain is about 100 mA and UFS resume fixes are still in test. |
| Shutdown and reboot | Partial | Reboot works; power-off followed by a cold boot is not recorded. |
| CPU frequency scaling | Works | Three `schedutil` policies reach 1.80, 2.50 and 2.92 GHz; DDR reaches 3196 MHz under load. [Geekbench 7](https://browser.geekbench.com/v7/cpu/782476) |
| Thermal management | Untested |  |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | The BMI26x reports orientation and the screen rotated in all four orientations; on-screen rotation is not yet verified. |
| Magnetometer | Untested | The QMC630x is fitted but not set up. |
| Ambient light sensor | Untested | The TCS3701 is fitted but not set up. |
| Proximity sensor | Untested | Presence of a physical proximity sensor is not established; Android uses a virtual one. |
| Hall sensor (cover) | Untested | Presence not established. |
| Vibration | Untested | The PM8350B haptics driver is built; vibration is not tested. |
| Fingerprint reader | Untested |  |

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
