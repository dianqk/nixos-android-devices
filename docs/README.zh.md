# 安装与使用

[English](README.md) · [项目首页](../README.zh.md)

从[配置指南](configuration.zh.md)创建自己的系统，再按设备准备存储和引导。
四个型号均使用 U-Boot → systemd-boot → Linux。

## 安装

| 设备 | FAT `/boot` | ext4 根 | 固件分区 | 指南 |
| --- | --- | --- | --- | --- |
| Asphalt / Y700 2023 | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [配置](asphalt/README.zh.md) · [首装准备](asphalt/first-install.zh.md) |
| Polaris / MIX 2S | 物理 `system` | `userdata` | `boot`，无 A/B | [配置](polaris/README.zh.md) · [首装](polaris/first-install.zh.md) |
| Sheng / 平板 6S Pro | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [配置](sheng/README.zh.md) · [首装准备](sheng/first-install.zh.md) |
| Clover / 平板 4 LTE | 物理 `system` | `userdata` | `boot`，无 A/B | [配置](clover/README.zh.md) · [首装准备](clover/first-install.zh.md) |

四款设备均可在分区准备完成后使用[首次安装器](initial-install.zh.md)。
Clover 需要实测存储契约，其 U-Boot 尚未真机验证。Asphalt/Sheng 的 Linux
分区取自原 userdata 分配范围，保留 Android A 和 super。

完整步骤见 [U-Boot 安装指南](u-boot-install.zh.md)。

## 日常更新与排障

- 配置用户、桌面、应用和服务：[配置指南](configuration.zh.md)。
- USB 网络、SSH 和 `nixos-rebuild boot`：[连接与更新](usb-signaller.md)。
- 选择 Polaris 代际与菜单设置：[启动菜单](polaris/boot-menu.md)。
- 启动失败、挂载目标文件系统和离线更新：[RAM recovery](recovery.md)。
- 闭包传输与受检查的设备操作：[mobile-device](../pkgs/mobile-device/README.zh.md)。
- Sheng recovery 镜像维护：[recovery 操作](sheng/recovery.zh.md)。

普通系统更新维护 FAT `/boot` 上的内核、initrd、DTB 和代际条目。
U-Boot 固件与 recovery 镜像单独更新。

## 支持等级

支持等级以本开源仓库提供的示例为准：

| 等级 | 支持目标 | 验证要求 |
| --- | --- | --- |
| Tier 1 | 可运行 + 可构建 + 可 eval（求值） | 必须有独立的实体设备专门使用本仓库示例进行验证，并通过构建、求值与运行验证 |
| Tier 2 | 可构建 + 可 eval（求值） | 验证构建与求值，不承诺设备运行验证 |
| Tier 3 | 可 eval（求值） | 验证求值，不承诺构建或设备运行验证 |

当前没有 Tier 1 设备。已测试的功能和已知限制见各设备的硬件页面。

## 固件来源与许可证

设备专用固件的来源与用途见各设备指南。通用固件与无线法规数据来自 Nixpkgs 的
`linux-firmware` 和 `wireless-regdb`。固件二进制文件遵循其上游许可证，不适用
本项目的 MIT 或内核 GPL-2.0 许可证；本仓库不保存设备固件二进制副本。
