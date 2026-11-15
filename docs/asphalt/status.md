# Support status: Lenovo Legion Y700 2023 (TB320FC) (asphalt)

[中文](status.zh.md) · [Device guide](README.md) · [Hardware support](hardware.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Lenovo Legion Y700 2023 (TB320FC) (asphalt) | Qualcomm SM8475 | Nixpkgs Linux 7.3-rc6 with Asphalt patches | 2026-10-30 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 10 | 13 | 0 | 16 | 3 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (`boot_b`) → systemd-boot on the FAT `linux-boot` ESP → Linux, root on ext4 `linux`; slot A and super stay untouched. |
| Generation update and rollback | Works | A new generation booted by default and a rollback booted the older one; `boot_b` stayed unchanged. |
| RAM recovery | Works | Recovery in `recovery_b` boots via the OEM bootloader; USB SSH, offline filesystem checks and generation deploy work. |
| First installation from recovery | Partial | The installed system was set up from RAM recovery on one tablet; the current `install-initial` flow on a fresh tablet is unverified. |
| Reboot to bootloader or recovery | Partial | Recovery reaches the OEM bootloader; rebooting the installed system into recovery is unverified. |
| Internal storage | Works | UFS holds the ext4 root and FAT ESP across reboots and updates; a 75 MHz clock limit is the default. |
| microSD card | Partial | An SDXC card was detected at SDR104 and mounted read-only; writes and hot-plug are untested. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | NT36523N dual-DSI panel at 1600×2560, 120 Hz through MSM DRM. (Verified on 2026-10-03.) |
| Backlight and screen off | Partial | The panel turns off and on with the power key in the charger screen; desktop brightness changes are not yet verified. (Verified on 2026-10-04.) |
| Touchscreen | Works | Novatek touch maps correctly in Niri, including all four rotations. (Verified on 2026-10-03.) |
| Hardware buttons | Partial | The power key works in the charger screen; volume keys and desktop actions are not yet verified. (Verified on 2026-10-04.) |
| External display (USB-C DisplayPort) | Untested | A 3840×2160 60 Hz DP output trains and is driven by the compositor; the picture on a monitor is not yet verified. |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Partial | The Niri desktop renders through Freedreno (Adreno 730); glmark2 ran only in automated checks and one GMU timeout fault is unexplained. (Verified on 2026-10-03.) |
| Vulkan acceleration | Untested | Turnip renders vkcube in automated checks; on-screen output is not yet verified. |
| Hardware video decode | Untested | Iris decodes 180-second 1080p H.264/HEVC 8-bit through V4L2 and VA-API in automated checks; on-screen playback is not yet verified. |
| Speaker | Untested | The CS35L45 speaker sink exists; a heavily attenuated playback test produced no audible sound. |
| Headphone jack | Untested | Headphone jack presence is not established. |
| Microphone | Untested | Capture is untested. |
| Camera | Works | Scene photos from all three cameras through libcamera's software ISP; tuning is generic and autofocus is missing. (Verified on 2026-09-27.) |
| Camera flash | Untested | Flash LED presence is not established; no flash control is implemented. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | WCN6855 associates at two-stream HE80 rates, gets DHCP and carries SSH traffic. |
| Bluetooth | Partial | Discovery and unpaired L2CAP echo work; pairing has not succeeded and profiles are untested. |
| USB networking (device mode) | Works | NCM with DHCP and SSH in the system and recovery, at USB2 and USB3 speeds. |
| USB host / OTG | Untested | No host-mode session with an attached device has been tested. |
| Mobile data | N/A | TB320FC is the Wi-Fi model without a cellular modem. |
| Voice calls | N/A | TB320FC is the Wi-Fi model without a cellular modem. |
| SMS | N/A | TB320FC is the Wi-Fi model without a cellular modem. |
| GNSS (GPS) | Untested | GNSS hardware presence is not established. |
| NFC | Untested | NFC hardware presence is not established. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | Capacity, voltage and current follow a discharge; `power_now` is bogus and `charge_counter` is quantized. |
| Charging | Partial | Off-mode charging works from a USB host near full charge; a full charge cycle and fast charging are unverified. |
| Suspend | Partial | s2idle reaches deep sleep and resumes; only the power key wakes it, and Bluetooth failed after one of two resumes. |
| Shutdown and reboot | Partial | Reboot and power-off usually complete; a USB gadget teardown hang and slow service stops remain open. |
| CPU frequency scaling | Partial | Three `schedutil` policies change frequency under load; performance is not yet benchmarked. |
| Thermal management | Partial | Thermal zones report plausible temperatures; throttling is untested. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Works | SSC accelerometer drives Niri auto-rotation in all four directions. (Verified on 2026-10-03.) |
| Magnetometer | Untested | The MMC56x3 sensor is present in SSC; readings are unverified. |
| Ambient light sensor | Untested | The STK3A5x sensor is present in SSC; readings are unverified. |
| Proximity sensor | Untested | The STK3A5x sensor is present in SSC; readings are unverified. |
| Hall sensor (cover) | Untested | The BU52053NVX Hall sensor is present in SSC; cover behavior is untested. |
| Vibration | Untested | Stock vendor files reference two haptic drivers; no Linux haptics integration is tested. |
| Fingerprint reader | Untested | Fingerprint reader presence is not established. |

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
