# Clover LTE 首次安装

[English](first-install.md)

请先阅读[统一 U-Boot 安装流程](../u-boot-install.zh.md)和[本机配置](README.zh.md)。

准备好以下分区后，使用[共享首次安装器](../initial-install.zh.md)导入闭包、安装 EFI 并写入匹配的 U-Boot 固件。

Clover 使用物理 system 作为 FAT `/boot`、userdata 作为 ext4 根；无 A/B。U-Boot 尚未真机验证。在 `hardware.clover.storageRoles` 填入本机实测的 `userdata`、`boot`、`recovery` 和 `misc` 分区之前，recovery 会拒绝 root、firmware、recovery 和 misc 操作。FAT `/boot` 是 eMMC 上唯一的 `system` 分区。

临时启动 recovery、通过 ACM/NCM 进入、测量分区以及受检查的 `format-root` 和 `prepare-boot` 命令见 [Clover 存储准备](manual-storage.zh.md)。
