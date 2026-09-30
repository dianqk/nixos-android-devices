{ lib }:
with lib.kernel;
{
  PINCTRL_SDM660 = yes;
  PINCTRL_LPASS_LPI = module;
  PINCTRL_SDM660_LPASS_LPI = module;

  # Keep this SoC's existing clock and fabric selections. Kconfig resolves
  # shared helpers; hot-plug peripheral settings are outside this policy.
  SDM_GCC_660 = yes;
  SDM_GPUCC_660 = yes;
  SDM_MMCC_660 = yes;
  INTERCONNECT_QCOM_SDM660 = yes;
}
