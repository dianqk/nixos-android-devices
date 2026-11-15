# 支持状态：小米平板 6S Pro 12.4（sheng）

[English](status.md) · [设备指南](README.zh.md) · [硬件支持](hardware.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米平板 6S Pro 12.4（sheng） | Qualcomm SM8550 | Nixpkgs Linux 7.3-rc5 及 Sheng 补丁 | 2026-10-30 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 7 | 7 | 2 | 21 | 5 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（`boot_b`）→ FAT `linux-boot` 上的 systemd-boot → Linux，根分区为 ext4 `linux`；未连接 USB 主机时的启动未验证。 |
| 系统代际更新与回滚 | Partial | 新代际默认启动且无需重写 U-Boot；旧代际仅在适配期间被选择启动，尚无记录的回滚测试。 |
| RAM recovery | Works | ABL 可独立启动 `recovery_b`；USB SSH、离线系统部署与 recovery 自更新均可用。 |
| 从 recovery 首次安装 | Untested | 系统由 recovery 部署到手动准备的分区；`prepare-install` 与 `install-initial` 未测试。 |
| 重启到 bootloader 或 recovery | Works | 重启参数 `bootloader` 与 `recovery` 可进入 fastboot 和 RAM recovery。EFI 菜单项未测试。 |
| 内部存储 | Works | UFS；独立的 `linux` 与 `linux-boot` 分区与 Android 并存，Android 保持不变。 |
| microSD 卡 | N/A | 该平板没有 microSD 卡槽。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | 双 DSI NT36532E 面板以 3048×2032、120 Hz 显示，直接接管 U-Boot 画面。 （2026-10-06 验证。） |
| 背光与熄屏 | Untested | 软件可设置并读取亮度；面板上的亮度变化和熄屏/亮屏尚未验证。 |
| 触摸屏 | Works | NT36532E 触摸经 THP 服务工作；手写笔未测试。 （2026-10-05 验证。） |
| 实体按键 | Untested | 音量键和电源键可操作 U-Boot 与 recovery 菜单；桌面中的动作未测试。 |
| 外接显示（USB-C DisplayPort） | Untested | 较早内核上曾驱动 4K 显示器；当前内核与 USB 角色策略下未重新测试。 |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Untested | 软件检查中 Freedreno（Adreno 740）可渲染桌面和 glmark2；屏幕输出尚未验证。 |
| Vulkan 加速 | Untested | 软件检查中 Turnip（Adreno 740）可渲染 Vulkan 演示；屏幕输出尚未验证。 |
| 硬件视频解码 | Untested | Iris 解码 H.264、HEVC、VP9 和 AV1 的结果与软件解码逐像素一致，mpv 可经 VA-API 播放；屏幕播放尚未验证。 |
| 扬声器 | Broken | 六颗 CS35L43 功放均已绑定，但 UCM 查找失败，PipeWire 没有输出。 |
| 耳机 | N/A | 该平板没有 3.5 毫米耳机孔。 |
| 麦克风 | Broken | 已有录音 PCM，但 UCM 查找失败，PipeWire 没有输入。 |
| 摄像头 | Untested | libcamera 可拍摄前置场景和后置测试图案；图像质量尚未评估，ISP 未校准。 |
| 闪光灯 | Untested | 已启用闪光灯 LED 设备；闪光灯未测试。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | WCN7850 以 80 MHz 双流自动连接并承载 SSH，挂起后亦可用；吞吐量未测量。 |
| 蓝牙 | Partial | LE 与 BR/EDR 扫描可用；当前内核下配对和音频未测试。 |
| USB 网络（设备模式） | Partial | 系统与 recovery 中 NCM SSH 可在 10 Gb/s 下工作，但主机端有时需手动设置地址。 |
| USB 主机 / OTG | Untested | 较早内核上 USB 游戏手柄可用；当前内核未测试。 |
| 移动数据 | N/A | 仅 Wi-Fi 版平板，没有蜂窝调制解调器。 |
| 语音通话 | N/A | 仅 Wi-Fi 版平板，没有蜂窝调制解调器。 |
| 短信 | N/A | 仅 Wi-Fi 版平板，没有蜂窝调制解调器。 |
| 卫星定位（GPS） | Untested | 尚未确认是否有定位接收器。 |
| NFC | Untested | 尚未确认是否有 NFC。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | 充电时电量计读数合理；放电尚未测试。 |
| 充电 | Partial | 电池可从 3% 充至 82%，支持 MiPPS 快充；完整充电周期尚未测试。 |
| 挂起 | Partial | 挂起与恢复成功且 Wi-Fi 可恢复；功耗与其他外设未验证。 |
| 关机与重启 | Partial | 重启可重复成功；关机与冷启动尚未验证。 |
| CPU 频率调节 | Untested |  |
| 温度管理 | Untested |  |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | 较早内核上自动旋转可用；当前内核下可选传感器栈未测试。 |
| 磁力计 | Untested |  |
| 环境光传感器 | Untested |  |
| 距离传感器 | Untested | 尚未确认是否有该传感器。 |
| 霍尔传感器（保护套） | Untested | 设备树中已描述霍尔输入；保护套行为未测试。 |
| 振动 | Untested | 尚未确认是否有振动马达。 |
| 指纹识别 | Untested | 已打包 FPC1553 驱动与 fprintd；录入与验证未测试。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
