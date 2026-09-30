# 小米平板 4 8 英寸 LTE（clover）

[English](README.md) · [全部设备](../README.zh.md) · [硬件支持](hardware.zh.md)

支持等级：Tier 3。具体含义见[支持范围](../README.zh.md#支持等级)。

可选的 `boot-kernel` 镜像直接启动固定的一代 Linux 系统；默认使用 U-Boot。
见[配置与使用说明](../configuration.zh.md#额外的内核直启镜像sheng--clover)。

## 配置与安装

1. 按[配置指南](../configuration.zh.md)创建自己的 flake，将 `lib.mkSystem` 的
   `device` 设置为 `"clover"`，或导入 `nixosModules.clover`。
2. 在已安装系统配置中填写下方设置，与独立 recovery 配置共享设备和存储身份；
   用户、桌面和服务留在已安装系统配置中。
3. 阅读[安装准备](first-install.zh.md)，确认本机存储布局和仍需手动完成的步骤，
   再构建匹配的系统、EFI 文件、U-Boot 和 recovery。

```nix
{
  androidDevices.usbSerial = "my-clover-01";
  hardware.clover.storageRolesFile = ./storage-roles.sh;
  androidDevices.persistentImage.rootfs.label = "NIXOS";
  # Preserve the existing UUID when keeping a filesystem:
  # hardware.clover.rootUUID = "YOUR_MEASURED_UUID";
}
```

模块面向 8 英寸 LTE 型号。安装系统和 recovery 使用同一份实测 eMMC 存储契约，
未配置的默认契约拒绝写入。可选的 `hardware.clover.wifiAddress` 和 `bluetoothAddress`
必须填写本机出厂身份。此板无 A/B，不复用 Asphalt/Sheng 的分区名或切槽命令。

Clover 使用 U-Boot/systemd-boot，物理 `system` 为 FAT `/boot`，`userdata` 为 ext4 根。
U-Boot 尚未真机验证，已接入[共享 EFI 首装器](../initial-install.zh.md)，分区准备需单独完成，见[安装准备](first-install.zh.md)。

默认内核为 Nixpkgs Linux 7.3-rc5，附有[注明来源的 Clover 补丁](../../pkgs/linux-kernel/sdm660/clover/PATCHES.zh.md)，
尚未在设备上启动验证。

## 使用与排障

自己的消费 flake 可构建 `.#system`、`.#bootstrap-info` 和 `.#recovery`；
仓库演示产物使用 `.#devices.clover.<role>`，如 `.#devices.clover.system`。使用 `lib.mkArtifacts` 得到与配置匹配的产物，
详见[产物说明](../configuration.zh.md#选择构建产物)。

- 日常系统更新：[USB SSH](../usb-signaller.md)。
- 启动失败与离线更新：[RAM recovery](../recovery.md)。
- Wi-Fi、音频、显示等支持程度：[硬件参考](hardware.zh.md)。
- 构建/求值问题：[配置排障](../configuration.zh.md#更新恢复与排障)。

## 固件来源

设备专用固件从固定的上游提交获取，本仓库不保存其二进制副本。

- 来源：[setotau/firmware-xiaomi-clover 的 `c850ad5` 提交](https://github.com/setotau/firmware-xiaomi-clover/tree/c850ad5d11315e690df8244670241e3d5a8436dc)。
- 用途：WCN3990 板级数据。

通用固件来源及许可证说明见[文档索引](../README.zh.md#固件来源与许可证)。
