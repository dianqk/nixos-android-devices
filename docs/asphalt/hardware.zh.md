# 硬件支持

[返回使用指南](README.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库包含适配代码，不代表另一台平板已通过全新安装验证。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 启动与存储 | SM8475 内核/设备树、A/B boot 与 recovery、只读 GPT 规划器、`linux` ext4 根分区 | 已配置；另一台设备的首次安装未验证 |
| 显示与输入 | 面板、背光、触摸及 recovery 按键菜单 | 显示、背光和触摸已验证；实体菜单按键选择待验证 |
| DisplayPort | DP0、主 Type-C 端口和 FSA4480 AUX 开关 | Dell U2720Q EDID、HBR2 ×4 训练及 3840×2160 60 Hz 合成器输出已验证；实体画面、反向插头和 DP 音频待验证 |
| GPU 与视频 | Adreno 和视频固件、内核驱动 | 已验证 OpenGL/Vulkan 渲染、完整 180 秒 H.264/HEVC 8-bit 硬解，以及短时重复 720p/1080p 硬编码 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi 与蓝牙 | WCN6855；OnePlus WLAN 核心固件配合仓库中的 TB320FC 板级数据 | 周边 Wi-Fi/蓝牙扫描通过；不覆盖配对和协议服务 |
| 音频 | CS35L45 扬声器、ALSA UCM 与拓扑 | 检测到物理 ALSA 播放接口；基础测试不播放音频 |
| microSD | 设备树支持 | 已配置；端到端使用未验证 |
| 相机 | HI1339 主后摄、S5K4H7 前摄、SC202CS 后置微距；CAMSS 与 libcamera 软件 ISP | 三摄配置、RAW 采集及重复启停通过；三摄实景照片已验证 |
| 电池读数 | 经 pmic_glink 的 ADSP 电池管理器（`qcom-battmgr-bat`） | Linux 7.3.0-rc6 上状态、电量、电压和电流可读，且与放电过程一致。`power_now` 与电压 × 电流不符，不应显示；请用 `voltage_now` × `current_now` 计算功率。`charge_counter` 按电量百分比 × `charge_full` 量化；`charge_full` 与 `state_of_health` 的关系、上报的 USB 类型及充放电循环行为待验证（[充电](charging.zh.md)） |
| 挂起 | s2idle（`mem_sleep_default`）、UFS `spm_lvl` 5、具名唤醒源 | s2idle 进入、深度睡眠与唤醒已验证；电源键可唤醒，USB/电池事件暂不能唤醒（[详情](#挂起与唤醒)） |
| 传感器 | SLPI、FastRPC、libssc/proxy 与旋转客户端 | 已配置；持续读数、物理方向与休眠恢复待验证（[配置方法](../sensors.zh.md)） |

内屏支持 2560×1600、120 Hz。当前 U-Boot 从经检查的 ESP 加载指定 EFI 镜像后，
自动将 B 标记为成功。这发生在 Linux 启动之前，只确认 EFI 加载，不代表 Linux 健康。
若此确认无法完成，未确认的重复启动仍可能耗尽 bootloader 重试次数并回退 Android A。

FFmpeg 默认使用上游 nixpkgs。本文直接 V4L2 的验证记录针对保留的设备补丁版，
诊断时需按[可选 FFmpeg](../video.zh.md) 显式选择。

## 视频硬件编码

可选的设备补丁版 FFmpeg 提供 `h264_v4l2m2m` 和 `hevc_v4l2m2m`，这两个 8-bit 编码器
使用 NV12 输入。例如运行一次有限时长的 H.264 检查：

```console
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30:duration=3 \
  -vf format=nv12 -c:v h264_v4l2m2m -b:v 4M -y sample.h264
ffprobe -v error -count_frames -show_entries stream=width,height,nb_read_frames sample.h264
ffmpeg -v error -xerror -i sample.h264 -f null -
```

HEVC 使用 `-c:v hevc_v4l2m2m` 和 `sample.hevc`。上述输入恰好 90 帧，应同时
核对解码帧数与退出状态；独立的码流头包会使输出包数与图像帧数不同。
这些合成画面测试不包含屏幕采集或音频录制配置。

短时 720p 和 1080p H.264/HEVC 编码已验证：输出可解码且帧数准确，1080p 输出的
硬件解码与软件解码逐像素一致。持续录屏、温控和极限吞吐量尚未验证。

内核提供 SM8450 固件要求的独立参考缓冲区和安全 ARP 内存；普通编码也需要
后者。如果内核报告保留保护内存或 IOMMU／权限错误，请保存日志并在重启后
再测试；失败路径会主动拒绝继续复用。顺序会话会复用页表，大量并发编码和
内存压力场景尚未验证；保护页表分配设有上限，耗尽时返回错误。


## 可选的无线身份

设备模块提供 `hardware.asphalt.radio.wifiAddressFile` 与
`bluetoothAddressFile`，默认均为 `null`。通过构建输入文件分别提供出厂 Wi-Fi
MAC 和保存的 Qualcomm Bluetooth NVM 地址；蓝牙文件采用控制器字节序，
服务会转换为 BlueZ 所需的显示字节序。Wi-Fi 地址由 udev `.link` 文件在 `wlan0` 出现时设置，因为
NetworkManager 的 IWD 后端会忽略 cloned address。身份数据保留在使用者自己的配置中。
Recovery 不运行这些初始化服务。

## UFS 时钟上限

`hardware.asphalt.ufs.maxFrequency` 默认 75 MHz。udev 规则在 initrd 与已安装系统中
限制 UFS 时钟缩放，同时使链路保持在 HS-G1。设为 `null` 后，内核在两个 UFS
operating point 之间缩放。

内核声明与原厂相同的两个 operating point：75 MHz（RPMh CX LOW_SVS，HS-G1）与
850 MHz（TURBO_L1，HS-G4）。850 MHz 下控制器使用 Qualcomm 的 turbo 配置
（`qcom,sm8475-ufshc`），与联想固件一致；HS-G4 不会在更低时钟下使用。使用该内核
且不设上限时，持续写入负载（4 GiB 直接写入、三次复制约 1000 个文件、回读）
连续十次未出现 PHY、数据链路、致命错误或主机复位，负载期间 CX 处于 TURBO_L1。
1 GiB 写入约 450–1200 MB/s（随设备写缓存填满而下降），O_DIRECT 读取约
1.7 GB/s；75 MHz 时读取约 180 MB/s。

此前未实现 turbo 配置的内核，在启动期 interconnect 与电源投票释放后（所有
fw_devlink `sync_state()` 完成），同样负载在 850 MHz 与 300 MHz/HS-G4 下均出现
PHY／数据链路错误和控制器复位，并发生过一次意外重启。在 850 MHz 下验证系统挂起
与唤醒之前保留默认上限：UFS 主机复位和唤醒后会从最高 operating point 开始，
不受 udev 上限约束。

## 挂起与唤醒

`hardware.asphalt.suspend.memSleep` 默认为 `"s2idle"`，会在内核命令行加入
`mem_sleep_default=s2idle`；固件也提供 `"deep"`，但未经测试；设为 `null` 则保留
内核默认值（`deep`）。s2idle 同时也是联想原厂的默认模式。

已在 Linux 7.3.0-rc6、不设 UFS 时钟上限（850 MHz turbo）且 UFS `spm_lvl` 为 5
（设备断电、链路关闭、唤醒时完整重新初始化）的条件下验证：SoC 进入深度睡眠
（114 秒挂起中约 80 % 时间 AOSS/CX/DDR 处于塌缩状态），唤醒后无 UFS 错误且直接
读取成功，Wi-Fi 重新关联，触摸重新初始化。`spm_lvl` 3 在一次试验中也正常唤醒。

已知限制：

- 电源键可以唤醒设备。插入 USB 以及其他电池管理器或 Type-C（pmic_glink）事件
  目前还不能唤醒，即使这些唤醒源处于启用状态。
- 两次试验中有一次，蓝牙 UART 中断（`qcom_geni_serial`）在进入挂起后不久持续
  触发并被内核禁用，此后蓝牙在重启前不可用。
- 进入挂起时，若仍有未处理的 Type-C/UCSI 连接变化设置 FSA4480 mux，内核可能
  警告 `i2c ... Transfer while suspended`。

设备模块为共享的[唤醒源策略](../configuration.zh.md#挂起唤醒源)声明了唤醒源：
`powerKey`、`volumeKeys`、`battery`（电池管理器及承载它的 ADSP remoteproc）与
`usbPower`（USB 供电与 UCSI source 供电）。例如只保留电源键，并为将来可用的电池
事件保留电池源：

```nix
androidDevices.power.wakeup = {
  enable = true;
  keep = [ "powerKey" "battery" ];
};
```

## 未使用的时钟与电源域

`hardware.asphalt.ignoreUnusedClocksAndDomains` 默认为 `true`，会在已安装系统的
内核命令行加入 `clk_ignore_unused` 与 `pd_ignore_unused`。设为 `false` 后，内核会
关闭没有驱动认领的时钟和电源域。不带这两个参数启动的系统已在 Linux
7.3.0-rc6 上通过显示、输入、USB、无线与音频启动检查。充电镜像始终保留这两个
参数，不受此选项影响。

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
