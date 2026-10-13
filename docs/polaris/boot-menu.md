# Use the Polaris boot menu

[Device guide](README.md) · [First installation](first-install.md) · [中文](boot-menu.zh.md)

An installed EFI system keeps NixOS generations in FAT `/boot`. Ordinary
system updates add generations there; they do not rewrite U-Boot in physical
`boot`. Keep independent RAM recovery available for a failed startup.

The module also enables [power and special reboot actions](../boot-actions.md).
Bootloader/recovery entries need updated U-Boot and ask for confirmation; their
hardware behavior remains unverified.

## Choose a generation

At the systemd-boot menu, select the desired NixOS generation and confirm.
The firmware maps volume up/down to navigation and a short power press to Enter.
Physical button operation is configured but has not been verified on the panel;
USB ACM/serial console provides an alternative where available. Holding volume
down during U-Boot enters its own utility menu; select “Boot NixOS” to reach the
systemd-boot generation menu. A long power hold is handled by the PMIC.

From running Linux, inspect installed entries with:

```sh
bootctl list
ls /boot/loader/entries
```

If the new generation fails, select an older one on the next boot. If no usable
entry remains, boot RAM recovery and use the [deployment tool](../../pkgs/mobile-device/README.md).
The root filesystem and EFI files must match the same system closure.

## Change timeout and retained generations

Set these in your own NixOS configuration:

```nix
{
  boot.loader.timeout = 10;
  boot.loader.systemd-boot.configurationLimit = 10;
}
```

Build and install the change with `nixos-rebuild boot`, then reboot. Ensure the
FAT partition has space for the retained kernel/initrd/DTB files and one update.
The default is 10 generations; the EFI installer refuses insufficient capacity.
Do not edit generated entry files as your configuration source of truth.

The menu uses U-Boot's 24×48 bitmap glyphs. Linux `console.font`, compositor settings
and TrueType fonts do not change it. There is no runtime font-size option in the
current firmware; changing glyph size requires rebuilding and validating U-Boot.
See the [implementation reference](boot-menu-reference.md) for renderer, key and
details.
