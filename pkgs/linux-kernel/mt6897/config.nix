{ lib }:
with lib.kernel;
{
  # MT6897 boot path for a console RAM recovery: UART, UFS, USB device mode
  # and the watchdog. Clocks, power domains and pins stay as LK left them.
  ARCH_MEDIATEK = yes;
  SERIAL_8250_MT6577 = yes;
  SCSI_UFS_MEDIATEK = yes;
  PHY_MTK_UFS = yes;
  PHY_MTK_XSPHY = yes;
  USB_MTU3 = yes;
  MEDIATEK_WATCHDOG = yes;
  # Volume keys on the SoC keypad.
  KEYBOARD_MT6779 = yes;
  # GPIO/EINT controller and i2c (touchscreen).
  PINCTRL_MT6897 = yes;
  PINCTRL_MTK_PARIS = yes;
  PINCTRL_MTK_V2 = yes;
  I2C_MT65XX = yes;
  # SPMI PMICs: MT6363 power key, MT6685 RTC (and its clock gates).
  SPMI = yes;
  SPMI_MTK_PMIF = yes;
  MFD_MTK_SPMI_PMIC = yes;
  KEYBOARD_MTK_PMIC = yes;
  COMMON_CLK_MT6685 = yes;
  RTC_DRV_MT6685 = yes;
  # Backlight on the display PWM.
  PWM = yes;
  PWM_MTK_DISP = yes;
  BACKLIGHT_PWM = yes;
  # CPU DVFS: MediaTek cpufreq-hw (CSRAM performance domains).
  ARM_MEDIATEK_CPUFREQ_HW = yes;
  # LVTS thermal sensors, calibrated from the efuse.
  MTK_THERMAL = yes;
  MTK_LVTS_THERMAL = yes;
  NVMEM_MTK_EFUSE = yes;
  # Connectivity supplies (MT6363 VCN13/VRFIO18, MT6368 LDOs).
  REGULATOR_MT6363 = yes;
  REGULATOR_MT6368 = yes;
}
