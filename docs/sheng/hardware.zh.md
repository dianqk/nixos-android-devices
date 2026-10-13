# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库包含适配代码，不代表另一台平板已通过全新安装。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 启动与存储 | SM8550 内核/设备树、A/B boot 与 recovery、手工 GPT 准备、`linux` ext4 根分区 | 持久 B 槽 U-Boot/EFI 和独立 RAM recovery 已验证；全新分区未测试 |
| 显示与输入 | 面板、NT36532E 触摸、recovery 按键 | RAM 启动已验证 U-Boot 菜单和音量/电源选择；带补丁的 7.3 显示接管通过；触摸未验证 |
| GPU 与视频 | Adreno 和视频固件、内核驱动 | 已验证硬件 OpenGL/Vulkan；7.3 H.264/HEVC 8-bit 解码通过，FFmpeg Main10 失败 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与蓝牙 | WCN7850 固件和蓝牙驱动 | 7.3 协商到 80 MHz EHT/NSS 2、约 1.3 Gbit/s；蓝牙扫描通过，配对未测 |
| 音频 | ADSP 固件、拓扑、SoundWire 和 CS35L43 驱动 | 7.3 可探测全部六颗功放和 ALSA PCM；受测示例没有活动的 PipeWire 输出路由 |
| 传感器、指纹、手写笔 | ADSP 传感器服务、FPC1553 与手写笔工具 | 可选；端到端使用未验证 |
| 相机 | CAMSS/flash-class 驱动、libcamera 传感器增益映射 | 前摄场景与后摄彩条通过；ISP 尚未校准 |

## 已知限制

打包的内核为 Nixpkgs Linux 7.3-rc6。本页硬件结果基于 7.3-rc5 补丁集取得。
见[内核补丁说明](../../pkgs/linux-kernel/sm8550/sheng/PATCHES.zh.md)。

7.3 安装系统可用：无需关闭再开启 DSI 输出即可直接以 120 Hz 显示 3048×2032 桌面，
Wi-Fi 自动连接和扫描，以及通过 USB 和 Wi-Fi 的 SSH。应保留可用的回退代。

已知问题与未验证范围：

- 不连接 USB 主机的启动、休眠和完整色彩准确性未验证。
- 视频：FFmpeg 的 `h264_v4l2m2m` 和 `hevc_v4l2m2m` 解码 1080p H.264 与 HEVC Main，
  结果与软件解码逐像素一致。HEVC Main10 在捕获缓冲区初始化时返回 `EINVAL`。
  VA-API、mpv、零拷贝显示和音画同步见[视频说明](../video.zh.md)，不在本项检查内。
- Wi-Fi：5 GHz 连接协商到 80 MHz EHT、双空间流（PHY 速率约 1.1–1.3 Gbit/s）。
  吞吐量和 160/320 MHz 未测量。
- 蓝牙：LE 与 BR/EDR 扫描可用；配对和音频未验证。需配置本机蓝牙地址。
- 音频：六颗 CS35L43 功放全部绑定，ALSA 声卡提供两个播放 PCM 和一个录音 PCM，
  但没有 PipeWire 输出：声卡长名称与已安装 UCM 文件名不同，UCM 查找失败，
  只出现 Off/Pro Audio 配置。外放、录音和路由暂不可用。
- 相机：libcamera 可拍摄前置 OV32D40 3264×2448 场景和后置 S5KJN1 4080×3060 彩条。
  后摄实景画质、自动对焦、闪光灯、色彩校准和深度传感器未验证。
- Recovery 和普通系统可协商 10 Gb/s USB，持续吞吐量未测量。Recovery 需保留模块
  提供的 ADSP 固件；缺失时 Type-C/UCSI 无法启动，USB 限于 480 Mb/s。
- 内核日志包含启动早期的显示 SID SMMU fault、CPU 特性差异、CDSP 子系统事件/APM
  命令超时、音频警告及未启用后端 DAI 警告；均为已知现象，不代表新故障。

## 可选设置

Sheng 使用共享的正常系统 NCM、recovery ACM+NCM 策略。双角色和 Type-C 支持保留，
自动线缆角色切换仍需实机验证。设备模块也负责 WCN7850 P2P NetworkManager
排除规则。
通过 `hardware.sheng.wifiMacAddress` 提供本机已知的出厂地址。
`hardware.sheng.suspendWorkarounds.enable` 默认 `false`；显式启用后过滤
未使用的唤醒源，并在休眠前后重新加载 `ath12k_wifi7`。最小示例尚未验证休眠可用。
