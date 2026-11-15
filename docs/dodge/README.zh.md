# 一加 13（dodge）

[English](README.md) · [全部设备](../README.zh.md) · [支持状态](status.zh.md)

Dodge 是实验性的一加 13 移植。NixOS 通过 U-Boot 和 systemd-boot 启动，同槽位
boot-choice 产品可在当前槽位选择 Android 或 NixOS，而不切换 A/B。请保留可用的
Android、独立 RAM recovery 和回滚资产。

## 存储与启动

- UFS `linux-boot` 保存 FAT ESP；ext4 `linux` 是 NixOS 根。
- 已安装系统使用 U-Boot `boot_b` 和 systemd-boot；Android 保留在 A 槽。
- U-Boot 是同槽位产品的嵌入组件，不是独立可刷写 boot image。使用匹配的
  producer/helper，或保留现有独立 U-Boot/Android 引导资产。
- RAM recovery 是主机提供的 FIT payload，独立于已安装 U-Boot。见
  [recovery](../recovery.zh.md)。

## 固件与功能

默认[固件包](firmware.zh.md)是仓库 `firmware` release 中的
`dodge-firmware-LineageOS-24.0-5dd12b17e7-20261115.tar.zst`，包含 GPU、Wi-Fi、
蓝牙、ADSP、CDSP、modem、SoCCP、视频、音频和 SSC 运行时数据。需要允许 unfree
的 `dodge-firmware`。

- 显示、触摸、USB NCM/SSH、USB 主机/DP、Wi-Fi 和基础蓝牙可用；实测限制见
  [状态](status.zh.md)。
- AudioReach 扬声器和麦克风：[音频](audio.zh.md)。
- 无线充电和可选电压养护策略：[无线充电](wireless-charging.zh.md)。
- 触摸与显示唤醒：[触摸](touch.zh.md)。
- SSC 传感器：[传感器](sensors.zh.md)。
- 同槽位 Android/NixOS 选择：[boot choice](../boot-choice.zh.md)。

## 构建

```sh
nix build .#devices.dodge.recovery --out-link result-recovery
nix build .#devices.dodge.boot-firmware --out-link result-firmware
nix build .#devices.dodge.firmware --out-link result-device-firmware
nix build .#devices.dodge.kernel --out-link result-kernel
```

使用匹配的 `nixosModules.dodge` 和 `hardware.dodge.*` 选项。设备配置、首次安装
和 recovery 命令见共享的[安装指南](../README.zh.md)和
[recovery 指南](../recovery.zh.md)。

Suspend、持续热策略、完整充电周期和部分外设组合仍未验证。不要把主机检查当作
硬件验收。
