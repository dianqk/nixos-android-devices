# Same-slot boot-choice EFI helper

[中文](README.zh.md)

`boot-choice-efi` is an AArch64 UEFI application used by
`hardware.dodge.bootChoice.enable`. It validates the early boot-choice context and
the Linux ESP identity before loading the selected NixOS entry. It does not
switch A/B slots, write an EFI policy or provide a recovery shell.

Build it with `nix build .#boot-choice-efi`. The helper must match the firmware
and owned boot image; host checks do not establish hardware, runtime EFI or
power-loss acceptance. See the public [boot-choice guide](../../docs/boot-choice.md)
for the full workflow and safety limits.
