# Polaris EFI console implementation

The installed chain is Android firmware → U-Boot → systemd-boot → Linux EFI.
The Android boot header wraps U-Boot; only RAM recovery boots Linux directly
through the Android firmware. U-Boot lives in physical `boot`. Physical `system`
is FAT32 mounted at `/boot`, with `EFI/BOOT/BOOTAA64.EFI`, the standard NixOS
`EFI/nixos/` payloads and `loader/entries/` generations. Userdata is plain ext4.

## Display and customization

systemd-boot 261.2 runs before Linux, through UEFI Simple Text Output/Input; this
is not a Linux tty/getty. On this firmware U-Boot renders text onto the inherited
1080×2160 framebuffer and also sends console output over serial/USB ACM.
The built U-Boot configuration selects `VIDEO_FONT_8X16` and the local
`VIDEO_FONT_SCALE=3`, yielding 24×48 glyphs and a 45×45 character grid. TrueType and runtime font selection are disabled. Linux `console.font` cannot change this menu.

[loader.conf](https://github.com/systemd/systemd/blob/v261.2/man/loader.conf.xml)
provides timeout, default entry, console mode and entry visibility settings.
It does not provide a graphical theme engine, custom widgets or arbitrary font
files. The [menu implementation](https://github.com/systemd/systemd/blob/v261.2/src/boot/boot.c)
uses firmware text rendering. A custom graphical menu requires changing that
implementation or using another EFI frontend, with corresponding generation
and input integration work.

`console-mode` selects a firmware text mode; it is not a portable font-size
control. In this U-Boot version, `efi_cout_set_mode()` changes the logical text
mode and clears the screen, without scaling glyphs. `query_vidconsole()` only uses video-console dimensions when `stdout`
starts with `vidconsole`; the environment uses `vidconsole,serial,usbacm`
(USB ACM is added during preboot).
Do not assume `console-mode max` makes the phone's text bigger. The explicit
bitmap scale sets glyph size before EFI queries the display. Native panel
resolution and Linux fonts remain unchanged.
See [U-Boot EFI console source](https://github.com/u-boot/u-boot/blob/a06e89ab05eaa2b8344d521319399333cd760ae5/lib/efi_loader/efi_console.c).

## Physical keys

The compiled firmware enables `BUTTON_KEYBOARD`, `BUTTON_GPIO`,
`BUTTON_QCOM_PMIC` and `BUTTON_REMAP_PHONE_KEYS`. `button-kbd` is included in
`stdin`, alongside serial and USB ACM. Upstream maps:

| Phone key | EFI menu input |
| --- | --- |
| Volume up | Up |
| Volume down | Down |
| Power, short press | Enter |

See the [upstream mapping](https://github.com/u-boot/u-boot/blob/a06e89ab05eaa2b8344d521319399333cd760ae5/drivers/button/button-uclass.c)
and [systemd-boot menu keys](https://systemd.io/BOOT/).
Polaris DT describes volume up on PM8998 GPIO 6, volume down on PM8998 resin,
and power on the PM8998 power-key input. Holding volume down during U-Boot
startup requests **U-Boot's own** recovery/utility menu; select “Boot NixOS”
to reach systemd-boot. Short navigation presses in systemd-boot select generations.

Automatic EFI boot and generation rollback have been verified. Physical button
navigation and on-panel font readability remain untested; see the
[user guide](boot-menu.md). A long power-key hold remains subject to the PMIC's
hardware behavior.
