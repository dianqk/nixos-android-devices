# 首次安装系统

[English](initial-install.md) · [U-Boot 和存储准备](u-boot-install.zh.md)

`mobile-device recovery install-initial` 从 RAM recovery 安装 NixOS 闭包和 EFI
代际。先按设备指南准备空的 ext4 根和 FAT ESP。主机工具和 RAM recovery 都须支持
独立安装系统。

通常先[单独安装 U-Boot](u-boot-install.zh.md)，再通过设备支持的方式进入 RAM recovery，
最后安装系统。如果已安装兼容的 U-Boot，可继续使用。能够独立启动 RAM recovery 的设备
也可先安装系统，再刷写固件。启动已安装的系统前，应确认设备已有兼容的 U-Boot。

从同一锁定配置构建 `system` 和 `bootstrap-info`，并确认 RAM recovery 的 SSH 可达。
输出定义见[配置指南](configuration.zh.md)。x86_64 和 AArch64 Linux 主机均可发起安装。

以下命令在构建主机执行，将路径和 recovery SSH 别名替换为实际值：

```sh
SYSTEM=$(readlink -f result-system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info --execute
```

第一条检查本地元数据和 recovery 前置条件。`--execute` 再次检查，传输完整闭包，
导入 Nix 注册信息，校验闭包成员和 NAR 哈希，并确认 fstab 中 `/` 和 `/boot`
指向已检查的分区。随后创建初始 profile，运行标准 NixOS EFI 安装器并核对选定代际的
EFI 条目。该操作写入已准备好的根和 ESP。分区、格式化、固件刷写和重启均为独立操作。

`bootstrap-info` 提供空根所需的闭包注册信息和大小。已有系统使用 `deploy` 更新。

recovery 守护进程通过 `recovery status` 和 `recovery task TASK_ID` 报告结果。
安装失败后留在 recovery 查看错误。`/var/lib/mobile-efi-preparation/pending`
标记会阻止 recovery 选择正常启动。若已完整传输，可带相同的系统和 bootstrap-info
加 `--resume` 重试。传输未完成时，重新准备空根后安装。

Asphalt 首次正常启动前，按设备指南完成[经检查的 B DTBO 流程](asphalt/first-install.zh.md#擦除-b-dtbo-并启动)。
