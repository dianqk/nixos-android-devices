# 支持状态：联想拯救者 Y700 2023（TB320FC）（asphalt）

[English](status.md) · [设备指南](README.zh.md) · [硬件支持](hardware.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 联想拯救者 Y700 2023（TB320FC）（asphalt） | Qualcomm SM8475 | Nixpkgs Linux 7.3-rc6 及 Asphalt 补丁 | 2026-10-30 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 10 | 13 | 0 | 16 | 3 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（`boot_b`）→ FAT `linux-boot` ESP 上的 systemd-boot → Linux，根分区为 ext4 `linux`；A 槽与 super 保持不变。 |
| 系统代际更新与回滚 | Works | 新代际默认启动，回滚后旧代际再次启动；`boot_b` 保持不变。 |
| RAM recovery | Works | `recovery_b` 中的 recovery 经原厂 bootloader 启动；USB SSH、离线文件系统检查和代际部署均可用。 |
| 从 recovery 首次安装 | Partial | 已在一台平板上通过 RAM recovery 完成安装；当前 `install-initial` 流程在全新平板上未验证。 |
| 重启到 bootloader 或 recovery | Partial | recovery 可进入原厂 bootloader；已安装系统重启进入 recovery 未验证。 |
| 内部存储 | Works | UFS 承载 ext4 根分区与 FAT ESP，经重启和更新保持正常；默认限制时钟为 75 MHz。 |
| microSD 卡 | Partial | SDXC 卡以 SDR104 识别并只读挂载；写入与热插拔未测试。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | NT36523N 双 DSI 面板经 MSM DRM 以 1600×2560、120 Hz 显示。 （2026-10-03 验证。） |
| 背光与熄屏 | Partial | 充电界面中可用电源键熄屏与亮屏；桌面亮度调节尚未验证。 （2026-10-04 验证。） |
| 触摸屏 | Works | Novatek 触摸在 Niri 中映射正确，包括四个旋转方向。 （2026-10-03 验证。） |
| 实体按键 | Partial | 电源键在充电界面中可用；音量键与桌面动作尚未验证。 （2026-10-04 验证。） |
| 外接显示（USB-C DisplayPort） | Untested | 3840×2160 60 Hz DP 输出可完成链路训练并由合成器驱动；显示器上的实际画面尚未验证。 |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Partial | Niri 桌面经 Freedreno（Adreno 730）渲染；glmark2 仅在自动检查中运行，一次 GMU 超时故障原因未明。 （2026-10-03 验证。） |
| Vulkan 加速 | Untested | Turnip 在自动检查中可渲染 vkcube；屏幕输出尚未验证。 |
| 硬件视频解码 | Untested | 自动检查中 Iris 可经 V4L2 和 VA-API 解码 180 秒 1080p H.264/HEVC 8-bit；屏幕播放尚未验证。 |
| 扬声器 | Untested | CS35L45 扬声器输出已存在；一次大幅衰减的播放测试未发出可听见的声音。 |
| 耳机 | Untested | 尚未确认是否有耳机接口。 |
| 麦克风 | Untested | 录音未测试。 |
| 摄像头 | Works | 三颗摄像头均可经 libcamera 软件 ISP 拍摄实景；调校为通用参数，无自动对焦。 （2026-09-27 验证。） |
| 闪光灯 | Untested | 尚未确认是否有闪光灯；未实现闪光灯控制。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | WCN6855 以双流 HE80 速率关联，获取 DHCP 并承载 SSH 流量。 |
| 蓝牙 | Partial | 发现与未配对 L2CAP 回显可用；配对尚未成功，协议配置未测试。 |
| USB 网络（设备模式） | Works | 系统与 recovery 中 NCM、DHCP 和 SSH 均可用，支持 USB2 与 USB3 速率。 |
| USB 主机 / OTG | Untested | 尚未测试接入设备的主机模式。 |
| 移动数据 | N/A | TB320FC 为无蜂窝调制解调器的 Wi-Fi 型号。 |
| 语音通话 | N/A | TB320FC 为无蜂窝调制解调器的 Wi-Fi 型号。 |
| 短信 | N/A | TB320FC 为无蜂窝调制解调器的 Wi-Fi 型号。 |
| 卫星定位（GPS） | Untested | 尚未确认是否有卫星定位硬件。 |
| NFC | Untested | 尚未确认是否有 NFC 硬件。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | 容量、电压和电流随放电变化合理；`power_now` 数值错误，`charge_counter` 被量化。 |
| 充电 | Partial | 接 USB 主机时关机充电在接近满电时可用；完整充电周期与快充未验证。 |
| 挂起 | Partial | s2idle 可进入深度睡眠并恢复；仅电源键可唤醒，两次中有一次恢复后蓝牙失效。 |
| 关机与重启 | Partial | 重启与关机通常可完成；USB gadget 拆除挂起与服务停止缓慢问题仍未解决。 |
| CPU 频率调节 | Partial | 三个 `schedutil` 策略可随负载调节频率；性能尚未经基准测试。 |
| 温度管理 | Partial | 温度区读数合理；降频未测试。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Works | SSC 加速度计驱动 Niri 在四个方向自动旋转。 （2026-10-03 验证。） |
| 磁力计 | Untested | SSC 中存在 MMC56x3 传感器；读数未验证。 |
| 环境光传感器 | Untested | SSC 中存在 STK3A5x 传感器；读数未验证。 |
| 距离传感器 | Untested | SSC 中存在 STK3A5x 传感器；读数未验证。 |
| 霍尔传感器（保护套） | Untested | SSC 中存在 BU52053NVX 霍尔传感器；保护套行为未测试。 |
| 振动 | Untested | 原厂 vendor 文件引用两个振动驱动；Linux 振动集成未测试。 |
| 指纹识别 | Untested | 尚未确认是否有指纹识别器。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
