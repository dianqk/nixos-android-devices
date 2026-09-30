# Sheng 首次安装

请先阅读[统一 U-Boot 安装流程](../u-boot-install.zh.md)和[本机配置](README.zh.md)。

准备好以下分区后，使用[共享首次安装器](../initial-install.zh.md)导入闭包、安装 EFI 并写入匹配的 U-Boot 固件。

使用独立 1 GiB FAT linux-boot 与 ext4 linux，仅操作 B；保留 A 和 super。若从占满原分配范围的 Android userdata 划出空间，必须先安全缩小或准备重建其文件系统，不能仅缩小 GPT 来保留数据。

从临时启动 recovery、通过 ACM/NCM 进入，到按本机 GPT 手动准备分区的命令见[Sheng 手动分区示例](manual-storage.zh.md)。示例也说明与 `format-root` 自动命令的差异。
