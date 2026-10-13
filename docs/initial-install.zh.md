# 首次安装

[English](initial-install.md) · [存储准备](u-boot-install.zh.md)

`mobile-device recovery install-initial` 为 Asphalt、Polaris、Sheng、Clover
安装初始 EFI 系统，并检查设备身份、槽位和分区。

先按设备指南准备空 ext4 根与 FAT `/boot`：
[Asphalt](asphalt/first-install.zh.md)、[Polaris](polaris/first-install.zh.md)、
[Sheng](sheng/first-install.zh.md)、[Clover](clover/first-install.zh.md)。
此命令不会创建分区或格式化。Clover 需要 `userdata`、`boot`、`recovery` 和 `misc` 的实测存储角色，
其 U-Boot 仍未真机验证。Asphalt/Sheng 必须在 B 槽 recovery 中运行，只写 `boot_b`，
保留 Android A、super 和两个 recovery 分区。

从同一锁定配置构建 `system`、`bootstrap-info`、`recovery`，输出定义见
[配置指南](configuration.zh.md)，先确认 recovery 的 SSH 可达。
系统已包含匹配的 U-Boot 镜像，无需另行传入固件。
x86_64 和 AArch64 Linux 主机均可发起安装。

以下命令在构建主机执行，将路径和 recovery SSH 别名替换为实际值：

```sh
SYSTEM=$(readlink -f result-system)
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info
mobile-device recovery --target RECOVERY_HOST install-initial "$SYSTEM" \
  --bootstrap-info result-bootstrap-info --execute
```

第一条只校验本地元数据和 recovery 前置条件，不导入闭包或修改文件系统。
`--execute` 会再次检查，传输完整闭包、导入 Nix 注册信息、校验闭包成员和 NAR 哈希，
并确认 fstab 中 `/` 和 `/boot` 指向已检查的分区。随后创建初始 profile，运行标准
NixOS EFI 安装器。确认选定代际的 EFI 条目存在后，最后写入并回读校验匹配的 U-Boot。
安装成功不会自动重启。

`bootstrap-info` 提供构建时生成的闭包注册信息和大小，因为空根尚无可用的 Nix 数据库。
普通 `deploy` 更新已有系统，不执行这一步初始化，也不写入 U-Boot。

recovery 守护进程通过 `recovery status` 和 `recovery task TASK_ID` 报告结果。成功后检查 recovery 状态，再显式重启，
无需第二次刷写固件。失败时保留根中的 `/var/lib/mobile-efi-preparation/pending`，
阻止 recovery 正常启动选择。留在 recovery 检查原因，不要直接删除标记。
导入文件后根已非空，盲目重试会被拒绝；应明确修复或重新准备空根。
根、FAT 和固件的写入不是原子事务；boot 写入或回读失败时，重启前必须修复匹配的固件。

各设备的真机全新安装验证仍不完整，具体限制见设备指南。

Aurora 的实验性首次分区/安装见 [设备说明](aurora/README.zh.md#首次分区安装和增量更新实验性)。

Asphalt 首次正常启动 U-Boot 前，应返回 OEM fastboot，单独完成
[经检查的 B DTBO 擦除](asphalt/first-install.zh.md#擦除-b-dtbo-并启动)。
安装程序已经写入 `boot_b`，不要再次刷写 U-Boot；`install-initial` 不执行此 DTBO 准备。
