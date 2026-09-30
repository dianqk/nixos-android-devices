# Sheng recovery 操作

[English](recovery.md) · [设备概览](README.zh.md)

本页介绍进入 RAM recovery、离线部署系统和更新 `recovery_b`。
日常系统更新见 [USB SSH 指南](../usb-signaller.md)；
首次安装与固件布局见[安装准备](first-install.zh.md)。

`SYSTEM_HOST` 和 `RECOVERY_HOST` 是你的 OpenSSH 主机配置名称，两者使用各自固定的
主机密钥，配置方式见[连接指南](../recovery.md)。`--target` 选择 SSH 目标；
`--serial` 仅用于 fastboot。下面的 `mobile-device` 写入命令省略 `--execute` 时只检查。

## 进入 RAM recovery

以下脚本路径相对于本仓库根目录；在构建电脑上运行 `mobile-device`。

```sh
mobile-device recovery --target SYSTEM_HOST enter \
  --script devices/sheng/request-recovery.sh \
  --support-script devices/sheng/slot-gate.sh --support-env SHENG_SLOT_GATE \
  --execute
mobile-device recovery --target RECOVERY_HOST status
```

请求脚本检查已安装的 Sheng 系统、引导器提供的 B 槽证据、UFS/GPT 身份和 4 MiB
`misc` 分区。它仅将 BCB 的前 32 字节命令改为 `boot-recovery`，比较整个分区后，
由主机工具发起普通重启。遇到未知 BCB 命令时拒绝覆盖。

## 从 RAM recovery 更新

```sh
mobile-device recovery --target RECOVERY_HOST deploy tmp/systemd-artifacts/system
mobile-device recovery --target RECOVERY_HOST deploy tmp/systemd-artifacts/system --execute
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

选择与配置的 root label、hostname 一致的系统。Recovery 导入缺少的闭包、选择新一代
系统，并将 EFI 文件安装到 FAT `/boot`，U-Boot 固件保持不变。已安装的其他系统代仍可从引导菜单选择。
存在未完成的部署事务时，必须恢复完成后才能启动系统。

## 更新 recovery 自身

在当前 recovery 完全运行于 RAM、所有块设备文件系统均已卸载且 swap 已停用时执行：

```sh
mobile-device recovery --target RECOVERY_HOST install-image tmp/systemd-artifacts/recovery \
  --installer devices/sheng/install-recovery.sh \
  --partition /dev/disk/by-partlabel/recovery_b \
  --support-script devices/sheng/check-recovery-image.sh --support-env SHENG_IMAGE_CHECK \
  --execute
mobile-device recovery --target RECOVERY_HOST reboot recovery --execute
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

辅助脚本在写入前检查镜像。Recovery 同时提供
`sheng-install-recovery` 和 `sheng-check-recovery-image`；设备端可通过
`recovery install-recovery --check|--execute IMAGE SHA256 EXPECTED_OLD_SHA256`
调用安装器。

安装器固定写入 `recovery_b`，检查 B 槽来源、Sheng/UFS/GPT 身份、容量、传输哈希和
原分区哈希。仅接受完整 100 MiB Android v0 镜像，要求附加 DT 的根 compatible 为
Sheng、启动参数指定 RAM recovery，并包含本仓库格式的无签名 AVB recovery 哈希描述符。
写入后验证整个分区 SHA-256。截短镜像、系统 boot 镜像、其他设备镜像或过期的原分区
哈希均在写入前拒绝。这些检查验证格式和完整性，不证明发布者身份。

原厂 `vbmeta_b` 即使在普通 B 槽启动时也会检查 `recovery_b`。必须保留完整 AVB footer，
不要只写入较短的 payload 或修改 vbmeta 标志。Recovery 更新不选择槽位，也不标记
启动成功；未启用自动 Linux 启动成功确认。
