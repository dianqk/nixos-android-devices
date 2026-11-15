# 支持状态：小米 Redmi Note 12 Turbo / POCO F5（marble）

[English](status.md) · [设备指南](README.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米 Redmi Note 12 Turbo / POCO F5（marble） | Qualcomm SM7475 (Snapdragon 7+ Gen 2) | Linux 7.3 及 Marble 补丁 | 2026-11-02 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 6 | 11 | 3 | 20 | 2 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（`boot_b`）→ `linux-boot` ESP 上的 systemd-boot → Linux 7.3；U-Boot 将槽位 B 标记为成功。 |
| 系统代际更新与回滚 | Partial | 新代际默认启动；尚无回滚到旧代际的记录。 |
| RAM recovery | Partial | recovery 通过 `fastboot boot` 仅在内存中启动，USB SSH 与存储操作可用；尚未安装到独立分区。 |
| 从 recovery 首次安装 | Works | `prepare-install`、`format-root` 和 `install-initial` 安装的系统可从 `boot_b` 启动。 |
| 重启到 bootloader 或 recovery | Partial | 从 recovery 重启到 bootloader 可进入 fastboot；recovery 参数和已安装系统的重启模式未检查。 |
| 内部存储 | Partial | 根分区与 ESP 位于 UFS；针对高负载下 UFS 链路故障的修复仅通过了短时写入与挂起测试。 |
| microSD 卡 | N/A | 该手机没有 microSD 卡槽。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Untested | 面板曾在诊断内核上显示桌面；之后发布内核的修复仅经软件检查。 |
| 背光与熄屏 | Untested | 亮度值与 DPMS 关闭/开启在软件中生效；面板上的效果尚未验证。 |
| 触摸屏 | Untested | Goodix 触摸屏可上报输入；桌面中的映射尚未验证。 |
| 实体按键 | Untested | 电源键与音量键在 U-Boot 中可用，电源键可从挂起唤醒；桌面中的操作尚未验证。 |
| 外接显示（USB-C DisplayPort） | N/A |  |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Untested | 软件检查显示 niri 桌面经 Adreno GPU 渲染；当前内核的屏幕输出尚未验证，也未运行 GL 基准测试。 |
| Vulkan 加速 | Untested |  |
| 硬件视频解码 | Untested | Iris 解码 H.264、HEVC 和 VP9 的帧与软件解码一致；屏幕播放尚未验证。 |
| 扬声器 | Works | 两个扬声器均能以原厂音量清晰播放音乐；没有扬声器保护，请保持适中音量。 （2026-10-25 验证。） |
| 耳机 | Broken | 有线耳机通路（耳机、耳机麦克风、插孔检测）尚未移植。 |
| 麦克风 | Partial | 底部麦克风可录到信号；其他麦克风尚未配置。 （2026-10-25 验证。） |
| 摄像头 | Partial | 主摄、超广角、微距与前置摄像头可通过 libcamera 与 PipeWire 以 30 fps 拍摄 RAW 与处理后的图像（一次一个）。画面方向与色彩尚未验证；自动对焦、闪光灯与画质调校尚未实现。 |
| 闪光灯 | Untested |  |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | WCN6855 可关联并传输数据；八次唤醒中有两次固件崩溃后自动恢复。 |
| 蓝牙 | Partial | 可通过安全简易配对进行配对。连接耳机时，音频播放（A2DP，含 LDAC）和遥控（AVRCP 双向音量、播放与暂停）可用。免提音频（HFP）可使用 CVSD、mSBC 和 LC3-SWB 连接并双向传输音频；发往耳机的音频基本正常，但耳机麦克风方向有断音和咔嗒声。 |
| USB 网络（设备模式） | Works | RAM recovery 和已安装系统中均可通过 USB NCM 使用 SSH。 |
| USB 主机 / OTG | Untested |  |
| 移动数据 | Untested | 调制解调器可启动且 ModemManager 能识别；尚无 SIM 卡测试记录。 |
| 语音通话 | Broken | 语音通话音频通路尚未移植。 |
| 短信 | Untested |  |
| 卫星定位（GPS） | Broken | 定位需要打过补丁的 libqmi 与 ModemManager，尚未集成。 |
| NFC | Untested | 尚未配置。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | 电池管理器上报容量与电量计数，已用于挂起耗电测量；完整放电未检查。 |
| 充电 | Partial | 从 USB 充电下行端口（CDP，输入限流 1.45 A）以约 1.3 A 充电；快充适配器与充满尚未检查。 |
| 挂起 | Partial | s2idle 可进入 SoC 睡眠并由 RTC 和电源键唤醒；耗电约 100 mA，UFS 唤醒修复仍在测试中。 |
| 关机与重启 | Partial | 重启可用；尚无关机后冷启动的记录。 |
| CPU 频率调节 | Works | 三个 `schedutil` 策略分别可达 1.80、2.50 与 2.92 GHz；负载下 DDR 可达 3196 MHz。 [Geekbench 7](https://browser.geekbench.com/v7/cpu/782476) |
| 温度管理 | Untested |  |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | BMI26x 可上报方向，屏幕在四个方向均已旋转；屏幕上的旋转效果尚未验证。 |
| 磁力计 | Untested | 已配备 QMC630x，但尚未配置。 |
| 环境光传感器 | Untested | 已配备 TCS3701，但尚未配置。 |
| 距离传感器 | Untested | 尚未确定是否有物理距离传感器；Android 使用虚拟距离传感器。 |
| 霍尔传感器（保护套） | Untested | 尚未确定是否存在。 |
| 振动 | Untested | 已构建 PM8350B 振动驱动；未测试振动。 |
| 指纹识别 | Untested |  |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
