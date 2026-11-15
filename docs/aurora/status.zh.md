# 支持状态：小米 14 Ultra（aurora）

[English](status.md) · [设备指南](README.zh.md) · [硬件支持](hardware.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米 14 Ultra（aurora） | Qualcomm SM8650 (Snapdragon 8 Gen 3) | Linux 7.3 及 Aurora 补丁 | 2026-10-30 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 17 | 10 | 6 | 7 | 2 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（`boot_b`）→ FAT `linux-boot` ESP 上的 systemd-boot → Linux 7.3，根分区为 `linux`；A 槽保留 Android。 |
| 系统代际更新与回滚 | Works | 回滚到旧代际并再切回均成功启动；`boot_b` 保持不变。 |
| RAM recovery | Works | Recovery 从 `recovery_b` 独立于 U-Boot 启动，提供 USB NCM/SSH，主机密钥持久保存。 |
| 从 recovery 首次安装 | Works | `prepare-install` 划分原 userdata 空间；安装与首次 EFI 启动均通过。 |
| 重启到 bootloader 或 recovery | Works | 重启参数 `bootloader` 与 `recovery` 可进入 OEM fastboot 和已安装的 recovery。 |
| 内部存储 | Works | UFS（MCQ）；Android A、super 与校准分区保持不变。 |
| microSD 卡 | N/A | 设备没有 microSD 卡槽。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | N1 1440×3200 DSC 面板，支持 30/60/120 Hz；进入 Linux 控制台前仍有短暂花屏闪烁。 （2026-10-09 验证。） |
| 背光与熄屏 | Works | 亮度滑块与熄屏/亮屏可用，唤醒后无花屏。 （2026-10-09 验证。） |
| 触摸屏 | Works | 内核驱动支持 Android 16 控制器固件；防误触与边缘未测试。 （2026-10-24 验证。） |
| 实体按键 | Untested | 电源与音量键已枚举，电源键可从挂起唤醒；桌面动作未检查。 |
| 外接显示（USB-C DisplayPort） | Works | DP 显示器可显示桌面；DP 音频、其他模式与热插拔未测试。 （2026-10-08 验证。） |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Works | Adreno 750 经 Freedreno 渲染桌面；glmark2 校验在原 Android 14 底层上通过。 （2026-10-24 验证。） |
| Vulkan 加速 | Untested | vkmark 经 Turnip 运行无故障；屏幕输出尚未验证。 |
| 硬件视频解码 | Partial | 基于 Iris V4L2 的 VA-API 在原 Android 14 底层上可播放普通视频；尚未在 Android 16 上复查。 （2026-10-08 验证。） |
| 扬声器 | Partial | 立体声音乐在原 Android 14 底层上可经扬声器播放；尚未在 Android 16 上复查。 （2026-10-08 验证。） |
| 耳机 | N/A | 无 3.5 mm 耳机孔。 |
| 麦克风 | Untested | 麦克风录音未验证。 |
| 摄像头 | Partial | 四个后置摄像头可通过 libcamera 与 PipeWire 以 30 fps 拍摄 RAW 与处理后的图像（一次一个）；前置摄像头尚未启用。自动对焦、防抖与画质调校尚未实现。 |
| 闪光灯 | Broken | 尚未集成闪光灯驱动。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | WCN7850 可在 5 GHz（EHT）关联、获取 DHCP 并传输数据；挂起恢复后可重连。 |
| 蓝牙 | Partial | BR/EDR 与 LE 配对、L2CAP 数据和 GATT 读取可用；音频与 HID 配置文件未测试。 |
| USB 网络（设备模式） | Works | 系统与 recovery 中 NCM、DHCP 和 SSH 均可用，系统中可达 5 Gbit/s。 |
| USB 主机 / OTG | Broken | 尚不支持 USB 主机模式和数据角色切换。 |
| 移动数据 | Works | 实验性可选功能：LTE/5G NR 注册，IPv4 与 IPv6 数据可用。 |
| 语音通话 | Broken | 尚未集成语音（VoLTE/IMS）软件栈。 |
| 短信 | Partial | 收发短信在原 Android 14 底层上可用；尚未在 Android 16 上复查。 |
| 卫星定位（GPS） | Untested | 尚未获得定位结果。 |
| NFC | Broken | 尚未集成 NFC 驱动。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Works | ADSP 电池遥测一致；电荷计数随放电按较粗步进变化。 |
| 充电 | Partial | 已观察到 9 V USB PD 充电；尚无完整充电周期，且不支持无线充电。 |
| 挂起 | Works | s2idle 待机 2 小时以上可正常恢复，约 28 mA；`deep` 不可用。 |
| 关机与重启 | Partial | 重启现已可靠完成；关机与冷启动尚未验证。 |
| CPU 频率调节 | Partial | 四个 CPU 策略在负载下均达到最高频率，空闲后回落；性能尚未经基准测试。 |
| 温度管理 | Partial | 可读取温度；持续负载下的降频未验证。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Works | SSC 加速度计驱动桌面旋转；在 Android 16 上仅做了软件复查。 （2026-10-07 验证。） |
| 磁力计 | Untested |  |
| 环境光传感器 | Partial | 前置传感器向自动亮度提供照度；亮度曲线跟随未验证。 |
| 距离传感器 | Untested | 尚未确认是否有该传感器。 |
| 霍尔传感器（保护套） | Untested | 尚未确认是否有该传感器。 |
| 振动 | Broken | 尚未集成振动马达驱动。 |
| 指纹识别 | Broken | 尚未集成指纹驱动。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
