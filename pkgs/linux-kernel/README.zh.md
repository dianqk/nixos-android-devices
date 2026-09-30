# 设备内核配置

Polaris、Asphalt 和 Clover 默认使用 Nixpkgs Linux 7.3-rc5 及对应的有序补丁集。
Sheng 的 7.3 版本在实机上无法初始化 Wi-Fi，因此默认使用固定版本的 Linux 7.2.6
分支源码；`kernel-testing` 保留 Sheng 的 7.3 补丁集。Sheng 的 `kernel-mainline`
是默认内核的别名；Clover 的 `kernel-mainline` 仍是单独的固定 7.2.3 回退包。
配置按以下顺序叠加：

1. 设备提交的 `configfile`。
2. [通用裁剪](config/common.nix)。
3. SoC 的 `config.nix`。
4. 设备定义中的 `configOverrides`。

覆盖值使用 `lib.kernel.yes`、`module` 或 `no`。共享策略放在通用层，芯片需求
放在 SoC 层，板级例外放在设备定义中。`olddefconfig` 解析依赖；`postConfigure`
在编译前核对最终启用的 `PINCTRL` 符号。

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
