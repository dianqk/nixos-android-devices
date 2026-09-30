# Device kernel configuration

Polaris, Asphalt and Clover default to the Nixpkgs Linux 7.3-rc5 source and
their ordered patch series. Sheng defaults to its pinned Linux 7.2.6 fork after
the 7.3 generation failed Wi-Fi initialization on device; `kernel-testing`
retains Sheng's 7.3 patch series. Sheng's `kernel-mainline` is an alias for its
default. Clover retains a separate pinned 7.2.3 `kernel-mainline` fallback.
Configuration is applied in this order:

1. The board's checked-in `configfile`.
2. [Common reductions](config/common.nix).
3. The SoC's `config.nix`.
4. The board specification's `configOverrides`.

Use `lib.kernel.yes`, `module`, or `no` in overrides. Put shared policy in the
common layer, chip requirements in the SoC layer and board exceptions in the
board specification. `olddefconfig` resolves dependencies; `postConfigure`
checks the resulting enabled `PINCTRL` symbols before compilation.

## Peripheral and pinctrl policy

The configuration keeps USB-C/DP, USB hubs, USB networking, external storage,
card readers, keyboards and mice, including their host, role-switch, USB
Storage/UAS, SCSI and HID dependencies. Asphalt and Clover also keep the MMC/
SDHCI path for their built-in microSD slots. FAT and exFAT remain available.

[Qualcomm clock and interconnect reductions](config/qcom-soc-drivers.nix) are
restored by each SoC layer where needed. Shared RPM/RPMh, GDSC/PLL/APCS and
interconnect helpers follow Kconfig dependencies. The SoC layers also restore
the required pin controllers:

| Device | SoC controller | Audio controller | PMIC support |
| --- | --- | --- | --- |
| Asphalt | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Polaris | `PINCTRL_SDM845` | WCD9340 GPIO in `drivers/gpio` | `PINCTRL_QCOM_SPMI_PMIC` |
| Sheng | `PINCTRL_SM8550` | `PINCTRL_SM8550_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Clover | `PINCTRL_SDM660` | `PINCTRL_SDM660_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |

Audio pinctrl also needs `PINCTRL_LPASS_LPI`; Asphalt uses the SM8450 audio
controller compatible. Configuration checks do not establish hardware function.
Test display, touch, storage, audio and external peripherals on the target
before deploying a changed kernel.

[中文](README.zh.md)
