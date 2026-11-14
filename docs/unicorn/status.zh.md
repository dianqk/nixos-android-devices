# 支持状态：小米 12S Pro（unicorn）

[English](status.md) · [设备指南](README.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米 12S Pro（unicorn） | Qualcomm SM8475 (Snapdragon 8+ Gen 1) | Linux 7.3.4；真机结果来自 Linux 7.3-rc6 | 2026-11-17 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 8 | 8 | 3 | 22 | 1 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | boot_b 中的 U-Boot 经 systemd-boot 启动已安装系统；ESP 与根分区占用原 userdata 空间。 |
| 系统代际更新与回滚 | Partial | EFI 系统代更新无需重写 U-Boot；尚无完整回滚测试记录。 |
| RAM recovery | Partial | 已验证独立 recovery 启动；完整 USB SSH 与存储流程仍需在当前内核复验。 |
| 从 recovery 首次安装 | Untested | 已实现 Linux 独占布局；尚无完整 prepare-install 与 install-initial 流程的实测记录。 |
| 重启到 bootloader 或 recovery | Untested | 已配置 bootloader 与 recovery 重启目标；两条路径仍需实测。 |
| 内部存储 | Works | UFS 启动与有限文件读写通过；linux-boot 与 linux 从 userdata 划分。 |
| microSD 卡 | N/A | 手机没有 microSD 卡槽。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | 1440×3200 DSC 面板支持 24/30/40/60/90/120 Hz，默认 60 Hz。 |
| 背光与熄屏 | Works | 已验证亮度调节、熄屏/亮屏及可选的 60↔120 Hz 切换；其他活动切换仍为实验功能。 |
| 触摸屏 | Works | ST FingerTipS SPI 驱动提供多点触控。 |
| 实体按键 | Partial | 已实现控制台音量、电源短按熄亮屏与长按关机；桌面动作需要另行配置与测试。 |
| 外接显示（USB-C DisplayPort） | Untested | USB-C DisplayPort 板级通路未验证，尚未启用。 |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Partial | Adreno 730 经 Freedreno 渲染；尚无完整屏幕 GL 基准验证记录。 |
| Vulkan 加速 | Untested | 尚未验证屏幕 Vulkan 渲染。 |
| 硬件视频解码 | Untested | 尚未验证硬件视频播放。 |
| 扬声器 | Works | 单独提供私有固件、校准与 Music 数据后，内置扬声器播放可用。 |
| 耳机 | Broken | USB-C 模拟耳机路由不完整；数字 USB-C 配件也未验证。 |
| 麦克风 | Works | 提供私有音频运行时输入后，已验证内置麦克风录音与回放。 |
| 摄像头 | Partial | JN1 超广角与长焦可采集 RAW10；前摄/主摄识别 NACK。Bayer、曝光、软件 ISP、自动对焦与 OIS 仍未验证或未实现。 |
| 闪光灯 | Untested | 尚未验证闪光灯。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | 2.4/5 GHz 连接、传输与重连通过；NetworkManager 提供稳定本地地址。 |
| 蓝牙 | Partial | 单独提供原厂地址后，配对、耳机播放与 RFCOMM 传输可用；固件下载可能超时。HFP 及 Wi-Fi/音频并用未验证。 |
| USB 网络（设备模式） | Partial | 已配置 NCM 与可选 ACM；实际 USB 枚举、DHCP 与 SSH 仍需随当前角色管理器复验。 |
| USB 主机 / OTG | Untested | 已实现固件协商的 USB2 主机模式；外设使用与 VBUS 供电仍未验证。 |
| 移动数据 | Untested | 尚未验证蜂窝数据。 |
| 语音通话 | Broken | 未提供语音通话集成。 |
| 短信 | Untested | 尚未验证短信。 |
| 卫星定位（GPS） | Untested | 尚未验证定位结果。 |
| NFC | Untested | 包含 SN NCI 读卡模式驱动；标签与读卡操作未验证。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Untested | 已实现板级 ADSP 电池遥测；尚无完整放电验证记录。 |
| 充电 | Untested | 已实现认证与输入遥测；完整充电周期、充电泵工作与 120 W 峰值仍未验证。 |
| 挂起 | Partial | 有限挂起恢复检查通过；待机功耗与完整外设恢复未验证。 |
| 关机与重启 | Untested | 控制台侧键服务可请求正常关机；断电、冷启动与重复重启验收尚不完整。 |
| CPU 频率调节 | Untested | 尚未验证所有 CPU 集群在负载下的频率调节。 |
| 温度管理 | Untested | 已配置温控降频；持续负载下的限频未验证。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | 专用 SSC 数据与用户态传感器集成尚不完整。 |
| 磁力计 | Untested | 尚未验证传感器读数。 |
| 环境光传感器 | Untested | 尚未验证照度读数与自动亮度。 |
| 距离传感器 | Untested | 尚未确认传感器及其读数。 |
| 霍尔传感器（保护套） | Untested | 尚未确认是否存在该传感器。 |
| 振动 | Untested | 包含 AW86927 力反馈驱动；实际振动未验证。 |
| 指纹识别 | Broken | 未包含指纹驱动或服务。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
