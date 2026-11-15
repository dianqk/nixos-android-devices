# Support status: Xiaomi Mi MIX 2S (polaris)

[中文](status.zh.md) · [Device guide](README.md) · [Hardware support](hardware.md)

Generated from [`status.toml`](status.toml) by `tools/status-pages.py`; edit that file and regenerate.

| Device | SoC | Kernel | Last updated |
| --- | --- | --- | --- |
| Xiaomi Mi MIX 2S (polaris) | Qualcomm SDM845 | Nixpkgs Linux 7.3 with Polaris patches | 2026-10-30 |

## Summary

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 9 | 12 | 4 | 15 | 2 |

## Boot and storage

| Item | Status | Notes |
| --- | --- | --- |
| Installed boot (U-Boot, systemd-boot, Linux) | Works | ABL → U-Boot (boot) → systemd-boot on FAT `system` → Linux EFI stub, root on `userdata`. |
| Generation update and rollback | Works | Update, rollback and restore each booted the selected generation; `boot` stayed unchanged. |
| RAM recovery | Partial | The installed recovery boots independently and served storage operations over ADB; the current SSH-based recovery is not hardware-tested. |
| First installation from recovery | Partial | Recovery prepared FAT `/boot` and installed EFI files and U-Boot that boot; installation onto an empty root is untested. |
| Reboot to bootloader or recovery | Works | The systemd-boot bootloader and recovery entries work; a Linux reboot with the `bootloader` argument reached fastboot. |
| Internal storage | Works | UFS 2.1 holds ext4 `userdata` and FAT `system`; the stock GPT is unchanged. |
| microSD card | N/A | The MIX 2S has no microSD slot. |

## Display and input

| Item | Status | Notes |
| --- | --- | --- |
| Built-in display | Works | NT35596S DSI panel at 1080×2160 through MSM DRM, including the first frame after boot. (Verified on 2026-09-15.) |
| Backlight and screen off | Partial | The panel turns off and on with the power key; brightness changes on the panel are not yet verified. (Verified on 2026-10-04.) |
| Touchscreen | Works | Touch unlock and desktop input work; rotated input mapping in the current Niri session is not separately verified. (Verified on 2026-09-15.) |
| Hardware buttons | Partial | The power key toggles and reboots the charging screen; desktop and volume-key actions are not yet verified. (Verified on 2026-10-04.) |
| External display (USB-C DisplayPort) | Untested | DisplayPort alternate mode on this USB-C port is not established. |

## Graphics and multimedia

| Item | Status | Notes |
| --- | --- | --- |
| OpenGL ES acceleration | Untested | Freedreno (Adreno 630) renders the desktop and scored 663 in glmark2; on-screen output is not yet verified. |
| Vulkan acceleration | Untested | Turnip scored 1407 in vkmark; on-screen output is not yet verified. |
| Hardware video decode | Works | H.264 and HEVC 8-bit play in mpv through Venus V4L2; HEVC Main 10 needs the VA-API path. (Verified on 2026-09-23.) |
| Speaker | Partial | Video audio was heard from the speakers; audibility after the latest UCM fix is not yet verified. (Verified on 2026-09-23.) |
| Headphone jack | N/A | No 3.5 mm jack. |
| Microphone | Broken | Capture streams open, but the recorded samples are silent. |
| Camera | Partial | Front OV5675 and rear main IMX363 capture through libcamera; the auxiliary rear sensor, autofocus and tuning are missing. (Verified on 2026-09-27.) |
| Camera flash | Untested | No flash control has been tested. |

## Connectivity

| Item | Status | Notes |
| --- | --- | --- |
| Wi-Fi | Works | WCN3990 connects at 5 GHz and 160 MHz, gets DHCP, carries traffic and reconnects; suspend recovery is untested. |
| Bluetooth | Partial | Interoperates with a real device; pairing with an audio or input profile is not covered. |
| USB networking (device mode) | Works | NCM with DHCP and SSH in the system, including system updates over USB. |
| USB host / OTG | Untested | Host mode is configured; VBUS output and device enumeration are unverified. |
| Mobile data | Broken | The modem runs for Wi-Fi support, but ModemManager and a cellular data path are not enabled. |
| Voice calls | Broken | No telephony stack or call-audio path is enabled. |
| SMS | Broken | No SMS path is enabled. |
| GNSS (GPS) | Untested | No location fix or userspace integration. |
| NFC | Untested | No NFC device or test is recorded. |

## Power and performance

| Item | Status | Notes |
| --- | --- | --- |
| Battery status | Partial | PMI8998 fuel gauge readings are plausible; a full discharge is not yet tested. |
| Charging | Partial | Charges at upstream SMB2 limits (1 A) and has an off-mode charging screen; termination and a complete charge cycle are not yet verified. |
| Suspend | Untested | Suspend, power saving and resume are not yet tested. |
| Shutdown and reboot | Partial | Reboot works and shutdown on charger power enters the charging screen; cold boot from the power key is untested. |
| CPU frequency scaling | Partial | Both clusters expose `schedutil` policies (up to 1.77 and 2.65 GHz); load following is not measured. |
| Thermal management | Partial | Thermal zones report plausible temperatures under load; throttling is untested. |

## Sensors and feedback

| Item | Status | Notes |
| --- | --- | --- |
| Accelerometer (auto-rotation) | Untested | The sensor DSP delivers three-axis samples to the IIO proxy; desktop rotation is not yet verified. |
| Magnetometer | Untested |  |
| Ambient light sensor | Untested |  |
| Proximity sensor | Untested |  |
| Hall sensor (cover) | Untested | Sensor presence is not established. |
| Vibration | Untested | No vibration driver or test is recorded. |
| Fingerprint reader | Untested | No fingerprint driver or test is recorded. |

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
