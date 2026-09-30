# 联想 Y700 2023（TB320FC）（asphalt）

[English](README.md) · [全部设备](../README.zh.md) · [硬件支持](hardware.zh.md)

支持等级：Tier 2。具体含义见[支持范围](../README.zh.md#支持等级)。

## 配置与安装

1. 按[配置指南](../configuration.zh.md)创建自己的 flake，将 `lib.mkSystem` 的
   `device` 设置为 `"asphalt"`，或导入 `nixosModules.asphalt`。
2. 在已安装系统配置中填写下方设置，与独立 recovery 配置共享设备和存储身份；
   用户、桌面和服务留在已安装系统配置中。
3. 阅读[安装准备](first-install.zh.md)，确认本机存储布局和仍需手动完成的步骤，
   再构建匹配的系统、EFI 文件、U-Boot 和 recovery。

```nix
{
  androidDevices.usbSerial = "my-asphalt-01";
  androidDevices.persistentImage.rootfs.label = "NIXOS";
  # Optional factory identity files:
  # hardware.asphalt.radio.wifiAddressFile = ./wifi-address;
  # hardware.asphalt.radio.bluetoothAddressFile = ./bluetooth-address;
}
```

可选的身份文件是构建输入。Wi-Fi 文件保存出厂 MAC；蓝牙文件保存控制器字节序的
Qualcomm NVM 地址，服务会转换为 BlueZ 使用的顺序。recovery 不运行这些身份服务。
根文件系统位于独立的物理 `linux` 分区，不在 super 中。B 槽启动成功确认尚未自动化，
依赖多次重启前请阅读[硬件限制](hardware.zh.md)。

Asphalt 已验证 U-Boot/EFI 启动、代际更新与回退。
使用独立 1 GiB FAT `linux-boot` ESP 和 ext4 `linux`，固件位于 `boot_b`，保留 A 和 super。
尚需手动完成的准备步骤见[安装准备](first-install.zh.md)。

## 使用与排障

自己的消费 flake 可构建 `.#system`、`.#bootstrap-info` 和 `.#recovery`；
仓库演示产物使用 `.#devices.asphalt.<role>`，如 `.#devices.asphalt.system`。使用 `lib.mkArtifacts` 得到与配置匹配的产物，
详见[产物说明](../configuration.zh.md#选择构建产物)。

- 日常系统更新：[USB SSH](../usb-signaller.md)。
- 启动失败与离线更新：[RAM recovery](../recovery.md)。
- Wi-Fi、音频、显示等支持程度：[硬件参考](hardware.zh.md)。
- 构建/求值问题：[配置排障](../configuration.zh.md#更新恢复与排障)。
- 相机命令与限制：[相机](hardware.zh.md#相机)。

## 固件来源

设备专用固件从固定的上游提交获取，本仓库不保存其二进制副本。

- 来源：[dianqk/firmware-lenovo-asphalt 的 `207d466` 提交](https://github.com/dianqk/firmware-lenovo-asphalt/tree/207d4668183032c1d9f196f195e9ecef98949d06)。
- 用途：触摸、GPU、音频、视频、WCN6855 板级数据及 OnePlus Wi-Fi 固件。

上游仓库记录了 Lenovo Android 镜像来源、OnePlus Wi-Fi 来源与 41 个文件的
SHA256 校验值。可通过 `hardware.asphalt.wifiBoardFile` 覆盖默认 Wi-Fi
板级数据；设备地址由用户另行提供。

通用固件来源及许可证说明见[文档索引](../README.zh.md#固件来源与许可证)。
