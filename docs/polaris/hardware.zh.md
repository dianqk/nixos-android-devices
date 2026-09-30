# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库提供了适配代码，不代表全新安装已经通过完整真机测试。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 芯片与启动 | SDM845 DTB、补丁内核、Android boot 与 recovery 镜像 | 已配置；镜像可构建 |
| UFS 与根文件系统 | initrd 中的 UFS 处理、ext4 userdata、GPT 分区名唯一性检查；可选逐机精确契约 | 已配置；另一台设备的首次格式化与安装尚未真机验证 |
| 显示与输入 | NT35596S 面板补丁、recovery 按键菜单、Sway 示例 | Sway 截图、两次启动的实体首帧及输出开关均通过；输入待验证 |
| GPU | Polaris 固件包与内核支持 | 1 倍缩放下 OpenGL（FD630）和 Vulkan（Turnip Adreno 630）短场景渲染通过；3 倍下 vkmark 超时 |
| 视频解码 | 带设备补丁的 FFmpeg V4L2 M2M | 180 秒 1080p H.264／HEVC 8-bit 无声视频完整硬解，帧数齐全且无解码错误 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与调制解调器 | 固件和 QRTR/RMTFS 服务；逐机校准与身份数据可选配置 | 提供逐机数据后，实时热点扫描通过；未测试连接 |
| 蓝牙 | 早期固件与可选的逐机身份配置 | 实时扫描附近设备通过；未测试配对或连接 |
| 音频 | ADSP 服务描述文件、TAS2559 驱动、ALSA UCM、PCM 采样对齐 | 物理 X2S 声卡及 MultiMedia1/2 PCM 检测通过；基础测试不播放或录音 |
| 相机 | 后置主摄 IMX363 与前置 OV5675，通过 CAMSS 和 libcamera 接入 | 两颗均可枚举并拍摄实际图像；已测试前摄 1296×972、后摄 1920×1080 输出，以及 `demo` 用户拍照 |
| 指纹、NFC、GNSS | 此处没有经过验证的用户流程 | 未验证 |

视频播放器可使用 `config.androidDevices.video.ffmpegPackage`，以保留设备的 V4L2 解码修复。
启用蓝牙时，将 `hardware.polaris.radio.bluetoothIdentityFile` 设置为设备上的蓝牙地址文件路径；该服务会等待蓝牙控制器并验证地址生效。

重启后 modem 启动偶发 XPU 故障，可能导致 Wi-Fi 初始化失败。
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
