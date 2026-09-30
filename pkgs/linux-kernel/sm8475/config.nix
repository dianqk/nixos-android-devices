{ lib }:
with lib.kernel;
{
  PINCTRL_SM8475 = yes;
  # SM8475 uses the SM8450 audio pin controller compatible.
  PINCTRL_LPASS_LPI = module;
  PINCTRL_SM8450_LPASS_LPI = module;

  # Keep this SoC's existing clock and fabric selections. Kconfig resolves
  # shared helpers; hot-plug peripheral settings are outside this policy.
  # SM8475 reuses SM8450 drivers; the board enables CAMCC for its cameras.
  SM_GCC_8450 = yes;
  SM_GPUCC_8450 = yes;
  SM_DISPCC_8450 = yes;
  SM_VIDEOCC_8450 = yes;
  INTERCONNECT_QCOM_SM8450 = yes;
}
