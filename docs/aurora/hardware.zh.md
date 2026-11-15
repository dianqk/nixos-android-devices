# Aurora 硬件支持与实现参考

[配置、安装与更新](README.zh.md) · [English](hardware.md)

下列观察结果描述已测试的能力，不代表对所有
配置承诺运行验证。内核为带 Aurora 补丁队列的 Linux 7.3。必须使用[安装指南](README.zh.md#安装前必须准备的原厂底包)要求的
Android 16 底包；运行时固件包不会替换原厂启动链和安全固件。

## 支持概览

| 能力 | 当前支持与限制 |
| --- | --- |
| 启动与存储 | 已验证 B 槽 U-Boot/EFI 安装、独立 recovery 和代际回退。保留 Android A 和 super。 |
| CPU 与 GPU | 已验证 CPU 调频/idle、Adreno 750 OpenGL 4.6、GLES 3.2 和 Turnip Vulkan 渲染。长期热稳态及 GPU 故障恢复未验证。 |
| 显示 | N1 1440×3200，支持 30、60（首选）、120 Hz。60 Hz 刷新及亮屏雪花检查通过；30/120 Hz 视觉检查、HBM 和校准色彩尚未完成。 |
| 触控 | 已验证基本点击、拖动和旋转。多点精度、边缘、防误触和休眠未验证。 |
| 传感器 | 提供 SSC 加速度与 SensorProxy；桌面旋转策略由消费者配置。 |
| USB 与无线 | 已验证 USB3 ACM/NCM、Wi-Fi 和蓝牙数据路径。身份配置及角色/供电限制见[连接说明](connectivity.zh.md)。 |
| DisplayPort | 外接基本画面可用。DP 音频、其他模式、长时间运行及共存（USB3、触控映射）未验证。 |
| 蜂窝基带 | 需显式启用，实验性：MPSS、IPA、rmtfs（默认只读 NV）、tqftpserv、ModemManager 和 QTEE 许可服务。启用许可服务（包括非自由的 `qwesd`）后，注册网络（LTE/5G NR）、IPv4/IPv6 移动数据和短信均可用。见[连接说明](connectivity.zh.md#cellular-modem-experimental)和[基带服务](../modem.zh.md)。 |
| 视频 | Iris V4L2 和可选 VA-API 后端；测试覆盖及限制见下文。 |
| 音频与电源 | 双扬声器立体声播放可用，其余限制见[音频](audio.zh.md)。挂起到空闲（s2idle）可用，见[待机](#待机)。充电策略一致性未验证。 |

Recovery 可能为独立 SSH 身份短暂访问已验证的 Linux 根分区，完成后释放目标挂载。
详见[恢复连接配置](../recovery.zh.md#configure-and-connect)。

## 待机

模块选择挂起到空闲（`mem_sleep_default=s2idle`）。待机时内核拆除 Wi-Fi 的 PCIe
链路，关闭 WCN7850 与 PCIe 控制器电源，使 CX 与 DDR 可以塌缩。在 Android 16 底包、
基带空闲时实测：电源键唤醒的 2 小时 18 分待机正常恢复，CX/DDR 塌缩时间占 99.8 %，
耗电约 28 mA；10 分钟 RTC 闹钟测试恢复正常，塌缩 99.4 %。恢复后 Wi-Fi 重新连接。
每次挂起都会记录 `qcom-pcie 1c00000.pcie: Timeout waiting for L2 entry! LTSSM:
0x12`；内核按设计继续执行，恢复时链路重新训练（Gen 2 x2），该消息无害。

已知限制：

- 从未进入 AOSS 睡眠（`/sys/kernel/debug/qcom_stats` 中 `aosd` 为 0 %）。
- `deep`（PSCI SYSTEM_SUSPEND）从不塌缩 CX/DDR，并在几秒到两分钟内无可记录的唤醒源
  自行醒来；不是默认值。
- 恢复时可能记录 `gunyah-wdt: gunyah_wdt_start: Failed to stop gunyah wdt -22`。
- `pcie_qcom.suspend_opp_floor` 可在 s2idle 期间保留 PCIe 内存投票作为后备：`off`
  （默认）、`full`（挂起 OPP）、`bw`（仅内存投票，`pcie_qcom.suspend_floor_kbps`，
  默认 1000）或 `cx`。任何非零内存投票都会阻止 CX/DDR 塌缩（约 130 mA）；
  `pci_host_common.endpoint_d3cold=0` 恢复旧的链路处理方式，此时需要该后备。

## 触控

已安装系统默认启用 `hardware.aurora.touch.enable`。S3910P 控制器固件自行计算
触点，`aurora-tcm` 内核驱动将其报告为多点触控设备 `Xiaomi 14 Ultra Touchscreen`
（10 点，1440x3200），无需 OEM 库或用户态服务。Recovery 使用物理按键，不加载
该驱动。设置 `hardware.aurora.touch.wakeDisplay = false` 可避免触摸唤醒 DPMS
关闭的屏幕；此时屏幕关闭期间会关闭触控控制器电源，省去其 SPI 中断与处理开销。
实验性的用户态处理程序（`hardware.aurora.touch.hostProcessor.enable`）需要
Android 14 控制器固件和处理库，因此在要求的底包上不可用。

通过 `evtest /dev/input/aurora-touch` 或 libinput 工具检查触点。
诊断、采集/回放与来源见[触控运行时指南](../../pkgs/aurora/touch/README.md)。
多显示器会话应在合成器中把触摸屏映射到目标面板；外接屏能显示不代表触控映射正确。

## 传感器与旋转

已安装系统默认启用 `hardware.aurora.sensors.enable`，提供 SSC/FastRPC、
配套固件的传感器数据及 iio-sensor-proxy。消费者自行配置 SensorProxy 与合成器的
旋转集成；recovery 不包含此用户态栈。

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
ssccli --sensor accelerometer --timeout 3
monitor-sensor --accel
```

监听器必须先产生加速度数据，proxy 才启动。失败时检查两个服务的日志；反复重启
ADSP 或替换成其他 ROM 的传感器数据不是受支持的修复方式。
详见[传感器配置](sensors.zh.md)。

## 视频编解码

本设备使用 Iris 与 OEM VPU33 固件。下列结果使用此前的 Android 14 固件、FFmpeg 9.0.1
及仓库提供的可选 VA 后端：

| 路径 | 已观察到的能力 | 已知限制 |
| --- | --- | --- |
| FFmpeg V4L2 解码 | H.264 Baseline/High、HEVC Main 8-bit 与软件输出一致。 | HEVC Main10 capture 格式失败；HEVC 间歇性会话失败/坏帧尚未解决。 |
| FFmpeg V4L2 编码 | 短 H.264/HEVC 8-bit 流。 | 缺少全局编码头时直接输出 Matroska 可能失败；诊断时先输出 Annex-B。 |
| VA-API 解码 | H.264、HEVC Main/Main10、VP9 Profile 0/2、AV1 Profile 0 8/10-bit 样本与软件输出一致。 | 样本覆盖不代表支持所有 profile、分辨率或码流特性。 |
| VA-API 编码 | H.264 High / HEVC Main 8-bit，720p/1080p，CQP 与 CBR。 | 10-bit 编码、B 帧及长期热稳态未验证。 |

4K/8K、HDR 和 Vulkan Video 未验证。Vulkan 渲染可用不能证明 Vulkan Video 可用。
另见[固件兼容性](firmware.zh.md)。

直接 V4L2 诊断时指定解码器，并核对日志中的 `iris_driver` / `Iris Decoder` 与视频节点：

```sh
ffmpeg -loglevel verbose -c:v h264_v4l2m2m -i input.mp4 -an -f null -
ffmpeg -loglevel verbose -c:v hevc_v4l2m2m -i input.mp4 -an -f null -
```

### 可选 VA-API 后端

启用 `androidDevices.video.vaapi.enable = true`；硬件模块不会自动安装用户态后端。
详见[驱动指南](../video.zh.md#可选-va-api-驱动)。所需内核补丁[已包含](#va-api-内核前提)。

```sh
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi -i input.mp4 \
  -vf hwdownload,format=nv12 -an -f framemd5 output.md5
mpv --hwdec=vaapi --hwdec-software-fallback=no --vo=gpu-next input.mp4
```

选择目标 GPU 的 render 节点；10-bit 比较使用 `p010le`。下载的帧须与独立软件解码
比较，仅列出 profile 或成功提交输入不能证明解码正确。

软解和硬解都可能在播放器启动时出现少量显示丢帧。如果随后稳定，且没有解码错误、
音画不同步或新增内核故障，初始计数本身不代表解码器回归。持续累积、卡顿及挂起应
单独诊断。模块不安装首帧预热绕行。

显式 VA-API 还可避开已知的 `hwdec=auto` 路径问题：先尝试不可用的 Vulkan Video，
随后切换时出现 AV1 解析错误。若之后正确选择 NV12/P010 并完成解码，`yuv420p`
surface 探测错误可能是非致命的。

## N1 原生显示

驱动支持 N1 42-02-0a 面板的 DSC command mode，提供 1440×3200 的 30、60、120 Hz。
切换使用对应初始化并完整下电重启。其他 Android 刷新模式、无缝切换及自主低刷新
未启用。

亮度通过 `/sys/class/backlight/n1-panel/brightness` 控制，范围 0–4095。
Recovery 提供 VT 菜单；`androidDevices.recovery.minimal = true` 切换为诊断控制台。
两者均不提供触控交互。显示熄屏不代表系统 suspend。

面板需要 DSC 1.2 码率参数、每包两个切片及原厂 command-transfer 速率。
SM8650 双 mixer command 扫描还需保留左右 DMA multirect 和配套 INTF tearcheck 序列。
旧内核可能实屏损坏而截图正常。调整内核时保留仓库中的 DSC 和显示接管修复，
并在实体屏幕确认结果。外接 DP 基本画面可用；DP 音频、其他模式、长时间运行和
共存未验证，见[连接说明](connectivity.zh.md#displayport)。

## 内核集成与已知限制

补丁概览见[补丁说明](../../pkgs/linux-kernel/sm8650/aurora/PATCHES.zh.md)。实际补丁和配置以[内核包定义](../../pkgs/linux-kernel/sm8650/aurora/default.nix)为准：

- [板级连线及 GPIO 保留](../../pkgs/linux-kernel/sm8650/aurora/board.patch)：保留固件占用的 GPIO；探测这些引脚可能阻塞初始化。
- [GMU component 集成](../../pkgs/linux-kernel/patches/gmu-sync-state/README.md)：保留上游提案来源和本地移植说明。
- [UFS MCQ](../../pkgs/linux-kernel/sm8650/aurora/ufs-mcq.patch)、[显示 IOMMU 接管](../../pkgs/linux-kernel/sm8650/aurora/sm8650-mdss-identity.patch)和[已启用 PLL 保护](../../pkgs/linux-kernel/sm8650/aurora/lucid-ole-preserve-enabled-pll.patch)。
- BTF 支持 systemd BPF 限制；应存在 `/sys/kernel/btf/vmlinux`。
- 直接 Android recovery 使用 `androidDevices.boot.android.arm64LoadOffset` 对齐原始内核载荷。包装结果不是 EFI 程序，安装后的 EFI 路径使用原始内核。

CPU SpecSEI 差异、虚拟 ITS 表限制、间歇性 GMU fenced-write 延迟及 Type-C 角色协商
仍是已知限制。保留诊断输出，不能因启动或渲染成功就认定这些问题已经解决。
隔离 recovery 中的 RTC 时间可能不可靠。未使用的 QCE consumer 已禁用，CPU 加密仍可用。

OEM 板级参考来自固定版本的小米[内核](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/c7841217725ac8bed6c4bf790d149dde10444e3d)、
[设备树](https://github.com/MiCode/kernel_devicetree/tree/0dbbaba95d270e0dd74ef52eba722801409bd647)、
[显示驱动](https://github.com/MiCode/vendor_opensource_display-drivers/tree/828d8a4fa074706bf087c5a22152309d29ea15c2)和
[显示设备树](https://github.com/MiCode/vendor_qcom_proprietary_display-devicetree/tree/3354864add728de1916f65511c25a512e8b06a72)。
[社区 Houji 板树](https://github.com/yoni13/armada-houji/blob/5d6156dbb0ce23d0156040219be38bbc28aa15c8/ports/houji/sm8650-xiaomi-houji.dts)
也提供了 GPIO 保留范围参考，Aurora 连线仍按自身硬件定义。配套二进制要求见
[固件说明](firmware.zh.md)。硬件补丁保留来源及本地适配说明，不代表上游已接受，也不会
使专有固件因此成为开源固件。

## VA-API 内核前提

Aurora 包含共享的 Iris HFI gen2 [解码顺序控制](../../pkgs/linux-kernel/patches/iris-hfi-gen2-decode-order.patch)
及[捕获缓冲池扩展](../../pkgs/linux-kernel/patches/iris-hfi-gen2-capture-pool.patch)。
SM8650 VPU33 使用 `iris_hfi_gen2_data`，板级操作和固件保持不变。
可选后端需要这些控制；即使 `vainfo` 列出 profile，缺少控制时仍可能以 DISPLAY_DELAY
EINVAL 创建上下文失败。标准 V4L2 客户端不主动选择新控制时保留显示顺序输出。

两项补丁保留 Xilin Wu 的作者、日期和 sign-off，来源为固定版本的
[libva-v4l2](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches)，
没有 Aurora 专属修改。
