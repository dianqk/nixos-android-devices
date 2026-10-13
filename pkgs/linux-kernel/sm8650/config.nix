{ lib }:
with lib.kernel;
{
  PINCTRL_SM8650 = yes;
  PINCTRL_LPASS_LPI = module;
  PINCTRL_SM8650_LPASS_LPI = module;
  PINCTRL_MAILI = no;
  SM_GCC_8650 = yes;
  SM_TCSRCC_8650 = yes;
  SM_GPUCC_8650 = yes;
  # These drivers match SM8650 too; the Kconfig names retain SM8550.
  SM_DISPCC_8550 = yes;
  SM_VIDEOCC_8550 = yes;
  SM_CAMCC_8650 = yes;
  INTERCONNECT_QCOM_SM8650 = yes;
}
