# Android 设备上的 NixOS

[English](README.md)

为小米和联想的四款手机、平板提供 NixOS 设备模块、内核和 U-Boot 固件。
系统通过 **U-Boot → systemd-boot → Linux** 启动，使用标准 NixOS 配置、更新和代际管理。
支持 AArch64 Linux 原生构建，或 x86_64 交叉编译配合本机 QEMU 补齐无缓存的 ARM 原生依赖。
详见[构建要求](docs/configuration.zh.md#构建平台与远程构建机)。

## 支持的设备

| 设备 | 代号 | 支持等级 | 配置与硬件状态 |
| --- | --- | --- | --- |
| 联想 Legion Y700 2023（TB320FC） | `asphalt` | Tier 2：可构建、可求值 | [设备指南](docs/asphalt/README.zh.md) |
| 小米 MIX 2S | `polaris` | Tier 2：可构建、可求值 | [设备指南](docs/polaris/README.zh.md) |
| 小米平板 6S Pro 12.4 | `sheng` | Tier 2：可构建、可求值 | [设备指南](docs/sheng/README.zh.md) |
| 小米平板 4 8 英寸 LTE | `clover` | Tier 3：可求值 | [设备指南](docs/clover/README.zh.md) |

支持等级针对本仓库的示例；具体硬件功能和实测范围见各设备指南。
目前没有满足专用设备运行验证要求的 Tier 1 设备，详见[支持标准](docs/README.zh.md#支持等级)。

## 开始使用

1. **配置**：从[配置指南](docs/configuration.zh.md)创建自己的 flake，使用
   `lib.mkSystem` 或 `nixosModules.<device>`。设备专属选项使用 `hardware.<device>.*`，
   共享能力使用 `androidDevices.*`；用户、SSH 密钥、桌面和应用使用普通 NixOS 配置。
2. **构建**：使用 `lib.mkArtifacts` 导出与配置匹配的系统和启动文件。
   [产物说明](docs/configuration.zh.md#选择构建产物)区分系统闭包、U-Boot 固件和 EFI 文件。
3. **安装**：按[设备安装指南](docs/README.zh.md#安装)准备 ext4 根和 FAT `/boot`，
   四款设备均可在分区准备完成后使用[首次安装器](docs/initial-install.zh.md)
   安装系统、EFI 文件和 U-Boot。
4. **更新**：安装后通过 [USB SSH](docs/usb-signaller.md) 或自己配置的网络运行
   `nixos-rebuild boot`，重启后检查新一代系统。普通更新只维护 `/boot` 上的 EFI 文件，
   不重写 U-Boot。

**刷写风险：**本项目完全由 LLM 生成。刷入镜像可能导致设备无法启动，甚至永久无法使用。
自行构建和刷入者承担相应风险；写入前核对型号、分区和镜像，并确认可用的恢复入口。
安装与排障使用独立的 [RAM recovery](docs/recovery.md)；具体存储规则见
[U-Boot 安装](docs/u-boot-install.zh.md)。

## 构建仓库示例

在启用 flakes 的 Linux 构建电脑上，只构建所选设备需要的产物。例如：

```sh
nix build .#devices.polaris.system --out-link tmp/systemd-artifacts/devices.polaris.system
nix build .#devices.polaris.boot-files --out-link tmp/systemd-artifacts/devices.polaris.boot-files
nix build .#devices.polaris.u-boot --out-link tmp/systemd-artifacts/devices.polaris.u-boot
```

其他设备将 `polaris` 换为 `asphalt`、`sheng` 或 `clover`。`devices.<device>.boot`
与 `devices.<device>.u-boot` 是同一固件；`boot-files` 是文件目录，不能作为分区镜像刷入。
其他输出包括 `bootstrap-info`、`recovery` 和 `kernel`，按安装指南选用。
这些命令仅构建产物；部署前须填写本机存储身份和访问凭据。

[`examples/`](examples/) 中的桌面示例显式选择 Sway、空密码 `demo` 自动登录及测试工具。
设备模块本身只提供硬件能力。Polaris 另有[最小控制台示例](docs/polaris/minimal.md)，
其 USB root SSH 允许空密码。请按自己的访问需求修改示例配置。

## 更多文档

- [软件包复用与覆盖](docs/packages.zh.md)
- [构建与开发检查](docs/development.md)
- [主机部署工具](pkgs/mobile-device/README.zh.md)

## 许可证

本项目原创代码采用 [MIT 许可证](LICENSE)。Linux 内核补丁遵循上游的
[GPL-2.0 条款](LICENSES/GPL-2.0)。
