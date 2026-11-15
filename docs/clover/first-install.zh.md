# Clover LTE 首次安装

[English](first-install.md)

请先阅读[统一 U-Boot 安装流程](../u-boot-install.zh.md)和[本机配置](README.zh.md)。

若尚无兼容的 U-Boot，按[独立固件流程](../u-boot-install.zh.md#单独构建和刷写-u-boot)
刷写。准备好以下分区后，用[共享首次安装器](../initial-install.zh.md)导入闭包并安装 EFI 代际。

Clover 使用物理 system 作为 FAT `/boot`、userdata 作为 ext4 根；无 A/B。U-Boot/EFI 安装、更新、回滚和独立 recovery 已在真机验证。recovery 按 eMMC 上唯一的原厂 GPT 名称找到 `userdata`、`system`、`boot`、`recovery` 和 `misc`；`hardware.clover.storageRoles` 中的实测值可选，填写后也必须一致。

临时启动 recovery、通过 ACM/NCM 进入、测量分区以及受检查的 `format-root` 和 `prepare-boot` 命令见 [Clover 存储准备](manual-storage.zh.md)。
