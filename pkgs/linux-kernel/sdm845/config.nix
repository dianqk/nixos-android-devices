{ lib }:
{
  PINCTRL_SDM845 = lib.kernel.yes;

  # Keep this SoC's existing clock and fabric selections. Kconfig resolves
  # shared helpers; hot-plug peripheral settings are outside this policy.
  SDM_GCC_845 = lib.kernel.yes;
  SDM_GPUCC_845 = lib.kernel.yes;
  SDM_DISPCC_845 = lib.kernel.yes;
  SDM_VIDEOCC_845 = lib.kernel.yes;
  SDM_CAMCC_845 = lib.kernel.module;
  SDM_LPASSCC_845 = lib.kernel.module;
  INTERCONNECT_QCOM_SDM845 = lib.kernel.yes;
}
