# 同槽位 boot-choice EFI helper

[English](README.md)

`boot-choice-efi` 是 `hardware.dodge.bootChoice.enable` 使用的 AArch64 UEFI
应用。加载选定的 NixOS 条目前，它校验早期 boot-choice 上下文和 Linux ESP 身份。
它不切换 A/B 槽、不写 EFI 策略，也不提供 recovery shell。

使用 `nix build .#boot-choice-efi` 构建。helper 必须与固件和自有 boot image
匹配；主机检查不能证明硬件、EFI 运行时或断电验收。完整流程和安全限制见公开的
[boot-choice 指南](../../docs/boot-choice.zh.md)。
