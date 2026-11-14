# Y700 2023 内核补丁

[English](PATCHES.md) · [Y700 2023 指南](../../../../docs/asphalt/README.zh.md)

补丁集已适配当前锁定的 Linux 7.3。独立补丁重放、解析后的配置检查、
设备 DTB 及补丁涉及的 43 个 C 文件编译均通过。完整内核构建和实机测试仍需
单独验证。其他设备状态见[共享内核说明](../../README.zh.md)。

`asphalt` 补丁集以 Linux 7.3 为目标。补丁顺序见
[`series.nix`](series.nix)，内核配置见 [`kernel.config`](kernel.config)。

| 补丁 | 适配领域 |
| --- | --- |
| 0001 | SM8475 基础支持 |
| 0002 | 显示、面板与背光 |
| 0003 | 触摸屏 |
| [共享 PCIe 修复](../../patches/pcie-qcom-iommu-cells.patch) | 正确解析 PCIe BDF-to-SID 映射的 IOMMU 字段 |
| 0005 | SM8475 850 MHz UFS 时钟父源（GPLL3） |
| 0006 | Y700 2023 设备树 |
| 0007 | 视频编解码 |
| 0008 | USB 与音频连接 |
| 0009 | CS35L45 DSP 固件名称 |
| 0010 | QMP 硬件端口选择 |
| 0011 | 音频服务配置 |
| 0012 | SM8450 CAMSS |
| 0013 | 相机共享 RCG 时钟 |
| 0014 | WL2864C 稳压器 |
| 0015 | HI1339、S5K4H7 和 SC202CS 传感器 |
| 0016 | TB320FC 相机连接和微距 PHY lane 掩码 |
| 0017 | 相机 GDSC 寄存器保持 |
| 0018 | DisplayPort 连接、主 FSA4480 AUX 开关和 QMP DP 方向 |
| 0019 | DP debugfs connector 初始化 |
| 0020 | 保留引导程序已启用的 Lucid OLE PLL，修复显示交接 |
| `iris-hfi-gen2-{decode-order,capture-pool}.patch` | HFI gen2 解码顺序控制和更大的解码捕获缓冲池 |
| [共享 GMU 补丁组](../../patches/gmu-sync-state/README.md) | 为 GMU 绑定驱动，使 GCC/GPUCC `sync_state()` 完成 |
| 0026 | 禁用未使用的 QCE 节点（上游驱动标记为 BROKEN），使 interconnect `sync_state()` 完成 |
| 0027 | 系统挂起时关闭 UFS 控制器、设备和 PHY（CX collapse 后 PHY 不保持状态） |
| 0028–0030 | SM8450 GCC GDSC 以 RPMh CX 为父电源域（上游） |
| 0031 | 已移入共享 Qualcomm 补丁：[仅开关 UFS lane 时钟](../../patches/ufs-qcom-lane-clocks-only.patch)（上游 f07317a8d57f） |
| 0032 | 为所有 gear 写入完整的 SM8475 UFS PHY 序列 |
| 0033 | `qcom,sm8475-ufshc` binding |
| 0034 | SM8475 UFS 300 MHz 以上的 turbo 模式配置 |
| 0035 | 带 CX 档位的 SM8475 UFS operating points（75 与 850 MHz） |
| 0036 | 联动 AXI/UniPro/ICE 调频及 CX/MX 请求；ICE 以 75 MHz/LOW_SVS 启动 |
| [共享 OPP 初始化](../../patches/ufs-opp-init-order.patch) | 初始升频前先应用所需性能档 |

在 x86_64 或 AArch64 Linux 主机上运行 `nix build .#devices.asphalt.kernel`。在 x86_64
主机上，derivation 由 x86_64 运行并生成 AArch64 内核。Kbuild 使用
`ARCH=arm64`、AArch64 target prefix，以及来自 `buildPackages` 的 Clang/LLD；
不需要 AArch64 主机版 LLVM 工具。Linux 内核补丁遵循上游 GPL-2.0 条款及被修改文件中的 SPDX 声明。

## UFS 时钟与 PHY

0035 以联想原厂频率表的两个 operating point 替代旧的 `freq-table-hz`：75 MHz
（LOW_SVS，HS-G1）与 850 MHz（TURBO_L1，HS-G4），即 Qualcomm GCC 驱动对这些频率
要求的 CX 档位。原厂固件在控制器忙碌度低于一半时还会降到 300 MHz 并保持 HS-G4；
此档位未声明，因此 HS-G4 只在 850 MHz 下运行。`qcom,sm8475-ufshc` 兼容串（0033）
启用控制器的 turbo 配置（0034），与 Qualcomm 下游驱动一致：高于 300 MHz 时设置
HCI turbo 时钟通路与 UniPro `ATTR_HW_CGC_EN`，`SYS1CLK_1US` 按核心时钟的一半计数，
UniPro 1 µs/40 ns 周期数为 213 与 9；不高于 300 MHz 时清除这两个位。主机复位或
断电恢复后的 link startup 使用最高频率，因此进入 turbo 模式。0005 提供 850 MHz
的 GPLL3 父时钟。0032 把 SM8475 的 PLL、TX/RX、PCS 配置从仅 HS-G4 生效的 overlay
移入基础表并补充 `BG_TIMER`，与下游所有 gear 共用的表一致。0031（上游
f07317a8d57f）现为共享 Qualcomm 补丁。实测结果见
[UFS 时钟上限](../../../../docs/asphalt/hardware.zh.md#ufs-时钟上限)。

0036 将已有 OPP 扩展为九项时钟，将 ICE 加入 AXI/UniPro 的切频过程，并为 GCC
增加 MX 父域。ICE 在驱动开启时钟前以 75 MHz/LOW_SVS 启动。移除主机永久 NOM
请求后，UFS OPP 通过 GDSC 父域请求 LOW_SVS 或 TURBO_L1。共享初始化修复先取得
全部时钟句柄，再通过 OPP 先提高性能档、后提高时钟频率，并记录已应用频率。
保留上游 turbo compatible、控制器时序与 PHY 序列。这会改变启动与切频时的电源
管理，可能影响功耗及存储稳定性；最高频率仍为 850 MHz，不代表吞吐量提升。
详见 [SM8475 说明](../README.zh.md)。

## 共享 PCIe 修复

Asphalt 与 Sheng 的 7.3 补丁集引用同一份上游 PCIe 解析补丁。
它替换 Asphalt 原本的本地 0004，保留完整原始提交说明与 trailer；代码层面的
唯一差异是恢复上游的警告文本。SDM845 使用另一组 PCIe 操作，不调用此 SID
解析函数，因此 Polaris 不选择该补丁。

## 相机来源

- 0012/0013 提取 Aaron Bockelie 的 SM8450 CAMSS 和 shared-RCG 内核补丁：
  [`d08afbea`](https://github.com/aaronsb/sm-x800-linux/commit/d08afbea7ba594092a104089aa5e124a91b06c7c)、
  [`04f99a72`](https://github.com/aaronsb/sm-x800-linux/commit/04f99a725bc63343683b54dea1aa8f698c4c3b13)。
  保留原作者、日期、提交说明及来源，仅提取打包提交中的相关内核差异。
- 0014 根据[厂商寄存器规格](https://www.ovt.com/wp-content/uploads/2022/09/OV-WL2864C-v2.pdf)
  实现 WL2864C 稳压器。
- 0015 提供 HI1339、S5K4H7、SC202CS 的全尺寸 RAW10 模式，使用 TB320FC
  的 24 MHz 配置。表中保留源文件哈希，补丁说明列出寄存器语义的 GPL 参考来源。
- 0016 配置实机供电、GPIO 和 CSI 连接，并保留单通道微距相机的 PHY 掩码；
  属于 0012 之后的本地适配。
- 0017 提取同作者 `04f99a72` 中的相机 GDSC 寄存器保留配置，与 TB320FC
  原厂设备树中全部九个 `qcom,retain-regs` 节点一致。

S5K4H7 控制寄存器语义也参考了 [MediaTek GPL 驱动（2019）](https://github.com/Samsung-MT6769-Devs/android_kernel_samsung_mt6768/blob/4e0fdc5e6f4c605813c569392f1c255ac4ef66ea/drivers/misc/mediatek/imgsensor/src/common/v1_1/s5k4h7_mipi_raw/s5k4h7mipiraw_Sensor.c)。

## Iris VA-API 前置支持

`iris-hfi-gen2-{decode-order,capture-pool}.patch` 原样导入 libva-v4l2 v1.0.0 中 Xilin Wu 的
[解码顺序控制](https://github.com/radxa-pkg/libva-v4l2/blob/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches/0001-media-iris-support-decode-order-output-on-HFI-gen2.patch)和
[捕获缓冲池上限](https://github.com/radxa-pkg/libva-v4l2/blob/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches/0002-media-iris-allow-larger-capture-buffer-pools-on-HFI-.patch)补丁，保留原作者、日期、
提交说明和签名。这些是 libva-v4l2 提供的配套补丁，不代表已被 Linux 上游合入。

同步 VA-API 客户端可能在提交后续输入之前等待当前画面完成。显示延迟控制
允许客户端按需启用 HFI gen2 解码顺序输出；未设置该控制的客户端保留固件默认
行为。第二项补丁允许 HFI gen2 解码器申请最多 64 个捕获缓冲区，不改变最小
分配数或编码器队列。具备这些接口本身不代表所有视频 profile 都已通过解码验证。
