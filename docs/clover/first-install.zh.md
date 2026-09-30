# Clover LTE 首次安装

请先阅读[统一 U-Boot 安装流程](../u-boot-install.zh.md)和[本机配置](README.zh.md)。

准备好以下分区后，使用[共享首次安装器](../initial-install.zh.md)导入闭包、安装 EFI 并写入匹配的 U-Boot 固件。

Clover 使用物理 system 作为 FAT `/boot`、userdata 作为 ext4 根；无 A/B。U-Boot 尚未真机验证。实测的 `hardware.clover.storageRolesFile` 必须包含 `userdata`、`system` 和 `boot` 角色；默认未配置的契约会拒绝安装。

从临时启动 recovery、通过 ACM/NCM 进入，到核对实测 eMMC 契约及手动格式化的命令见[Clover 手动分区示例](manual-storage.zh.md)。示例也说明与 `format-root` 自动命令的差异。
