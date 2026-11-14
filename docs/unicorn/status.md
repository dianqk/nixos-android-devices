# Support status: Xiaomi 12S Pro (unicorn)

[中文](status.zh.md) · [Device guide](README.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi 12S Pro (unicorn) | Qualcomm SM8475 (Snapdragon 8+ Gen 1) | Linux 7.3.4; hardware results from Linux 7.3-rc6 | 2026-11-17 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 8 | 8 | 3 | 22 | 1 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | U-Boot in boot_b boots systemd-boot and the installed Linux system; the ESP and root occupy the original userdata extent. |
| Generation update and rollback | Partial | EFI generation updates work without rewriting U-Boot; a complete rollback test is not documented. |
| RAM recovery | Partial | Independent recovery boot is verified; the complete USB SSH and storage workflow needs revalidation on the current kernel. |
| First installation from recovery | Untested | The Linux-only layout is implemented; the complete prepare-install and install-initial sequence is not documented as tested. |
| Reboot to bootloader or recovery | Untested | Bootloader and recovery reboot targets are configured; both transitions need hardware verification. |
| Internal storage | Works | UFS boot and bounded file I/O passed; linux-boot and linux are split from userdata. |
| microSD card | N/A | The phone has no microSD slot. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | The 1440×3200 DSC panel displays at 24/30/40/60/90/120 Hz; 60 Hz is preferred. |
| Backlight and screen off | Works | Brightness changes, screen off/on and opt-in 60↔120 Hz switching were verified; other active transitions remain experimental. |
| Touchscreen | Works | The ST FingerTipS SPI driver provides multitouch. |
| Hardware buttons | Partial | Console volume, short power press for screen off/on and long press for shutdown are implemented; desktop actions need separate configuration and testing. |
| External display (USB-C DisplayPort) | Untested | The USB-C DisplayPort board path is unverified and is not enabled. |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Partial | Adreno 730 renders through Freedreno; complete on-screen GL benchmark validation is not documented. |
| Vulkan acceleration | Untested | On-screen Vulkan rendering has not been verified. |
| Hardware video decode | Untested | Hardware video playback has not been verified. |
| Speaker | Works | Internal speaker playback works with separately provisioned private firmware, calibration and Music data. |
| Headphone jack | Broken | USB-C analogue headset routing is incomplete; digital USB-C accessories are also unverified. |
| Microphone | Works | Internal microphone recording and playback were verified with the private audio runtime inputs. |
| Camera | Partial | JN1 ultra-wide and telephoto capture RAW10; front/main identification NACKs. Bayer order, exposure, software ISP, autofocus and OIS remain unverified or unimplemented. |
| Camera flash | Untested | Flash operation has not been verified. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | 2.4/5 GHz association, traffic and reconnect passed; NetworkManager supplies a stable local address. |
| Bluetooth | Partial | Pairing, headset playback and RFCOMM transfers work with a separately provisioned factory address; firmware-download timeouts can occur. HFP and concurrent Wi-Fi/audio remain unverified. |
| USB networking (device mode) | Partial | NCM and optional ACM are configured; physical USB enumeration, DHCP and SSH need revalidation with the current role manager. |
| USB host / OTG | Untested | Firmware-negotiated USB2 host mode is implemented; peripheral operation and VBUS supply remain unverified. |
| Mobile data | Untested | Cellular data has not been verified. |
| Voice calls | Broken | No voice-call integration is provided. |
| SMS | Untested | SMS has not been verified. |
| GNSS (GPS) | Untested | No location fix has been verified. |
| NFC | Untested | An SN NCI reader-mode driver is included; tag and reader operation are unverified. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Untested | Board-specific ADSP battery telemetry is implemented; a full discharge validation is not documented. |
| Charging | Untested | Authentication and input telemetry are implemented; a full charge cycle, charge-pump operation and the 120 W peak remain unverified. |
| Suspend | Partial | Bounded suspend/resume checks passed; standby power and complete peripheral recovery remain unverified. |
| Shutdown and reboot | Untested | Orderly shutdown is requested by the console key service; power-off, cold boot and repeated reboot acceptance remain incomplete. |
| CPU frequency scaling | Untested | Frequency scaling under load on every CPU cluster has not been verified. |
| Thermal management | Untested | Thermal cooling is configured; sustained-load throttling has not been verified. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | Dedicated SSC data and userspace sensor integration remain incomplete. |
| Magnetometer | Untested | Sensor readings have not been verified. |
| Ambient light sensor | Untested | Light readings and automatic brightness have not been verified. |
| Proximity sensor | Untested | Sensor presence and readings have not been established. |
| Hall sensor (cover) | Untested | Sensor presence has not been established. |
| Vibration | Untested | An AW86927 force-feedback driver is included; physical vibration is unverified. |
| Fingerprint reader | Broken | No fingerprint driver or service is included. |

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
