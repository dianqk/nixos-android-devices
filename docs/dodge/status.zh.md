# 支持状态：一加 13（dodge）

[English](status.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 一加 13（dodge） | Qualcomm SM8750 (Snapdragon 8 Elite) | Linux 7.3.1 及 Dodge 补丁 | 2026-11-09 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 17 | 11 | 0 | 14 | 0 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | B 槽 U-Boot 经 systemd-boot 启动 NixOS；保留 Android A 槽。 |
| 系统代际更新与回滚 | Partial | 系统代际更新可正常启动；手动回滚尚未测试。 |
| RAM recovery | Works | 独立的主机提供 RAM recovery 可在 ESP 已写入时启动，并提供 USB SSH。 |
| 从 recovery 首次安装 | Works | Recovery 可准备根分区和启动分区，并安装可启动的 NixOS 闭包。 |
| 重启到 bootloader 或 recovery | Partial | 可重启到原厂 bootloader；重启到 recovery 的操作尚未测试。 |
| 内部存储 | Works | UFS 承载已安装的 ext4 根文件系统和 FAT 启动文件系统。 |
| microSD 卡 | Untested |  |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | （2026-11-08 验证。） |
| 背光与熄屏 | Works | 亮度调节及屏幕熄灭/唤醒可用。 （2026-11-07 验证。） |
| 触摸屏 | Works | 已修正触点释放解析和驱动移除时的内存所有权。 （2026-11-08 验证。） |
| 实体按键 | Works | 电源键及音量加减键可用。 （2026-11-07 验证。） |
| 外接显示（USB-C DisplayPort） | Works | DASUNG 可使用原生 3200x1800、约 40 Hz；显示器独立供电，不为手机充电。 （2026-11-10 验证。） |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Partial | 桌面使用 Adreno 加速；尚未运行 GL 基准测试。 |
| Vulkan 加速 | Partial | GPU 时钟校准修正后的 Geekbench 6.7.1 Preview Vulkan 计算成绩为 15159。修正前的成绩：[默认设置 8534](https://browser.geekbench.com/v6/compute/6966589)，[启用诊断着色器 IR 日志 8750](https://browser.geekbench.com/v6/compute/6966684)。实际计算时钟恢复至约 1.1 GHz。图形渲染仍未验证。 [Geekbench 6](https://browser.geekbench.com/v6/compute/6966777) |
| 硬件视频解码 | Partial | VA-API 硬件解码通过 H.264、HEVC、VP9 和 AV1 逐帧比较；可见播放效果尚未验证。 |
| 扬声器 | Works | 内置扬声器播放可用，驱动保留固定的硬件音量上限。 （2026-11-09 验证。） |
| 耳机 | Untested |  |
| 麦克风 | Untested |  |
| 摄像头 | Partial | 前置相机已支持 RAW10 采集；后置相机和应用预览尚未支持。 |
| 闪光灯 | Untested |  |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works |  |
| 蓝牙 | Works | 经认证的 BLE 键盘/鼠标输入及 A2DP/AVRCP/HFP 耳机配置可用。 |
| USB 网络（设备模式） | Works | USB NCM 提供 SSH 访问。 |
| USB 主机 / OTG | Works | 手机供电的 USB2 集线器和键盘可与四通道 DisplayPort 同时使用；USB3 恢复和鼠标输入尚未测试。 （2026-11-10 验证。） |
| 移动数据 | Works | LTE 和 5G SA 数据可传输 HTTPS 流量。 |
| 语音通话 | Untested |  |
| 短信 | Works | 可经 IMS 接收和发送短信。 |
| 卫星定位（GPS） | Untested |  |
| NFC | Untested |  |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | 可读取电量、电压和电流；放电行为尚未测试。 |
| 充电 | Partial | 电池未满时 USB 充电可报告正向电池电流；完整充电周期仍未验证。 |
| 挂起 | Partial | 禁用 SS3 后，保留模式 s2idle 可通过 RTC 唤醒并恢复；启用 SS3 系统断电仍会导致重置。低功耗和长时间待机尚未验证。 |
| 关机与重启 | Partial | 正常重启可用；关机及之后的冷启动尚未测试。 |
| CPU 频率调节 | Works | schedutil 可调节两个簇的频率，启用 boost 后最高为 3.5328 GHz 和 4.32 GHz。CPU 容量和 boost 修正后的 Geekbench 7.0.0 Preview 成绩为单核 2505 / 多核 8696；[先前基线为 1660 / 8992](https://browser.geekbench.com/v7/cpu/831184)。[Geekbench 6.7.1 Preview 成绩为单核 2811 / 多核 8822](https://browser.geekbench.com/v6/cpu/19447918)。 [Geekbench 7](https://browser.geekbench.com/v7/cpu/832733) |
| 温度管理 | Partial | 温度传感器可报告读数；持续负载下的热节流尚未验证。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | SSC 加速度计可提供采样；物理方向尚未验证。参见[传感器](sensors.md)。 |
| 磁力计 | Untested |  |
| 环境光传感器 | Untested |  |
| 距离传感器 | Untested |  |
| 霍尔传感器（保护套） | Untested |  |
| 振动 | Untested |  |
| 指纹识别 | Untested |  |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
