# Android 设备上的 NixOS

[English](README.md)

为九款高通和联发科手机、平板提供 NixOS 设备模块、内核和 U-Boot 固件。系统通过
**U-Boot → systemd-boot → Linux** 启动，使用标准 NixOS 配置、更新和代际管理。

## 设备

| 设备 | 代号 | 指南 |
| --- | --- | --- |
| 联想 Legion Y700 2023（TB320FC） | `asphalt` | [使用与安装](docs/asphalt/README.zh.md) |
| 小米 MIX 2S | `polaris` | [使用与安装](docs/polaris/README.zh.md) |
| 小米平板 6S Pro 12.4 | `sheng` | [使用与安装](docs/sheng/README.zh.md) |
| 小米 14 Ultra | `aurora` | [使用与安装](docs/aurora/README.zh.md) |
| 小米平板 4 8 英寸 LTE | `clover` | [使用与安装](docs/clover/README.zh.md) |
| Redmi Note 12 Turbo / POCO F5 | `marble` | [使用与安装](docs/marble/README.zh.md) |
| 酷比魔方 iPlay 80 mini Ultra | `t880` | [使用与安装](docs/t880/README.zh.md) |
| 一加 13 | `dodge` | [使用与安装](docs/dodge/README.zh.md) |
| Xiaomi 12S Pro | `unicorn` | [使用与安装](docs/unicorn/README.zh.md) |

各指南包含支持的硬件、存储约定、首次安装、更新、recovery 和已知限制。支持状态
记录在各设备页中；本 README 不划分支持等级。

## 快速开始

1. **配置**：使用 `lib.mkSystem` 或 `nixosModules.<device>`。设备选项使用
   `hardware.<device>.*`，共享能力使用 `androidDevices.*`。用户、SSH 密钥、
   桌面和应用使用普通 NixOS 配置。
2. **构建**：使用 `lib.mkArtifacts` 导出匹配的系统和启动文件。见
   [配置指南](docs/configuration.zh.md)。
3. **安装**：按设备指南准备 ext4 根和 FAT `/boot`，安装系统和 EFI 文件，然后
   安装 U-Boot。
4. **更新**：通过 [USB SSH](docs/usb-signaller.zh.md) 或自己的网络运行
   `nixos-rebuild boot`。普通更新维护 `/boot`，不重写 U-Boot。

[消费者 flake](examples/consumer/flake.nix) 是完整的起点。[示例](examples/)
只是演示，不是必须采用的策略。

## 构建平台

支持 AArch64 Linux 原生构建，或 x86_64 交叉编译配合本机 QEMU 补齐无缓存的 ARM
原生依赖。详见[构建要求](docs/configuration.zh.md#构建平台与远程构建机)。

## 固件与风险

设备固件按设备归档，发布在仓库的
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware)。
Git 树只包含打包和补丁，不包含 OEM 固件 payload。

**刷写风险：**本项目由 LLM 生成。刷入镜像可能导致设备无法启动，甚至永久无法使用。
写入前核对型号、分区和镜像，并确认可用的恢复入口。安装与排障使用独立的
[RAM recovery](docs/recovery.zh.md)；存储规则见
[U-Boot 安装](docs/u-boot-install.zh.md)。

## 文档

- [安装与更新](docs/README.zh.md)
- [配置](docs/configuration.zh.md)
- [模块与软件包](docs/modules.zh.md) · [软件包](docs/packages.zh.md)
- [开发与检查](docs/development.zh.md)
- [Recovery](docs/recovery.zh.md) · [USB 访问](docs/usb-signaller.zh.md)
- [Dodge 同槽位启动选择](docs/boot-choice.zh.md)

## 许可证

本项目原创代码采用 [MIT 许可证](LICENSE)。Linux 内核补丁遵循上游
[GPL-2.0 条款](LICENSES/GPL-2.0)。固件二进制保留其上游许可证，不由此许可证覆盖。
