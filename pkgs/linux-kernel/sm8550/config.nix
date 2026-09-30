{ lib }:
with lib.kernel;
{
  PINCTRL_SM8550 = yes;
  PINCTRL_LPASS_LPI = module;
  PINCTRL_SM8550_LPASS_LPI = module;

  # Keep this SoC's existing clock and fabric selections. Kconfig resolves
  # shared helpers; hot-plug peripheral settings are outside this policy.
  SM_GCC_8550 = yes;
  SM_GPUCC_8550 = yes;
  SM_DISPCC_8550 = yes;
  SM_VIDEOCC_8550 = yes;
  SM_CAMCC_8550 = yes;
  SM_TCSRCC_8550 = yes;
  INTERCONNECT_QCOM_SM8550 = yes;
}
