{ lib }:
with lib.kernel;
{
  PINCTRL_SM8750 = yes;
  PINCTRL_MAILI = no;
  SM_GCC_8750 = yes;
  SM_TCSRCC_8750 = yes;
  INTERCONNECT_QCOM_SM8750 = yes;
}
