# 小米平板 6S Pro 12.4（sheng）

[English](README.md) · [全部设备](../README.zh.md) · [硬件支持](hardware.zh.md)

支持等级：Tier 2。具体含义见[支持范围](../README.zh.md#支持等级)。

可选的 `boot-kernel` 镜像直接启动固定的一代 Linux 系统；默认使用 U-Boot。
见[配置与使用说明](../configuration.zh.md#额外的内核直启镜像sheng--clover)。

## 配置与安装

1. 按[配置指南](../configuration.zh.md)创建自己的 flake，将 `lib.mkSystem` 的
   `device` 设置为 `"sheng"`，或导入 `nixosModules.sheng`。
2. 在已安装系统配置中填写下方设置，与独立 recovery 配置共享设备和存储身份；
   用户、桌面和服务留在已安装系统配置中。
3. 阅读[安装准备](first-install.zh.md)，确认本机存储布局和仍需手动完成的步骤，
   再构建匹配的系统、EFI 文件、U-Boot 和 recovery。

```nix
{
  androidDevices.usbSerial = "my-sheng-01";
  androidDevices.persistentImage.rootfs.label = "NIXOS";
  # Use this tablet's verified factory addresses when needed:
  # hardware.sheng.wifiMacAddress = "YOUR_FACTORY_WIFI_ADDRESS";
  # hardware.sheng.bluetoothAddress = "YOUR_FACTORY_BLUETOOTH_ADDRESS";
}
```

可选能力包括 `hardware.sheng.sensors.enable`、`services.fprintd.enable`、
`hardware.sheng.thp.enable`、`hardware.sheng.pen-status.enable` 和
`services.xiaomi-mipps-auth.enable`。传感器/devauth 包需要 Nixpkgs unfree 许可；
仅开启需要的功能。`hardware.sheng.suspendWorkarounds.enable` 默认关闭，启用的是下游
唤醒源与 Wi-Fi 重载 workaround，不代表休眠已经验证。recovery 的 ADSP 固件同时支持
Type-C/USB，不能为了精简而随意替换整份固件列表。

Sheng 默认内核及安装系统示例使用固定版本的 Linux 7.2.6。Nixpkgs 7.3-rc5
补丁集保留为 `kernel-testing`；排查其 Wi-Fi 路径期间，RAM recovery 示例显式选择
此内核。来源记录和构建命令见
[内核说明](../../pkgs/linux-kernel/sm8550/sheng/PATCHES.zh.md)。

Sheng 已通过刷入 B 槽的 U-Boot/EFI 启动 7.2.6 示例；普通重启后的 USB/SSH 与
Wi-Fi 已验证。RAM 启动已验证 U-Boot 菜单显示和音量/电源选择，但进入 Linux
后可能黑屏；无 USB 主机时的启动仍未验证，详见[已知限制](hardware.zh.md#已知限制)。
使用独立 1 GiB FAT `linux-boot` ESP 和 ext4 `linux`，固件位于 `boot_b`，保留 A 和 super。
尚需手动完成的准备步骤见[安装准备](first-install.zh.md)。

## 使用与排障

自己的消费 flake 可构建 `.#system`、`.#bootstrap-info` 和 `.#recovery`；
仓库演示产物使用 `.#devices.sheng.<role>`，如 `.#devices.sheng.system`。使用 `lib.mkArtifacts` 得到与配置匹配的产物，
详见[产物说明](../configuration.zh.md#选择构建产物)。

- 日常系统更新：[USB SSH](../usb-signaller.md)。
- 启动失败与离线更新：[RAM recovery](../recovery.md)。
- Wi-Fi、音频、显示等支持程度：[硬件参考](hardware.zh.md)。
- 构建/求值问题：[配置排障](../configuration.zh.md#更新恢复与排障)。
- recovery 更新：[recovery 操作](recovery.zh.md)。

## 固件来源

设备专用固件从固定的上游提交获取，本仓库不保存其二进制副本。

- 来源：[code002-2/sheng-firmware 的 `14a4d70` 提交](https://github.com/code002-2/sheng-firmware/tree/14a4d70b0759bd0746264dc145f2d51a5a94902c)。
- 用途：GPU、Wi-Fi、音频、触摸、ADSP，以及可选的指纹与传感器服务。

通用固件来源及许可证说明见[文档索引](../README.zh.md#固件来源与许可证)。
