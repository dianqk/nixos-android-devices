# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

打包的内核为 Linux 7.3-rc6。下文硬件结果基于此前的 7.x 内核取得。

## 硬件适配状态

“已配置”表示仓库提供了适配代码，不代表全新安装已经通过完整真机测试。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 芯片与启动 | SDM845 DTB、补丁内核、Android boot 与 recovery 镜像 | 已配置；镜像可构建 |
| UFS 与根文件系统 | initrd 中的 UFS 处理、ext4 userdata、GPT 分区名唯一性检查；可选实测存储角色 | 已配置；recovery 格式化/安装流程未经真机测试 |
| 显示与输入 | NT35596S 面板补丁、recovery 按键菜单、Niri 示例 | 桌面截图、两次启动的实体首帧及输出开关均通过；输入待验证 |
| GPU | Polaris 固件包与内核支持 | 1 倍缩放下 OpenGL（FD630）和 Vulkan（Turnip Adreno 630）短场景渲染通过；3 倍下 vkmark 超时 |
| 视频解码 | 带设备补丁的 FFmpeg V4L2 M2M | 180 秒 1080p H.264／HEVC 8-bit 无声视频完整硬解，帧数齐全且无解码错误 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与调制解调器 | 固件和经由 [`androidDevices.modem`](../modem.zh.md) 的 QRTR/RMTFS 服务；必须提供逐机[校准快照](radio-snapshot.zh.md)与身份数据 | 快照完整时：热点扫描、WPA2 关联、DHCP 取址与 HTTPS 请求均通过；-54 dBm 下接收速率 270 Mbit/s（VHT-MCS 6 40 MHz NSS 2）|
| 蓝牙 | 早期固件与可选的逐机身份配置 | 实时扫描附近设备通过；未测试配对或连接 |
| 音频 | ADSP 服务描述文件、TAS2559 驱动、ALSA UCM、PCM 采样对齐 | 物理 X2S 声卡及 MultiMedia1/2 PCM 检测通过；基础测试不播放或录音 |
| 相机 | 后置主摄 IMX363 与前置 OV5675，通过 CAMSS 和 libcamera 接入 | 两颗均可枚举并拍摄实际图像；已测试前摄 1296×972、后摄 1920×1080 输出，以及 `demo` 用户拍照 |
| 指纹、NFC、GNSS | 此处没有经过验证的用户流程 | 未验证 |
| 传感器 | SLPI、FastRPC、libssc/proxy 与旋转客户端 | 已配置；持续读数、物理方向与休眠恢复待验证（[配置方法](../sensors.zh.md)） |

FFmpeg 默认使用上游 nixpkgs。本文直接 V4L2 的验证记录针对保留的设备补丁版，
诊断时需按[可选 FFmpeg](../video.zh.md) 显式选择。

校准快照不完整时 MPSS 每 40 秒左右 fatal error 一次并自动重启，`wlan0` 因此
始终不出现——即使 Wi-Fi 本身的 probe 全部成功；`rmtfs` 会记录它打不开的文件。
详见[基带校准快照](radio-snapshot.zh.md)。快照完整时基带连续运行数小时无崩溃。
测试机上曾有一次开机在 USB 枚举之前卡住，强制断电重启后恢复，未再复现。
RMTFS 的校准写入仅保存在内存中，底层快照保持只读。完整断电仍未验证。

## 相机

示例安装 libcamera 的 `cam` 命令行工具。先枚举相机，再使用对应传感器的编号：

```sh
cam --list
cam -c 1 --stream role=still,width=1296,height=972,pixelformat=RGB888 --capture=30 --file=/tmp/front.ppm
cam -c 2 --stream role=still,width=1920,height=1080,pixelformat=RGB888 --capture=30 --file=/tmp/rear.ppm
```

命令将最后一帧保存为 PPM，可通过 `scp root@172.16.42.1:/tmp/front.ppm .` 取回。
管线使用通用软件 ISP，可用时通过 GPU 解 Bayer。色彩／降噪调校、自动对焦、
OIS、闪光灯和后置辅助传感器尚未实现或验证。
[基础相机测试](../../tests/basic/README.zh.md) 使用 `--min-cameras 2` 检查两条管线，
不拍照；`--skip camera` 可跳过。
