# Sheng recovery 操作

[English](recovery.md) · [设备概览](README.zh.md)

本页介绍进入 RAM recovery、离线部署系统和更新 `recovery_b`。
日常系统更新见 [USB SSH 指南](../usb-signaller.zh.md)；
首次安装与固件布局见[安装准备](first-install.zh.md)。

`RECOVERY_HOST` 是 recovery 的 OpenSSH 主机配置名称，使用其单独固定的主机密钥，配置方式见[连接指南](../recovery.zh.md)。`--target` 选择 SSH 目标；
`--serial` 仅用于 fastboot。下面的 `mobile-device` 写入命令省略 `--execute` 时只检查。

## 进入 RAM recovery

在已安装系统中重启，并在 systemd-boot 菜单中选择 **Reboot to recovery**
（见[启动动作](../boot-actions.zh.md)）。它启动 `recovery_b` 中的 NixOS RAM recovery，
不改变 Android A。随后连接：

```sh
mobile-device recovery --target RECOVERY_HOST status
```

## 从 RAM recovery 更新

```sh
mobile-device recovery --target RECOVERY_HOST deploy result-system
mobile-device recovery --target RECOVERY_HOST deploy result-system --execute
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

选择与配置的 root label、hostname 一致的系统。Recovery 导入缺少的闭包、选择新一代
系统，并将 EFI 文件安装到 FAT `/boot`，U-Boot 固件保持不变。已安装的其他系统代仍可从引导菜单选择。
存在未完成的部署事务时，必须恢复完成后才能启动系统。

## 更新 recovery 自身

在当前 recovery 完全运行于 RAM、所有块设备文件系统均已卸载且 swap 已停用时执行：

```sh
mobile-device recovery --target RECOVERY_HOST install-image result-recovery \
  --partition /dev/disk/by-partlabel/recovery_b \
  --execute
mobile-device recovery --target RECOVERY_HOST reboot recovery --execute
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST reboot system --execute
```

Rust daemon 是 recovery 写入操作的唯一后端；设备端可用
`recovery update-recovery IMAGE --check` 和 `--confirm`。
要求 B 槽、正确设备/分区身份、完整 100 MiB 镜像及有效的无签名 AVB recovery 哈希。
写入后核对整个分区；格式与完整性检查不证明发布者身份。

原厂 `vbmeta_b` 即使在普通 B 槽启动时也会检查 `recovery_b`。必须保留完整 AVB footer，
不要只写入较短的 payload 或修改 vbmeta 标志。Recovery 更新不选择槽位，也不标记
启动成功；未启用自动 Linux 启动成功确认。
