# 支持状态：酷比魔方 iPlay 80 mini Ultra（t880）

[English](status.md) · [设备指南](README.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 酷比魔方 iPlay 80 mini Ultra（t880） | MediaTek MT6897 (Dimensity 8300) | Linux 7.3.1 及 T880 补丁 | 2026-11-10 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 16 | 13 | 8 | 4 | 1 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | 原厂 LK → U-Boot（`boot_a`）→ FAT `linux-boot` 上的 systemd-boot → Linux，根分区为 `linux`；Android 保留在 B 槽。 |
| 系统代际更新与回滚 | Works | 新代际默认启动，回滚可启动旧代际；`boot_a` 保持不变。 |
| RAM recovery | Partial | 通过 U-Boot USB fastboot 启动主机提供的 RAM recovery；需要 A 槽 U-Boot 正常。 |
| 从 recovery 首次安装 | Works | `prepare-install`、`install-image` 和 `install-initial` 完成安装并成功启动。 |
| 重启到 bootloader 或 recovery | Works | 重启参数 `bootloader` 与 `recovery` 可进入 LK fastboot 和 RAM recovery；U-Boot 菜单按键未测试。 |
| 内部存储 | Works | UFS 4.0 以 HS-G5 x2 运行，使用八个硬件队列（MCQ）；顺序读取可达 4.3 GB/s。Linux 分区从原 userdata 空间中划分。 |
| microSD 卡 | Partial | 存储卡可在 UHS-I SDR104 下识别、读取并热拔出；挂载与写入未测试。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Partial | mediatek-drm 以 1600×2560、60-144 Hz 显示；显示电源关闭再开启后可恢复清晰画面；偶发半屏黑屏启动的问题仍未解决。 （2026-10-17 验证。） |
| 背光与熄屏 | Partial | PWM 亮度调节支持 1024 级。显示电源关闭偶有无法完成。 （2026-10-15 验证。） |
| 触摸屏 | Works | Novatek NT36523N 多点触控在桌面中可用。 （2026-10-15 验证。） |
| 实体按键 | Partial | 电源键和音量键可产生事件；电源键用于切换显示电源，受上述显示问题影响，音量动作仍需音频支持。 （2026-10-16 验证。） |
| 外接显示（USB-C DisplayPort） | Partial | 720p60、1080p60、1440p60 和 4K30 信号源模式可通过 1080p60 采集设备输出画面，屏幕关闭/开启和重复启动正常；物理重插和其他显示器尚未测试。 |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Works | panthor 配合支持 Mali v11 的 Mesa 渲染桌面；glmark2 在 265 MHz-1.4 GHz 下运行。 （2026-10-16 验证。） |
| Vulkan 加速 | Untested | PanVK（未通过一致性认证）在软件检查中通过 dEQP-VK 子集和 vkmark；屏幕输出尚未验证。 |
| 硬件视频解码 | Partial | V4L2/VA-API 支持 8 位 H.264/HEVC、VP9 profile 0 和 AV1 Main 解码，包括裁剪、跳转及稳定的导出缓冲区。CPU 转换及重放可能开销较大；不提供 10 位及 VP8。 |
| 扬声器 | Broken | 尚未集成 AFE 和 AW88261 功放。 |
| 耳机 | Broken | 有线耳机使用 USB-C 模拟音频，尚未集成。 |
| 麦克风 | Broken | 尚未集成 MT6368 编解码器及其麦克风。 |
| 摄像头 | Broken | 没有可用的摄像头 ISP 驱动。 |
| 闪光灯 | Broken | 尚未集成后置闪光灯驱动。 |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Works | 使用树外 connsys 驱动和原厂固件文件；可通过 Wi-Fi 使用 SSH。 |
| 蓝牙 | Partial | A2DP（LDAC）、AVRCP 音量和播放控制以及 BLE 键盘/鼠标输入可用。音频偶有中断；可选的 mSBC 和 CVSD 均支持双向音频，CVSD 还偶有短暂杂音。控制器空闲休眠、唤醒及 BlueZ 关闭后重开可用；经典蓝牙 HIDP 尚未测试。 |
| USB 网络（设备模式） | Works | 系统与 recovery 中 NCM、DHCP 和 SSH 均可用，速率为 SuperSpeed。 |
| USB 主机 / OTG | Untested | 端口可切换为主机角色并绑定 xHCI；尚未测试 USB 设备。 |
| 移动数据 | Works | 通过 ModemManager 使用 5G NR 与 LTE 数据；调制解调器每次启动只启动一次。 |
| 语音通话 | Broken | 尚未集成语音通话和调制解调器音频通路。 |
| 短信 | Works | 在 5G NR（经 IMS）和 LTE 下均可收发。 |
| 卫星定位（GPS） | Broken | GNSS 依赖闭源厂商用户态，尚未集成。 |
| NFC | Untested | 尚未确认是否有此硬件。 |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | 充电时 MT6375 电量计数值合理；未插电放电检查待完成。 |
| 充电 | Partial | 约 9 W 的受限 5 V 充电可用，并在硬件终止时结束；电池养护可选但默认关闭；启用后插电时将电量保持在 75-80 %（`nexusctl battery full-charge` 可一次性充满）。 |
| 挂起 | Broken | 尚未实现挂起；仅 CPU 核心空闲状态可用。 |
| 关机与重启 | Works | 关机与重启均可完成；连接 USB 时设备会自行重新开机。 |
| CPU 频率调节 | Works | `mtk-cpufreq-hw` 与 schedutil 将三个簇分别调至最高 2.2、3.2 与 3.35 GHz（最高档时超大核实际约 3.0 GHz，与原厂 Android 相同）；单核吞吐量与原厂 Android 相同。持续负载下固件温度目标会限制 CPU，多核成绩因此较低。Geekbench 7 单核 1247 / 多核 3565： [Geekbench 7](https://browser.geekbench.com/v7/cpu/645266) |
| 温度管理 | Works | 28 个 LVTS 温区；CPU 与 GPU 在约 95 °C 降频；没有机身表面温度控制。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Partial | 自动旋转会跟随设备，但方向相差 180°；方向修正待手动测试。 （2026-10-20 验证。） |
| 磁力计 | Partial | QMC6308 经 SCP 传感器中枢作为 IIO 磁力计（`scp-magn`）提供；随方向变化的读数尚未验证。ICM4N607 陀螺仪以 `scp-gyro` 提供。 |
| 环境光传感器 | Works | JSA1130 经 SCP 传感器中枢作为 IIO 照度提供；可选自动亮度。 |
| 距离传感器 | N/A | 原厂传感器列表中没有距离传感器。 |
| 霍尔传感器（保护套） | Partial | 可报告保护套开合并熄屏；一次测试在多次开合后卡死。 （2026-10-20 验证。） |
| 振动 | Works | MT6368 VIBR 电源上的 `regulator-haptic`。 （2026-10-16 验证。） |
| 指纹识别 | Untested | 尚未确认是否有此硬件；厂商设备树含 Goodix 节点，未集成驱动。 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
