# Explicit firmware profiles shared by boards; no inference from device names.
{
  profile,
  confirmationNonGptLunMask ? 0,
  androidNonGptLunMask ? 0,
  chargerConfirmationPath ? "",
}:
assert builtins.isInt confirmationNonGptLunMask;
assert confirmationNonGptLunMask >= 0 && confirmationNonGptLunMask <= 255;
assert profile == "qcom-ab" || confirmationNonGptLunMask == 0;
assert builtins.isInt androidNonGptLunMask;
assert androidNonGptLunMask >= 0 && androidNonGptLunMask <= 255;
assert profile == "qcom-ab" || androidNonGptLunMask == 0;
assert builtins.isString chargerConfirmationPath;
assert
  chargerConfirmationPath == "" || builtins.match "/[A-Za-z0-9_./-]+" chargerConfirmationPath != null;
assert profile == "qcom-ab" || chargerConfirmationPath == "";
if profile == "none" then
  ""
else if profile == "pon" then
  ''
    CONFIG_EFI_MOBILE_BOOT_ACTION=y
    # CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB is not set
  ''
else if profile == "qcom-ab" then
  ''
    CONFIG_EFI_MOBILE_BOOT_ACTION=y
    CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB=y
    CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK=${toString androidNonGptLunMask}
    CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM=y
    CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP="linux-boot"
    CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH="/EFI/BOOT/BOOTAA64.EFI"
    CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_CHARGER_PATH="${chargerConfirmationPath}"
    CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK=${toString confirmationNonGptLunMask}
  ''
else
  throw "Unsupported mobile boot-action firmware profile: ${profile}"
