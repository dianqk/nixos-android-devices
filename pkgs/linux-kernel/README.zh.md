# 设备内核配置

每款设备只有一个内核 `devices.<device>.kernel`：锁定 Nixpkgs 输入提供的版本
（`linuxPackages_testing`，当前为 7.3-rc6）加上该设备的有序补丁集。已安装系统与
RAM recovery 使用同一内核，不保留固定版本或回退内核。构建平台由包输出选择：
`x86_64-linux` 下全部交叉编译为 AArch64（只有 x86_64 机器也可构建），`aarch64-linux`
下原生构建。同一构建平台内，设备的 system、recovery 和 `kernel` 输出共用同一内核
derivation，平台求值检查会对两个平台验证这一点。

所有补丁集都以 [`default.nix`](default.nix) 中的 `expectedVersion` 为目标。Nixpkgs
升级到其他版本后，求值会报错并提示移植：将所有设备的补丁集移植到新版本（见
[开发指南](../../docs/development.zh.md#kernel-patch-queues)）并更新 `expectedVersion`。
`patchQueueStatus` 为工具提供 `expectedVersion` 和 `evaluatedVersion`。求值成功不代表
构建或部署验证。
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

## 外设与 pinctrl 策略

配置保留 USB-C/DP、USB Hub、USB 网卡、外置存储、读卡器、键盘和鼠标，以及
host、角色切换、USB Storage/UAS、SCSI、HID 等依赖。Asphalt 和 Clover 还保留
内建 microSD 插槽所需的 MMC/SDHCI 路径；FAT 与 exFAT 可用。

[高通时钟与互连的通用裁剪](config/qcom-soc-drivers.nix)由各 SoC 层按需恢复。
RPM/RPMh、GDSC/PLL/APCS 和互连共享依赖由 Kconfig 处理。SoC 层还恢复所需的
引脚控制器：

| 设备 | SoC 控制器 | 音频控制器 | PMIC 支持 |
| --- | --- | --- | --- |
| Asphalt | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Polaris | `PINCTRL_SDM845` | `drivers/gpio` 中的 WCD9340 GPIO | `PINCTRL_QCOM_SPMI_PMIC` |
| Sheng | `PINCTRL_SM8550` | `PINCTRL_SM8550_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Clover | `PINCTRL_SDM660` | `PINCTRL_SDM660_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |

音频 pinctrl 还需要 `PINCTRL_LPASS_LPI`；Asphalt 使用 SM8450 音频控制器
compatible。配置检查不能证明硬件功能；部署内核更改前，应在目标设备上验证
显示、触控、存储、音频和外接设备。

[English](README.md)
