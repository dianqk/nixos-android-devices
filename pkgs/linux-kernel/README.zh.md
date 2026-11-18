# 设备内核配置

每款设备只有一个内核 `devices.<device>.kernel`：锁定 Nixpkgs 输入提供的版本
（`linuxPackages_latest`，当前为 7.3.4）加上该设备的有序补丁集。已安装系统与
RAM recovery 使用同一内核，不保留固定版本或回退内核。构建平台由包输出选择：
`x86_64-linux` 下全部交叉编译为 AArch64（只有 x86_64 机器也可构建），`aarch64-linux`
下原生构建。同一构建平台内，设备的 system、recovery 和 `kernel` 输出共用同一内核
derivation，平台求值检查会对两个平台验证这一点。

所有补丁集都以 [`default.nix`](default.nix) 中的 `expectedVersion` 为目标。Nixpkgs
升级到其他版本后，求值会报错并提示移植：将所有设备的补丁集移植到新版本（见
[开发指南](../../docs/development.zh.md#kernel-patch-queues)）并更新 `expectedVersion`。
`patchQueueStatus` 为工具提供 `expectedVersion` 和 `evaluatedVersion`。求值成功不代表
构建或部署验证。

全部八款设备的补丁集均以 7.3.4 为目标。Dodge 不再携带通用 PHY 模块引用竞争修复：
7.3.4 已包含该修复（稳定版 `8a9f16b5237e`，上游 `090055ee6295`）。FastRPC PDR
订阅保留上游预留内存初始化；Clover/Polaris WLED IRQ 深度跟踪采用上游初始亮度；
Polaris 的 ramoops 预留与扩展后的 XBL 区域共存。Marble 同时保留上游受限 IOVA 状态
和安全编码器 ARP 池，音频所有权补丁与上游位置缓冲区 UNMAP 修复共存。
保留的补丁沿用原共享或板级路径及有序列表。7.3.4 源码准备采用与 7.3.1 相同的、
精确核对的 Nixpkgs 加本地准备契约。源码重放和编译不代表硬件功能验证；应在每款
设备上验证变更后的内核和图形路径。

配置按以下顺序叠加：

1. 设备提交的 `configfile`。
2. [共享能力与通用裁剪](config/common.nix)。
3. SoC 的 `config.nix`。
4. 设备定义中的 `configOverrides`。

覆盖值使用 `lib.kernel.yes`、`module` 或 `no`。共享策略放在通用层，芯片需求
放在 SoC 层，板级例外放在设备定义中。`olddefconfig` 解析依赖；`postConfigure`
在编译前核对所有覆盖值及最终启用的 `PINCTRL` 符号。

## nftables 支持

所有 SoC 和内核变体均包含共享的 [nftables 配置](config/nftables.nix)。
IPv4/IPv6、inet、ARP、bridge、netdev 表，以及连接跟踪、NAT/重定向、NFQUEUE、
FIB 查询、socket 匹配、透明代理、日志、限速、集合与映射（nf_tables 核心能力）
和流卸载支持均内建到内核，覆盖 TUN 自动重定向所需的内核能力。
开启这些能力不会安装防火墙规则或启用代理服务。

## 蓝牙配置

所有带蓝牙的内核均包含共享的[蓝牙配置](config/bluetooth.nix)：RFCOMM（免提耳机
音频和串口配置）、BNEP（蓝牙网络共享）和 HIDP（经典蓝牙键盘和鼠标）。基线未选中
这些选项的内核将其构建为模块；基线已选中的保持原样。

## 外设与 pinctrl 策略

配置保留 USB-C/DP、USB Hub、USB 网卡、外置存储、读卡器、键盘和鼠标，以及
host、角色切换、USB Storage/UAS、SCSI、HID 等依赖。Asphalt 和 Clover 还保留
内建 microSD 插槽所需的 MMC/SDHCI 路径；FAT 与 exFAT 可用。

[高通时钟与互连的通用裁剪](config/qcom-soc-drivers.nix)由各 SoC 层按需恢复。
RPM/RPMh、GDSC/PLL/APCS 和互连共享依赖由 Kconfig 处理。SoC 层还恢复所需的
引脚控制器：

| 设备 | SoC 控制器 | 音频控制器 | PMIC 支持 |
| --- | --- | --- | --- |
| Asphalt / Unicorn | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Polaris | `PINCTRL_SDM845` | `drivers/gpio` 中的 WCD9340 GPIO | `PINCTRL_QCOM_SPMI_PMIC` |
| Sheng | `PINCTRL_SM8550` | `PINCTRL_SM8550_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Clover | `PINCTRL_SDM660` | `PINCTRL_SDM660_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Marble | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |

音频 pinctrl 还需要 `PINCTRL_LPASS_LPI`；Asphalt 和 Unicorn 使用 SM8450 音频
控制器 compatible。[Unicorn SM8475 队列](sm8475/README.zh.md) 独立维护，
Asphalt 保留其上游队列。
配置检查不能证明硬件功能；部署内核更改前，应在目标设备上验证
显示、触控、存储、音频和外接设备。

[English](README.md)
