# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库包含适配代码，不代表另一台平板已通过全新安装验证。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 启动与存储 | SM8475 内核/设备树、A/B boot 与 recovery、只读 GPT 规划器、`linux` ext4 根分区 | 已配置；另一台设备的首次安装未验证 |
| 显示与输入 | 面板、背光、触摸及 recovery 按键菜单 | 显示、背光和触摸已验证；实体菜单按键选择待验证 |
| DisplayPort | DP0、主 Type-C 端口和 FSA4480 AUX 开关 | Dell U2720Q EDID、HBR2 ×4 训练及 Sway 3840×2160 60 Hz 已验证；实体画面、反向插头和 DP 音频待验证 |
| GPU 与视频 | Adreno 和视频固件、内核驱动 | 开发设备通过 OpenGL/Vulkan 渲染和完整 180 秒 H.264/HEVC 8-bit 硬解 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与蓝牙 | WCN6855；OnePlus WLAN 核心固件配合仓库中的 TB320FC 板级数据 | 周边 Wi-Fi/蓝牙扫描通过；不覆盖配对和协议服务 |
| 音频 | CS35L45 扬声器、ALSA UCM 与拓扑 | 检测到物理 ALSA 播放接口；基础测试不播放音频 |
| microSD | 设备树支持 | 已配置；端到端使用未验证 |
| 相机 | HI1339 主后摄、S5K4H7 前摄、SC202CS 后置微距；CAMSS 与 libcamera 软件 ISP | 三摄配置、RAW 采集及重复启停通过；三摄实景照片已验证 |
| 其他传感器 | 暂无用户使用路径 | 未验证 |

内屏支持 2560×1600、120 Hz。自动
[B 槽启动成功确认](https://source.android.com/docs/core/architecture/bootloader/updating#support-for-slots)
尚未集成；未确认的重复启动可能耗尽 bootloader 重试次数并回退 Android A。

视频播放器可使用 `config.androidDevices.video.ffmpegPackage`，以保留设备的 V4L2 解码修复。

## 可选的无线身份

设备模块提供 `hardware.asphalt.radio.wifiAddressFile` 与
`bluetoothAddressFile`，默认均为 `null`。通过构建输入文件分别提供出厂 Wi-Fi
MAC 和保存的 Qualcomm Bluetooth NVM 地址；蓝牙文件采用控制器字节序，
服务会转换为 BlueZ 所需的显示字节序。身份数据保留在使用者自己的配置中。
Recovery 不运行这些初始化服务。

## 相机

示例安装了 `cam` CLI。用 `cam --list` 列出相机 ID；数字序号可能随启动改变。
对应路径末尾如下：

| 相机 | CCI 路径 | RAW 模式 |
| --- | --- | --- |
| HI1339 主后摄 | `cci@ac15000/i2c-bus@0/camera@20` | 4208×3120 GBRG10 |
| S5K4H7 前摄 | `cci@ac15000/i2c-bus@1/camera@10` | 3264×2448 GRBG10 |
| SC202CS 后置微距 | `cci@ac16000/i2c-bus@0/camera@36` | 1600×1200 BGGR10 |

需要拍照时，从列表选择完整 ID：

```console
cam --camera '<camera ID>' --stream role=viewfinder --capture=30 --file=/tmp/photo.ppm
```

三路 RAW 均约 30 fps。软件 ISP 使用通用、未校准参数；尚未实现自动对焦和闪光灯。
三摄均已验证实景拍摄。当前固定镜头位置和通用参数下，主后摄近景偏虚、画面偏暗；
尚未校准画质。[基础测试](../../tests/basic/README.zh.md)仅枚举和配置
相机；本设备使用 `--min-cameras 3`。

## DisplayPort

将支持 DP Alt Mode 的显示器连接到主 Type-C 端口（GLINK port 0）。
Linux 提供 `DP-1`，示例合成器同时启用它和 `DSI-1`；排列和缩放由合成器配置。
这不包含 U-Boot 或 generations 菜单的外屏显示支持。

USB3 共存、插头反向连接和显示器音频仍需实机验证。
