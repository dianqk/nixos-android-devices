# 安装与使用

[English](README.md) · [项目主页](../README.zh.md)

先按[配置指南](configuration.zh.md)创建系统，再为设备准备存储和启动文件。所有
支持的板都使用 U-Boot → systemd-boot → Linux；Dodge 使用同槽位 boot-choice
变体。

## 安装

| 设备 | FAT `/boot` | ext4 根 | 固件分区 | 指南 |
| --- | --- | --- | --- | --- |
| Asphalt / Y700 2023 | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [配置](asphalt/README.zh.md) · [准备安装](asphalt/first-install.zh.md) |
| Polaris / Mi MIX 2S | 物理 `system` | `userdata` | `boot`，无 A/B | [配置](polaris/README.zh.md) · [安装](polaris/first-install.zh.md) |
| Sheng / Pad 6S Pro | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [配置](sheng/README.zh.md) · [准备安装](sheng/first-install.zh.md) |
| Aurora / 小米 14 Ultra | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [配置与安装](aurora/README.zh.md) |
| Clover / 小米平板 4 LTE | 物理 `system` | `userdata` | `boot`，无 A/B | [配置](clover/README.zh.md) · [准备安装](clover/first-install.zh.md) |
| Marble / Redmi Note 12 Turbo | 独立 1 GiB `linux-boot` | `linux` | 仅 `boot_b` | [设备指南](marble/README.zh.md) |
| T880 / iPlay 80 mini Ultra | 未测量 | 未测量 | 未测量；仅实验性构建 | [设备指南](t880/README.zh.md) |
| Dodge / 一加 13 | 独立 `linux-boot` ESP | `linux` | 仅 `boot_b`；同槽位启动选择 | [设备指南](dodge/README.zh.md) |
| Unicorn / Xiaomi 12S Pro | 独立 1 GiB `linux-boot` | `linux`（全部 userdata） | `boot_b`；recovery 位于 `recovery_b` | [设备指南](unicorn/README.zh.md) |

完整顺序见 [U-Boot 安装](u-boot-install.zh.md)。Dodge 同槽位产品见
[boot-choice 指南](boot-choice.zh.md)。

## 更新与排障

- 用户、桌面、应用和服务：[配置](configuration.zh.md)。
- USB 网络、SSH 和 `nixos-rebuild boot`：[连接与更新](usb-signaller.zh.md)。
- 为 Wi-Fi 与基带准备校准快照：[基带校准快照](polaris/radio-snapshot.zh.md)。
- Polaris 代际选择和菜单设置：[启动菜单](polaris/boot-menu.zh.md)。
- Polaris/Clover Linux 前电源和重启目标：[启动动作](boot-actions.zh.md)。
- 启动失败、目标挂载和离线更新：[RAM recovery](recovery.zh.md)。
- 闭包传输和受检设备操作：[mobile-device](../pkgs/mobile-device/README.zh.md)。
- Sheng recovery 镜像更新：[recovery 操作](sheng/recovery.zh.md)。

普通系统更新维护 FAT `/boot` 上的内核、initrd、DTB 和代际条目；U-Boot 固件和
recovery 镜像单独更新。

## 定制与移植

- 软件包复用与覆盖：[packages](packages.zh.md)。
- 模块边界、共享 `androidDevices.*` 输入和设备选项：[modules](modules.zh.md)。
- 求值检查、内核补丁队列和新板 bring-up：[development](development.zh.md)。
- 开发主机工具和 USB 配置：[host](host.zh.md)。
- SSC 传感器和屏幕旋转：[sensors](sensors.zh.md)。
- 高通 modem 和 QTEE 服务：[modem](modem.zh.md)。

## 固件来源与许可证

设备固件按设备归档，发布在仓库的
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware)。
Git 树保留打包、补丁和配置，不包含 OEM payload。通用固件和法规数据来自 Nixpkgs
`linux-firmware` 和 `wireless-regdb`。固件二进制保留其上游许可证，不由此项目的
MIT 或内核 GPL-2.0 许可证覆盖。
