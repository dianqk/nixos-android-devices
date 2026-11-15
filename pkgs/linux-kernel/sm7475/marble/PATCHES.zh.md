# Marble 内核补丁

[English](PATCHES.md) · [Marble 指南](../../../../docs/marble/README.zh.md)

`marble` 补丁队列面向 Linux 7.3.1，排在 [`../../default.nix`](../../default.nix)
的共享 Qualcomm 补丁之后，由 [`series.nix`](series.nix) 定义。内核配置以
[Asphalt](../../sm8475/asphalt/kernel.config) 的 SM8475 基线为起点，加上
[`../config.nix`](../config.nix) 的 SoC 层与 [`default.nix`](default.nix) 的板级覆盖。
使用此内核的 RAM recovery 已在实机上启动（控制台、UFS、USB、触摸、按键以及
36 0d 0b 机器的显示）。

## 来源

[iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble) `main`
（`v7.2.8..ed120558cd2c`）是设备支持的主要来源。保留的独立补丁在
[`patches/linux-marble`](patches/linux-marble) 中记录原作者、日期、提交说明与签名。
合并后的补丁在提交说明中记录各来源及移植调整。

| 补丁 | 内容 |
| --- | --- |
| 0001–0010 | SM8475 pinctrl、cpufreq、`sm8475.dtsi`、SM8450 DT 修正、pd-mapper（Danila Tikhonov、Jens Reidel） |
| 0011 | SM8475 UBWC 配置（已解决：使用 7.3 共享的 `ubwc_4_0_hbb16`） |
| 0012–0015 | PCIe IOMMU cells、OSM L3 绑定、CPU 容量、USB/UFS PHY GDSC |
| 0016–0018 | M16T DSC 视频面板、DSI 10 bpc 时钟、DPU 视频模式 DSC（0017 已解决，见下文） |
| 0019 | SM8475 电池管理 |
| 0020、0036 | AW88261/AW88263S 扬声器功放（0020、0036 已解决：7.3 改用 `guard(mutex)`） |
| 0021–0026 | SMMU 安全上下文、Iris VPU2（0022 已解决：保留 Milos 固件数据）、IPA v5.1、PM8350B 振动、PM8008、SM8450 DT 节点 |
| 0027、0039 | Marble 设备树（`qcom/sm8475-xiaomi-marble.dtb`） |
| 0028–0033、0037、0038、0043–0045 | AudioReach/q6apm 通话与 APR 修改（0038 已解决：仅 include 上下文） |
| [0046](patches/local/0046-media-qcom-iris-adapt-the-SM8450-SM8475-VPU2-support.patch) | 本地：Iris VPU2 的 7.3 构建修正 |
| [0047](patches/local/0047-marble-m16t-36-0d-0b-panel.patch) | M16T「36 0d 0b」面板驱动，含背光缓存及引导程序交接时的下电顺序 |
| [Asphalt 0020](../../sm8475/asphalt/patches/upstream/0020-lucid-ole-preserve-enabled-pll.patch) | 上游提交：保留引导程序留下的运行中的显示 PLL |
| [`iris-hfi-gen2-{decode-order,capture-pool}.patch`](../../patches/iris-hfi-gen2-decode-order.patch) | 共享的 Iris VA-API 前置补丁（HFI gen2 解码顺序控制、更大的解码 capture 缓冲池），与 Asphalt 相同；见 [Asphalt 的说明](../../sm8475/asphalt/PATCHES.md#iris-va-api-prerequisites) |
| [0051](patches/local/0051-media-qcom-iris-apply-msm_vidc-rate-control-conditio.patch) | 本地：与 msm_vidc 一致，VPU2 编码器仅在 VBR 时发送 Android 的 VBR 专用属性（内容自适应编码、码率提升、最低质量、自适应模糊），仅在 CBR/VBR 时启用基于时间差的码率控制，基础层优先级 ID 仅用于 H.264；此前 CBR 下 HEVC P 帧输出为空（尚未在实机验证） |
| [0052](patches/local/0052-audioreach-legacy-tdm-topology.patch) | 旧版 AudioReach TDM 模块及第三路 TDM 位时钟。帧格式及通道配置来自 Audio IF 拓扑 token |
| [0054](patches/local/0054-marble-speaker-tdm-card.patch) | `xiaomi,marble-sndcard` 的绑定、机器驱动与板级连接。96 kHz S32_LE TDM 后端持有 LPASS core 投票，probe 时将听筒开关置于扬声器侧 |
| [0064](patches/local/0064-marble-tdm-clock-and-dcodec-vote.patch) | 在后端运行期间由声卡持有 `tdm-bclk` 与 LPASS `tdm-dcodec-vote` |
| [0075](patches/local/0075-marble-three-channel-tdm.patch) | 将 FL/FR/FC 映射到 TDM 时隙 0–2，使顶部功放的超声输入获得信号 |
| [`ssc-fastrpc-pdr.patch`](../../patches/ssc-fastrpc-pdr.patch)、[0078](patches/local/0078-arm64-dts-qcom-sm8475-xiaomi-marble-subscribe-to-the.patch) | 共享的 FastRPC 保护域订阅，与 Asphalt 相同；Marble DT 让 SLPI FastRPC 节点订阅 `tms/servreg` / `msm/slpi/sensor_pd`（见 [SLPI 传感器](#slpi-传感器)） |
| [0079](patches/local/0079-arm64-dts-qcom-sm8475-xiaomi-marble-enable-the-PMK83.patch) | 本地：与原厂一样启用 PMK8350 RTC 及其闹钟（不允许设置时间），用于 RTC 唤醒 |
| [`gmu-sync-state/0001–0005`](../../patches/gmu-sync-state/README.md) | 共享的 GMU 驱动核心系列（Akhil P Oommen，RFT v1），与 Asphalt 相同：为 GMU 绑定驱动，使 GCC 和 GPUCC 的 `sync_state()` 完成 |
| [0080](patches/local/0080-arm64-dts-qcom-sm8475-xiaomi-marble-disable-unsuppor.patch) | 本地：与 Asphalt 一样禁用 QCE 节点（7.3 中驱动标记为 BROKEN），使互连提供者的 `sync_state()` 完成并撤销启动带宽下限 |
| [0081](patches/local/0081-scsi-ufs-qcom-Power-down-the-controller-device-durin.patch) | 本地，与 Asphalt 的 0027 相同（cherry-pick）：SM8450 UFS `no_phy_retention`（默认 `spm_lvl` 5）；UFS PHY 在 CX 断电后不保留状态 |
| [0082](patches/upstream/0082-dt-bindings-clock-qcom-gcc-sm8450-Add-CX-power-domai.patch)-[0084](patches/upstream/0084-arm64-dts-qcom-sm8450-Add-GCC-CX-power-domain.patch) | 上游（linux-next，Abel Vesa），从 Asphalt 的 0028-0030 cherry-pick：SM8450 GCC 及其 GDSC 以 RPMh CX 为父电源域，GDSC 使用者的性能投票能传到 CX（见 [UFS 时钟与 PHY](#ufs-时钟与-phy)） |
| [0085](patches/local/0085-phy-qcom-qmp-ufs-program-the-full-SM8475-init-sequen.patch)-[0089](patches/local/0089-arm64-dts-qcom-sm8475-describe-UFS-operating-points-.patch) | 本地，从 Asphalt 的 0032、0005、0033、0034、0035 cherry-pick：所有档位的完整 SM8475 UFS PHY 表、来自 GPLL3 的 850 MHz UFS 时钟、`qcom,sm8475-ufshc` 兼容串、300 MHz 以上的 turbo 模式以及 UFS OPP 表（75 MHz/LOW_SVS、850 MHz/TURBO_L1）；0089 解决了与 Marble 自有 `sm8475.dtsi` 中 `freq-table-hz` 的冲突 |
| [0091](patches/local/0091-sm8450-ufs-phy-gdsc-retention.patch) | UFS PHY GDSC 在 CX 断电时进入保持状态，轮询 `CFG_GDSCR` 并保留触发器状态 |
| [`sm-x800-linux/0012`、`0013`、`0017`](../../sm8475/asphalt/PATCHES.md#camera-sources) | 引用 Asphalt 队列中的 SM8450 CAMSS 支持与摄像头时钟修复（Aaron Bockelie，sm-x800-linux）；见[摄像头](#摄像头) |
| [0095](patches/local/0095-media-qcom-camss-keep-the-SM8450-CSIPHY-lane-mask.patch) | 本地：在 SM8450 上保留计算出的 CSIPHY 通道掩码（Asphalt 0016 的驱动部分），用于单通道微距摄像头 |
| [`camss-stream-unwind.patch`](../../patches/camss-stream-unwind.patch)、[`camss-cphy/0001–0009`](../../patches/camss-cphy/README.md)、[`camss-csiphy-cphy-clock.patch`](../../patches/camss-csiphy-cphy-clock.patch) | 共享的 CAMSS 启停回退、CAMSS C-PHY 系列（David Heidelberg，v9）与 C-PHY CSIPHY 时钟，与 Aurora 相同 |
| [0096](patches/local/0096-media-qcom-camss-drop-SM8450-from-the-CSIPHY-init-la.patch)、[0097](patches/local/0097-media-qcom-camss-select-the-SM8450-CSIPHY-lane-table.patch) | 本地：先将 SM8450 移出 `csiphy_init()`，使 C-PHY 系列无需修改即可应用（0096），再按 PHY 类型选择 SM8450 D-PHY 通道表（0097） |
| [0098](patches/local/0098-media-qcom-camss-select-C-PHY-on-CSID-680.patch) | 本地：在 CSID 680（SM8450、SM8475、SM7475）上设置 C-PHY 类型位 |
| [0099](patches/local/0099-media-qcom-camss-csiphy-3ph-add-SM8450-C-PHY-lane-se.patch) | 本地：SM8450 系 C-PHY 通道参数（高通 CSIPHY v2.1.3，每组 1.7 与 2.5 Gsps） |
| [0100](patches/local/0100-media-i2c-add-a-GalaxyCore-GC02M1-driver.patch)–[0102](patches/local/0102-media-i2c-add-an-OmniVision-OV64B40-driver.patch) | 本地：GalaxyCore GC02M1（微距）、Samsung S5K3P9（前置）与 OmniVision OV64B40（主摄）驱动，各含一个固定模式 |
| [0103](patches/local/0103-arm64-dts-qcom-sm8475-xiaomi-marble-wire-the-cameras.patch) | 本地：在板级设备树中描述四颗摄像头 |
| [0104](patches/local/0104-power-supply-qcom_battmgr-report-the-SM8475-USB-port.patch) | 本地：从 SM8475 电池管理器的 `USB_ADAP_TYPE` 上报 USB 端口类型（SDP、CDP、DCP） |

0017 保留 10 bpc 下每像素时钟 24 位的视频时序以及面板提供的 DSC RC 参数。其
slice-per-packet 部分已在 7.3 上游（[`ce73a5db44e3`](https://git.kernel.org/torvalds/c/ce73a5db44e3)）；
M16T 面板改用该接口（`MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`），不再使用分支中的
`dsc_slice_per_pkt` 字段。

### 摄像头

| 摄像头 | 传感器 | 总线 | 链路 | 模式 | Bayer |
| --- | --- | --- | --- | --- | --- |
| 主摄 | OmniVision OV64B40（`ovti,ov64b40`） | CCI0 总线 1，0x10 | CSIPHY2，C-PHY 3 组，1.684 Gsps | 4624x3472 RAW10，30 fps | BGGR |
| 超广角 | Sony IMX355（主线 `imx355`） | CCI0 总线 0，0x1a | CSIPHY0，D-PHY 4 通道，720 Mbps | 3280x2464 RAW10，30 fps | RGGB |
| 前置 | Samsung S5K3P9（`samsung,s5k3p9`） | CCI0 总线 0，0x10 | CSIPHY3，D-PHY 4 通道，544 Mbps | 2304x1728 RAW10，30 fps | GBRG |
| 微距 | GalaxyCore GC02M1（`galaxycore,gc02m1`） | CCI1 总线 0，0x37 | CSIPHY1，D-PHY 1 通道，672 Mbps | 1600x1200 RAW10，30 fps | BGGR（推定） |

主摄、超广角与前置的 Bayer 顺序由传感器彩条测试图确定；GC02M1 的测试图为单色，
其顺序由镜像加翻转的读出方式推定。传感器寄存器表为量产模组的原厂序列；主摄的
逐模组校准数据未写入。C-PHY 通道参数为高通 CSIPHY v2.1.3 的通用值，未用到原厂
内核中本机 CSIPHY2/CSIPHY3 的专门调校。传感器驱动在断电后至少保持 1.2 秒关闭，
因为 CCI 控制器在传感器上下电期间保持时钟时会挂起。

### UFS 时钟与 PHY

Marble 与 SM8475 的 Lenovo TB320FC 一样，在 HS-G4 下以 850 MHz 运行 UFS
核心与 UniPro 时钟。0082–0089 移植了与
[Asphalt 的 UFS 时钟与 PHY](../../sm8475/asphalt/PATCHES.zh.md#ufs-时钟与-phy)
相同的系列：GCC 及其 GDSC 以 RPMh CX 为父电源域（0082-0084），因此 UFS OPP
表中的 CX 档位（0089：HS-G1 为 75 MHz/LOW_SVS，HS-G4 为 850 MHz/TURBO_L1，
节点级 NOM）会真正投票；`qcom,sm8475-ufshc`（0087）在 300 MHz 以上选择控制器的
turbo 配置（0088）；0085 为所有档位写入完整的 PHY 表；0086 让 850 MHz 来自
GPLL3。共享的
`ufs-qcom-lane-clocks-only.patch`（上游 `f07317a8d57f`）与其他 Qualcomm 设备一样
用于 Marble。Marble 保留 0081（不保留 PHY 状态，与 Asphalt 的 0027 相同）和 0015 的 USB
GDSC 轮询；0091 去掉 0015 为 UFS PHY GDSC 设置的 `ALWAYS_ON`（Asphalt 从未设置）：
该 GDSC 以 CX 为父电源域后，它会在挂起期间保留 UFS 的 TURBO_L1 投票。在硬件上
（0082–0089），2 × 2 GiB 写入期间链路以 HS-G4 运行且无错误，`s2idle` 在 `spm_lvl`
3 和 5 下均能恢复。

### 引导程序显示交接

Marble 使用 [Esteban Urrutia 的 Lucid OLE PLL 修复](https://lore.kernel.org/all/20260713-sm8450-qol-dispcc-v3-3-56fd05822270@proton.me/)，
与 Asphalt 相同。ABL 交接时显示 PLL 仍在运行，作为 MDP 时钟的来源；probe 时重新配置它会让该
时钟失去来源，无法切换（启动时出现 `disp_cc_mdss_mdp_clk_src: rcg didn't update its
configuration`）。有了 Asphalt 0020，显示时钟控制器会保留已在运行的 PLL，该警告消失，但仅靠它
36 0d 0b 面板启动时仍为黑屏：在一次显示关闭/开启循环之前不响应 DCS 读取。

0047 在 probe 时将该面板断电：ABL 交接时面板仍上电，驱动取得各路供电，在保持复位的情况下
按原厂顺序关闭并等待 500 ms，然后才连接 DSI 主机，因此链路首次建立时面板是重新上电的。
同时使用两项修复的内核在无诊断跟踪的情况下，两次实机启动均成功点亮 36 0d 0b 面板。

### 面板型号

Marble 装有 M16T「36 02 0a」面板（0016，`xiaomi,marble-m16t-36-02-0a`）或
「36 0d 0b」面板（0047，`xiaomi,marble-m16t-36-0d-0b`）之一，ABL 在
`msm_drm.dsi_display0` 中给出实际型号。0047 由
[linux-mdss-dsi-panel-driver-generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator)
从原厂设备树生成后修改：采用原厂供电顺序与延时；复位采用 36 02 0a 的脉冲（高
11 ms、低 1 ms、高 11 ms），因为面板在其原厂序列（低 1 ms 后高 20 ms）之后不响应；
两个 DSC slice 合入一个包，DSC
配置与原厂上电序列通过厂商命令 `0x70` 写入的 PPS 一致（DSC 1.1、10 bpc、8 bpp、
540×12 slice）。DTB 描述的是 36 02 0a；U-Boot 在把 DTB 交给 Linux 时改写面板
compatible 与 vddd 电压（36 0d 0b 为 1.256 V），见
U-Boot 包。
面板型号及其选择见[显示说明](../../../../docs/marble/display.zh.md)。

### 未纳入本队列

| linux-marble 提交 | 原因 |
| --- | --- |
| `b1e762036636` phy: qcom: qmp-pcie: add SM8475 Gen3x1 PCIe PHY support | 已在 7.3 上游：[`9e953732c3ed`](https://git.kernel.org/torvalds/c/9e953732c3ed)。 |
| `47e7100474a4` remoteproc: qcom: q6v5: disable handover IRQ once handled | 被 7.3 上游 [`bb7c5d6f5b41`](https://git.kernel.org/torvalds/c/bb7c5d6f5b41)（"Make handover IRQ one-shot"）取代。 |
| `f5bc71d7372e` ASoC: qcom: sc8280xp: support TDM backends and 32-bit slots | 由 0054 与 0064 取代：7.3 的 TDM `hw_params` 使用标准 DAI TDM 时隙属性；板级采样率、格式、core 投票与声卡持有的位时钟改为板级声卡条目，不再使用 `qcom,tdm-*` 声卡属性。 |
| `e21870ba92a9` ASoC: qcom: sc8280xp: connect Marble handset voice routes | 暂缓（通话，后续步骤）：依赖 `f5bc71d7372e`。其 probe 时申请扬声器/听筒 GPIO（输出，扬声器）的部分见 0054。 |
| `2c0bbc6ec3cc` ASoC: qcom: sc8280xp: preserve DT DAPM routes when adding voice routes | 暂缓：修正 `e21870ba92a9`。 |

### 7.3 上的扬声器 TDM

扬声器为第三路 TDM 接口上的两颗 AW88263S 功放，按原厂 Android 方式运行：96 kHz，
四个 32 位时隙中的 32 位采样，短帧同步、数据延迟一个位时钟。与原厂组设备（`channels 3`、
`slot_mask 7`）一致，后端在时隙 0-2 传输三个声道（0075）；功放 ACF 让 0x34（顶部扬声器）取时隙 0、
0x35（底部扬声器）取时隙 1，顶部功放另从一个时隙取 TDM 超声输入（SYSCTRL `ULS_MODE`）。
原厂由超声后端填充时隙 2；这里设备 MFC 输出 FL/FR/FC，使该时隙有驱动而非空闲。Linux 7.3
通过拓扑驱动的 Audio IF 模块（`MODULE_ID_AUDIO_IF_*`，0x0700117C）处理 TDM，但
SM7475 的 ADSP（ADSP.HT.5.7-01183）只注册旧版 TDM、I2S 与 codec DMA 端点（镜像中有
0x0700100E/F，没有 0x0700117C/D）。0052 加回旧版 TDM 模块，并用与 Audio IF 相同的
拓扑 token 配置它们，板级拓扑（`pkgs/marble/audio`）使用这些模块。0054 增加板级声卡
条目：后端 fixup 设为 96 kHz S32_LE，后端运行期间声卡持有原厂的 LPASS core 投票，7.3
的 TDM 路径按 DT 设置时隙。0054 在 probe 时选择扬声器。0064 与
`f5bc71d7372e` 相同由声卡申请位时钟：后端 startup 时（DSP graph 打开之前）启用，
后端 shutdown 时（graph 停止之前）关闭。0064 在同一时段持有 LPASS DCODEC
投票。实机上两只扬声器由此都能以原厂功放电平正常播放。

### SLPI 传感器

原厂 SLPI 固件（SLPI.HY.5.0，`slpius.jsn`）向 `tms/servreg` 服务注册
`msm/slpi/sensor_pd` 保护域，与 SM8475 的 Lenovo TB320FC 相同。FastRPC 节点在
`qcom,protection-domain` 中给出该域时，共享 FastRPC 补丁会订阅它，使其服务注册通知得到确认；
0078 在 SLPI FastRPC 节点上设置该属性。pd-mapper 已描述该域（0010：`qcom,sm8475`
使用 SM8350 的域列表）。这只是确认订阅，不处理静态 PD 重启。用户态部分见
[Marble 传感器](../../../../docs/marble/README.zh.md#传感器)。

## 配置

为不含模块的 RAM recovery 内建：SM8475 pinctrl、SM8450 GCC/显示/GPU 时钟与互连、
UFS、带 PTN3222 中继的 eUSB2 PHY、DWC3、ACM/NCM gadget 功能、simpledrm、带两种 M16T
面板驱动的 DRM MSM、Goodix Berlin SPI 触摸屏、GPIO 与 PMIC 按键、`PSTORE_RAM`、ext4 与
VFAT。振动、AW88261 与 IPA 驱动为模块，麦克风通路（Qualcomm SoundWire、WCD938x、LPASS RX/TX/VA macro）也是模块。
`PM_DEBUG` 与 `PM_SLEEP_DEBUG` 为挂起调试提供 `/sys/power/pm_test`、`pm_wakeup_irq`
与 `pm_print_times`；PMK8350 RTC 驱动（`RTC_DRV_PM8XXX`）为模块。

设备模块与社区移植一样传入 `fw_devlink=permissive pcie_aspm=off`；RAM recovery 还传入
`clk_ignore_unused pd_ignore_unused regulator_ignore_unused`
（`hardware.marble.ignoreUnusedClocksAndDomains`、`hardware.marble.ignoreUnusedRegulators`）。

## 构建

```sh
nix build .#devices.marble.kernel
```

使用 [`tools/kernel-queue.py`](../../../../tools/kernel-queue.py)（`--device marble
--version 7.3.1 --base v7.3.1`）维护队列，见[开发指南](../../../../docs/development.zh.md)。
