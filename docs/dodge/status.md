# Support status: OnePlus 13 (dodge)

[中文](status.zh.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| OnePlus 13 (dodge) | Qualcomm SM8750 (Snapdragon 8 Elite) | Linux 7.3.1 with Dodge patches | 2026-11-09 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 17 | 11 | 0 | 14 | 0 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | Installed slot-B U-Boot boots NixOS through systemd-boot; Android slot A is preserved. |
| Generation update and rollback | Partial | Generation updates boot normally; manual rollback remains untested. |
| RAM recovery | Works | Independent host-supplied RAM recovery boots with a populated ESP and provides USB SSH. |
| First installation from recovery | Works | Recovery prepares root/boot partitions and installs a bootable NixOS closure. |
| Reboot to bootloader or recovery | Partial | Reboot to the OEM bootloader works; the recovery reboot action remains untested. |
| Internal storage | Works | UFS hosts the installed ext4 root and FAT boot filesystem. |
| microSD card | Untested |  |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | (Verified on 2026-11-08.) |
| Backlight and screen off | Works | Brightness adjustment and panel off/wake work. (Verified on 2026-11-07.) |
| Touchscreen | Works | Contact release and driver removal ownership are corrected. (Verified on 2026-11-08.) |
| Hardware buttons | Works | Power and both volume directions work. (Verified on 2026-11-07.) |
| External display (USB-C DisplayPort) | Works | DASUNG works at native 3200x1800 around 40 Hz; the self-powered display does not charge the phone. (Verified on 2026-11-10.) |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Partial | The desktop uses Adreno acceleration; a GL benchmark has not been run. |
| Vulkan acceleration | Partial | Geekbench 6.7.1 Preview Vulkan compute: 15159 after GPU clock calibration was corrected. Earlier results: [8534 with default settings](https://browser.geekbench.com/v6/compute/6966589) and [8750 with diagnostic shader-IR logging](https://browser.geekbench.com/v6/compute/6966684), both before the correction. Actual compute clock is restored to about 1.1 GHz. Graphical rendering remains unverified. [Geekbench 6](https://browser.geekbench.com/v6/compute/6966777) |
| Hardware video decode | Partial | VA-API hardware decode passes H.264, HEVC, VP9 and AV1 frame comparisons; visual playback remains unverified. |
| Speaker | Works | Built-in speaker playback works with a fixed hardware volume ceiling. (Verified on 2026-11-09.) |
| Headphone jack | Untested |  |
| Microphone | Untested |  |
| Camera | Partial | Front camera RAW10 capture is available; rear cameras and application preview are not yet supported. |
| Camera flash | Untested |  |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works |  |
| Bluetooth | Works | Authenticated BLE keyboard/mouse input and A2DP/AVRCP/HFP headset profiles work. |
| USB networking (device mode) | Works | USB NCM provides SSH access. |
| USB host / OTG | Works | A phone-powered USB2 hub and keyboard work alongside four-lane DisplayPort; USB3 return and mouse input remain untested. (Verified on 2026-11-10.) |
| Mobile data | Works | LTE and 5G SA data carry HTTPS traffic. |
| Voice calls | Untested |  |
| SMS | Works | Incoming and outgoing SMS work through IMS. |
| GNSS (GPS) | Untested |  |
| NFC | Untested |  |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | Capacity, voltage and current telemetry are available; discharge behaviour remains untested. |
| Charging | Partial | USB charging reports positive battery current below full capacity; a complete charge cycle remains unverified. |
| Suspend | Partial | Retention-mode s2idle resumes with RTC wake when SS3 is disabled; enabling SS3 system collapse still causes resets. Low-power and long-duration standby are not yet verified. |
| Shutdown and reboot | Partial | Normal reboot works; power-off and subsequent cold boot remain untested. |
| CPU frequency scaling | Works | schedutil scales both clusters up to 3.5328 GHz and 4.32 GHz with boost enabled. Geekbench 7.0.0 Preview after CPU capacity and boost corrections: 2505 single-core / 8696 multi-core; [earlier baseline: 1660 / 8992](https://browser.geekbench.com/v7/cpu/831184). [Geekbench 6.7.1 Preview: 2811 single-core / 8822 multi-core](https://browser.geekbench.com/v6/cpu/19447918). [Geekbench 7](https://browser.geekbench.com/v7/cpu/832733) |
| Thermal management | Partial | Temperature sensors report values; sustained thermal throttling remains unverified. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | SSC accelerometer samples are available; physical orientation remains unverified. See [sensors](sensors.md). |
| Magnetometer | Untested |  |
| Ambient light sensor | Untested |  |
| Proximity sensor | Untested |  |
| Hall sensor (cover) | Untested |  |
| Vibration | Untested |  |
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
