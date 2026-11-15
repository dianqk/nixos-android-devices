# Support status: Xiaomi Mi Pad 4 LTE (clover)

[中文](status.zh.md) · [Device guide](README.md) · [Hardware support](hardware.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi Mi Pad 4 LTE (clover) | Qualcomm SDM660 | Nixpkgs Linux 7.3 with Clover patches | 2026-11-01 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 10 | 5 | 6 | 17 | 4 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (boot) → systemd-boot on FAT `system` → Linux 7.3, root on `userdata`. |
| Generation update and rollback | Works | Update and rollback booted the selected generation; `boot` stayed unchanged. |
| RAM recovery | Works | ABL boots `recovery`: the same U-Boot with a FIT ramdisk (LZMA kernel, xz initrd) under ABL's 35 MiB ramdisk limit. SSH host key persists. |
| First installation from recovery | Works | `format-root`, `prepare-boot` and `install-initial` (including resume) installed and booted the system. |
| Reboot to bootloader or recovery | Works | Reboot arguments `bootloader` and `recovery` reach ABL fastboot and RAM recovery. The EFI menu entries are untested. |
| Internal storage | Works | eMMC HS400; the stock GPT is unchanged. |
| microSD card | Untested | The SDHCI controller is enabled; no card test. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | NT51021 DSI panel at 1200×1920 through MSM DRM. (Verified on 2026-10-30.) |
| Backlight and screen off | Untested | Brightness changes are unchecked. Software reports DPMS off after 60 s at the login screen. |
| Touchscreen | Untested | FT5x06 passed on an earlier image; the current Niri session needs a check. |
| Hardware buttons | Untested | Power, volume and Hall inputs enumerate; their desktop actions are untested. |
| External display (USB-C DisplayPort) | N/A |  |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Untested | Freedreno (Adreno 512) loads; on-screen rendering and performance are not yet verified. |
| Vulkan acceleration | Broken | Mesa Turnip does not support Adreno 5xx. |
| Hardware video decode | Untested | Venus creates its V4L2 devices; decoding is not yet tested. |
| Speaker | Broken | The SDM660 UCM has no speaker route. |
| Headphone jack | Untested | UCM headphone routes exist; playback is unverified. |
| Microphone | Untested | UCM microphone routes exist; capture is unverified. |
| Camera | Broken | No capture pipeline is integrated. |
| Camera flash | N/A |  |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Partial | WCN3990 connects at VHT80 2x2 and survives disconnect/reconnect cycles (iwd needs ControlPortOverNL80211=false). Under severe memory pressure with Wi-Fi connected the tablet resets; the modem that runs the WLAN firmware sometimes restarts several times after boot, delaying Wi-Fi by up to about 2 minutes. |
| Bluetooth | Partial | Discovery, SSP pairing with an authenticated key and L2CAP echo work; no audio or input profile was tested, and encryption is not shown. |
| USB networking (device mode) | Works | NCM with DHCP and SSH in the system and recovery. |
| USB host / OTG | Untested | VBUS output and host enumeration are unverified. |
| Mobile data | Broken | The modem runs, but no IPA or cellular data path is enabled. |
| Voice calls | Untested | No telephony stack; voice support of the LTE model is not established. |
| SMS | Broken | No SMS path is enabled. |
| GNSS (GPS) | Untested | No location fix or userspace integration. |
| NFC | N/A |  |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | PMI8998 fuel gauge readings are plausible; a discharge is not yet tested. |
| Charging | Partial | Charges from a USB host port and reports external power; a full charge cycle is not yet tested. |
| Suspend | Broken | An s2idle test with an RTC wake alarm did not return within 5 minutes; the system policy disables suspend. |
| Shutdown and reboot | Partial | Reboot works repeatedly; power-off and cold boot are not yet verified. |
| CPU frequency scaling | Works | OSM with closed-loop CPRh voltage control scales both clusters with schedutil across the full table: silver up to 1843.2 MHz, gold up to 2208 MHz. Geekbench 7 389 single-core / 1036 multi-core: [Geekbench 7](https://browser.geekbench.com/v7/cpu/770857) |
| Thermal management | Works | Under sustained all-core load the CPU cooling maps throttle both clusters at the 70 °C passive trip; the GPU uses devfreq. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | No sensor is exposed to Linux (no IIO device). |
| Magnetometer | Untested | No sensor is exposed to Linux (no IIO device). |
| Ambient light sensor | Untested | No sensor is exposed to Linux (no IIO device). |
| Proximity sensor | Untested | Sensor presence is not established. |
| Hall sensor (cover) | Untested | The Hall input enumerates; cover behavior is untested. |
| Vibration | Untested | Vibration motor presence is not established. |
| Fingerprint reader | N/A |  |

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
