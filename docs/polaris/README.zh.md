# 小米 MIX 2S（polaris）

[English](README.md) · [全部设备](../README.zh.md) · [硬件支持](hardware.zh.md)

支持等级：Tier 2。具体含义见[支持范围](../README.zh.md#支持等级)。

## 配置与安装

1. 按[配置指南](../configuration.zh.md)创建自己的 flake，将 `lib.mkSystem` 的
   `device` 设置为 `"polaris"`，或导入 `nixosModules.polaris`。
2. 在已安装系统配置中填写下方设置，与独立 recovery 配置共享根分区标签；
   用户、桌面和服务留在已安装系统配置中。
3. 按[首次安装指南](first-install.zh.md)核对分区、构建匹配的 system/bootstrap-info/
   recovery，并完成安装。

```nix
{
  androidDevices.usbSerial = "my-polaris-01";
  androidDevices.usb.ssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY" ];
}
```

只需要 USB 控制台时，设置 `hardware.polaris.radio.enable = false` 和
`hardware.polaris.audio.enable = false`；两者默认均开启。启用无线时，通过
`hardware.polaris.radio.identityFile` 指定设备上的 Wi-Fi 地址文件，
`snapshotDirectory` 指向已核对的只读校准快照，`bluetoothIdentityFile` 指定蓝牙地址。
这些都是手机上的路径，不是构建输入文件。模块不会采集校准数据或生成出厂身份；
未配置快照目录时不启动 RMTFS。缺少已核实无线数据时先使用 USB 控制台配置。
NetworkManager、Bluetooth 和 PipeWire 使用标准 NixOS 选项启用。

Polaris 默认使用 U-Boot/EFI，物理 `system` 为 FAT `/boot`，`userdata` 为 ext4 根。
配置 USB SSH 后，按 [USB 指南](../usb-signaller.md)连接和更新；
[启动菜单](boot-menu.md)说明如何选择系统代。

## 使用与排障

自己的消费 flake 可构建 `.#system`、`.#bootstrap-info` 和 `.#recovery`；
仓库演示产物使用 `.#devices.polaris.<role>`，如 `.#devices.polaris.system`。使用 `lib.mkArtifacts` 得到与配置匹配的产物，
详见[产物说明](../configuration.zh.md#选择构建产物)。

- 日常系统更新：[USB SSH](../usb-signaller.md)。
- 启动失败与离线更新：[RAM recovery](../recovery.md)。
- Wi-Fi、音频、显示等支持程度：[硬件参考](hardware.zh.md)。
- 构建/求值问题：[配置排障](../configuration.zh.md#更新恢复与排障)。
- 相机命令与限制：[相机](hardware.zh.md#相机)。

## 固件来源

设备专用固件从固定的上游提交获取，本仓库不保存其二进制副本。

- 来源：[MollySophia/firmware-xiaomi-polaris 的 `d88ffb2` 提交](https://github.com/MollySophia/firmware-xiaomi-polaris/tree/d88ffb2ee182d07567bf280fc4a8493f975ae977)。
- 用途：设备专用 modem、Wi-Fi、蓝牙、GPU、IPA 与多媒体固件。

通用固件来源及许可证说明见[文档索引](../README.zh.md#固件来源与许可证)。
