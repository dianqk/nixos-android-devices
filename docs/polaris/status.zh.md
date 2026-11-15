# 支持状态：小米 MIX 2S（polaris）

[English](status.md) · [设备指南](README.zh.md) · [硬件支持](hardware.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米 MIX 2S（polaris） | Qualcomm SDM845 | Nixpkgs Linux 7.3 及 Polaris 补丁 | 2026-10-30 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 9 | 12 | 4 | 15 | 2 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（boot）→ FAT `system` 上的 systemd-boot → Linux EFI stub，根分区为 `userdata`。 |
| 系统代际更新与回滚 | Works | 更新、回滚与恢复均启动所选代际；`boot` 保持不变。 |
| RAM recovery | Partial | 已安装的 recovery 可独立启动，并经 ADB 完成存储操作；当前基于 SSH 的 recovery 尚未真机测试。 |
| 从 recovery 首次安装 | Partial | recovery 已准备 FAT `/boot` 并安装可启动的 EFI 文件和 U-Boot；在空根分区上的安装未测试。 |
| 重启到 bootloader 或 recovery | Works | systemd-boot 的 bootloader 和 recovery 菜单项可用；Linux 以 `bootloader` 参数重启可进入 fastboot。 |
| 内部存储 | Works | UFS 2.1 承载 ext4 `userdata` 和 FAT `system`；原厂 GPT 保持不变。 |
| microSD 卡 | N/A | MIX 2S 没有 microSD 卡槽。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | NT35596S DSI 面板经 MSM DRM 以 1080×2160 显示，开机首帧正常。 （2026-09-15 验证。） |
| 背光与熄屏 | Partial | 电源键可关闭和点亮屏幕；面板上的亮度调节尚未验证。 （2026-10-04 验证。） |
| 触摸屏 | Works | 触摸解锁与桌面输入可用；当前 Niri 会话的旋转输入映射未单独验证。 （2026-09-15 验证。） |
| 实体按键 | Partial | 电源键可在充电界面亮灭屏和重启；桌面与音量键动作尚未验证。 （2026-10-04 验证。） |
| 外接显示（USB-C DisplayPort） | Untested | 尚未确认该 USB-C 接口是否支持 DisplayPort 替代模式。 |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Untested | Freedreno（Adreno 630）可渲染桌面，glmark2 得分 663；屏幕输出尚未验证。 |
| Vulkan 加速 | Untested | Turnip 在 vkmark 中得分 1407；屏幕输出尚未验证。 |
| 硬件视频解码 | Works | H.264 与 HEVC 8-bit 可经 Venus V4L2 在 mpv 中播放；HEVC Main 10 需使用 VA-API 路径。 （2026-09-23 验证。） |
| 扬声器 | Partial | 曾听到扬声器播放的视频声音；最新 UCM 修复后的可听性尚未验证。 （2026-09-23 验证。） |
| 耳机 | N/A | 无 3.5 mm 耳机孔。 |
| 麦克风 | Broken | 录音流可以打开，但录到的样本全为静音。 |
| 摄像头 | Partial | 前置 OV5675 与后置主摄 IMX363 可经 libcamera 拍摄；缺少后置副摄、自动对焦和图像调校。 （2026-09-27 验证。） |
| 闪光灯 | Untested | 尚未测试闪光灯控制。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | WCN3990 可在 5 GHz、160 MHz 下连接、获取 DHCP、传输数据并自动重连；挂起恢复未测试。 |
| 蓝牙 | Partial | 可与真实设备互通；未覆盖音频或输入配置文件的配对使用。 |
| USB 网络（设备模式） | Works | 系统中 NCM、DHCP 和 SSH 可用，并可经 USB 更新系统。 |
| USB 主机 / OTG | Untested | 已配置主机模式；VBUS 输出与设备枚举未验证。 |
| 移动数据 | Broken | 调制解调器为支持 Wi-Fi 而运行，但未启用 ModemManager 和蜂窝数据路径。 |
| 语音通话 | Broken | 未启用电话软件栈或通话音频路径。 |
| 短信 | Broken | 未启用短信路径。 |
| 卫星定位（GPS） | Untested | 无定位结果，也无用户空间集成。 |
| NFC | Untested | 尚无 NFC 设备或测试记录。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | PMI8998 电量计读数合理；完整放电尚未测试。 |
| 充电 | Partial | 按上游 SMB2 限制（1 A）充电并提供关机充电界面；充满终止和完整充电周期尚未验证。 |
| 挂起 | Untested | 挂起、省电与唤醒恢复尚未测试。 |
| 关机与重启 | Partial | 重启可用，插电关机会进入充电界面；电源键冷启动未测试。 |
| CPU 频率调节 | Partial | 两个 CPU 簇均有 `schedutil` 策略（最高 1.77 和 2.65 GHz）；未测量频率随负载变化。 |
| 温度管理 | Partial | 负载下温度区读数合理；降频未测试。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | 传感器 DSP 可向 IIO 代理提供三轴数据；桌面旋转尚未验证。 |
| 磁力计 | Untested |  |
| 环境光传感器 | Untested |  |
| 距离传感器 | Untested |  |
| 霍尔传感器（保护套） | Untested | 尚未确认是否有该传感器。 |
| 振动 | Untested | 尚无振动驱动或测试记录。 |
| 指纹识别 | Untested | 尚无指纹驱动或测试记录。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
