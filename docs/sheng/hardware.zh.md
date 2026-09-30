# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库包含适配代码，不代表另一台平板已通过全新安装。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 启动与存储 | SM8550 内核/设备树、A/B boot 与 recovery、手工 GPT 准备、`linux` ext4 根分区 | 持久 B 槽 U-Boot/EFI 和独立 RAM recovery 已验证；全新分区未测试 |
| 显示与输入 | 面板、NT36532E 触摸、recovery 按键 | RAM 启动已验证 U-Boot 菜单和音量/电源选择；进入 Linux 后可能黑屏；触摸未验证 |
| GPU 与视频 | Adreno 和视频固件、内核驱动 | 硬件 OpenGL/Vulkan 与 H.264/HEVC 解码已验证 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与蓝牙 | WCN7850 固件和蓝牙驱动 | Wi-Fi/蓝牙实时扫描通过；需配置本机蓝牙地址 |
| 音频 | ADSP 固件、拓扑、SoundWire 和 CS35L43 驱动 | 已验证 ALSA 声卡/PCM；未验证播放、录音与路由 |
| 传感器、指纹、手写笔 | ADSP 传感器服务、FPC1553 与手写笔工具 | 可选；端到端使用未验证 |
| 相机 | CAMSS/flash-class 驱动、libcamera 传感器增益映射 | 前摄场景与后摄彩条通过；ISP 尚未校准 |

## 已知限制

默认 7.2.6 内核可启动并使用 USB/SSH 和 Wi-Fi；可选的 7.3-rc5 内核目前无法加载
WCN7850 固件。不连接 USB 主机的启动仍未验证。

从 U-Boot 菜单进入 Linux 后可能黑屏。测试中，关闭再开启合成器的 DSI 输出可恢复
画面，仅调整亮度无效；即使 SSH 可达，也可能遇到此显示启动问题。完整色彩准确性仍未验证。

FFmpeg 的 `h264_v4l2m2m` 和 `hevc_v4l2m2m` 已通过 Iris 完整硬解 180 秒
1080p、8-bit 视频。mpv、零拷贝显示和音画同步仍未验证。

Libcamera 已验证前置 OV32D40 的 3264×2448 场景照片和后置 S5KJN1 的
4080×3060 彩条。后摄实景画质、自动对焦、闪光灯和色彩校准仍未验证；
深度传感器可枚举，但采集画质未测试。

Recovery 和普通系统可协商 10 Gb/s USB 链路，持续吞吐量未测量。
Recovery 需保留模块提供的 ADSP 固件；缺失时 Type-C/UCSI 无法启动，USB 限于 480 Mb/s。

## 可选设置

Sheng 使用共享的正常系统 NCM、recovery ACM+NCM 策略。双角色和 Type-C 支持保留，
自动线缆角色切换仍需实机验证。设备模块也负责 WCN7850 P2P NetworkManager
排除规则。
通过 `hardware.sheng.wifiMacAddress` 提供本机已知的出厂地址。
`hardware.sheng.suspendWorkarounds.enable` 默认 `false`；显式启用后过滤
未使用的唤醒源，并在休眠前后重新加载 `ath12k_wifi7`。最小示例尚未验证休眠可用。
