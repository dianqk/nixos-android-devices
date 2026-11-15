# 支持状态：小米平板 4 LTE（clover）

[English](status.md) · [设备指南](README.zh.md) · [硬件支持](hardware.zh.md)

由 `tools/status-pages.py` 根据 [`status.toml`](status.toml) 生成；请修改该文件后重新生成。

| 设备 | SoC | 内核 | 最后更新 |
| --- | --- | --- | --- |
| 小米平板 4 LTE（clover） | Qualcomm SDM660 | Nixpkgs Linux 7.3 及 Clover 补丁 | 2026-11-01 |

## 概览

| Works | Partial | Broken | Untested | N/A |
| --- | --- | --- | --- | --- |
| 10 | 5 | 6 | 17 | 4 |

## 启动与存储

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 已安装系统启动（U-Boot、systemd-boot、Linux） | Works | ABL → U-Boot（boot）→ FAT `system` 上的 systemd-boot → Linux 7.3，根分区为 `userdata`。 |
| 系统代际更新与回滚 | Works | 更新与回滚均启动所选代际；`boot` 保持不变。 |
| RAM recovery | Works | ABL 启动 `recovery`：同一 U-Boot 加 FIT ramdisk（LZMA 内核、xz initrd），低于 ABL 的 35 MiB ramdisk 上限。SSH 主机密钥持久保存。 |
| 从 recovery 首次安装 | Works | `format-root`、`prepare-boot` 和 `install-initial`（含续装）完成安装并成功启动。 |
| 重启到 bootloader 或 recovery | Works | 重启参数 `bootloader` 与 `recovery` 可进入 ABL fastboot 和 RAM recovery。EFI 菜单项未测试。 |
| 内部存储 | Works | eMMC HS400；原厂 GPT 保持不变。 |
| microSD 卡 | Untested | SDHCI 控制器已启用；未测试存储卡。 |

## 显示与输入

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 内置屏幕 | Works | NT51021 DSI 面板经 MSM DRM 以 1200×1920 显示。 （2026-10-30 验证。） |
| 背光与熄屏 | Untested | 亮度调节未检查。软件显示登录界面 60 秒后 DPMS 关闭。 |
| 触摸屏 | Untested | FT5x06 在较早镜像上通过；当前 Niri 会话待检查。 |
| 实体按键 | Untested | 电源、音量和霍尔输入设备已枚举；桌面中的动作未测试。 |
| 外接显示（USB-C DisplayPort） | N/A |  |

## 图形与多媒体

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| OpenGL ES 加速 | Untested | Freedreno（Adreno 512）已加载；屏幕渲染与性能尚未验证。 |
| Vulkan 加速 | Broken | Mesa Turnip 不支持 Adreno 5xx。 |
| 硬件视频解码 | Untested | Venus 已创建 V4L2 设备；解码尚未测试。 |
| 扬声器 | Broken | SDM660 UCM 没有扬声器路由。 |
| 耳机 | Untested | 已有 UCM 耳机路由；播放未验证。 |
| 麦克风 | Untested | 已有 UCM 麦克风路由；录音未验证。 |
| 摄像头 | Broken | 尚未集成拍摄管线。 |
| 闪光灯 | N/A |  |

## 连接

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Wi-Fi | Partial | WCN3990 以 VHT80 2x2 连接，断开重连正常（iwd 需 ControlPortOverNL80211=false）。Wi-Fi 连接时若内存严重不足，平板会重启；运行 WLAN 固件的调制解调器在开机后有时会重启数次，使 Wi-Fi 最多延迟约 2 分钟可用。 |
| 蓝牙 | Partial | 发现、使用认证密钥的 SSP 配对和 L2CAP 回显可用；未测试音频或输入配置文件，也未证实链路加密。 |
| USB 网络（设备模式） | Works | 系统与 recovery 中 NCM、DHCP 和 SSH 均可用。 |
| USB 主机 / OTG | Untested | VBUS 输出与主机枚举未验证。 |
| 移动数据 | Broken | 调制解调器已运行，但未启用 IPA 或蜂窝数据路径。 |
| 语音通话 | Untested | 无电话软件栈；尚未确认 LTE 型号是否支持语音。 |
| 短信 | Broken | 未启用短信路径。 |
| 卫星定位（GPS） | Untested | 无定位结果，也无用户空间集成。 |
| NFC | N/A |  |

## 电源与性能

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 电池状态 | Partial | PMI8998 电量计读数合理；放电尚未测试。 |
| 充电 | Partial | 可从 USB 主机端口充电并报告外部供电；完整充电周期尚未测试。 |
| 挂起 | Broken | 带 RTC 唤醒闹钟的 s2idle 测试 5 分钟内未返回；系统策略已禁用挂起。 |
| 关机与重启 | Partial | 重启可重复成功；关机与冷启动尚未验证。 |
| CPU 频率调节 | Works | OSM 与闭环 CPRh 电压控制配合 schedutil 在完整频率表内调频：小核最高 1843.2 MHz，大核最高 2208 MHz。Geekbench 7 单核 389 / 多核 1036： [Geekbench 7](https://browser.geekbench.com/v7/cpu/770857) |
| 温度管理 | Works | 全核持续负载下，CPU 冷却映射在 70 °C 被动阈值处为两个簇降频；GPU 使用 devfreq。 |

## 传感器与反馈

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 加速度计（自动旋转） | Untested | Linux 中未暴露该传感器（无 IIO 设备）。 |
| 磁力计 | Untested | Linux 中未暴露该传感器（无 IIO 设备）。 |
| 环境光传感器 | Untested | Linux 中未暴露该传感器（无 IIO 设备）。 |
| 距离传感器 | Untested | 尚未确认是否有该传感器。 |
| 霍尔传感器（保护套） | Untested | 霍尔输入已枚举；保护套行为未测试。 |
| 振动 | Untested | 尚未确认是否有振动马达。 |
| 指纹识别 | N/A |  |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| Works | 完整功能已通过真机测试。 |
| Partial | 部分功能可用，或仍有已知的可靠性或覆盖缺口。 |
| Broken | 硬件存在，但缺少集成或无法使用。 |
| Untested | 硬件存在，但尚无足够的真机测试结果。 |
| N/A | 设备没有此硬件。 |
