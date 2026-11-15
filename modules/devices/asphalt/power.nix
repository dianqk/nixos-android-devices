# System suspend mode and named wakeup sources for the shared wakeup policy.
{ config, lib, ... }:
let
  memSleep = config.hardware.asphalt.suspend.memSleep;
  spmi = "/devices/platform/soc@0/c400000.spmi/spmi-0/0-00/c400000.spmi:pmic@0:pon@1300";
  glink = "/devices/platform/pmic-glink";
in
{
  options.hardware.asphalt.suspend.memSleep = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "s2idle"
        "deep"
      ]
    );
    default = "s2idle";
    description = ''
      Default system suspend mode, passed as `mem_sleep_default`. `s2idle`
      (Lenovo's stock default) is verified with UFS `spm_lvl` 5; `deep` is
      offered by the firmware but untested. `null` keeps the kernel's choice
      (`deep`).
    '';
  };

  config.androidDevices = {
    hardwareKernelParams = lib.optional (memSleep != null) "mem_sleep_default=${memSleep}";

    power.wakeup.sources = {
      powerKey = {
        description = "PMK8350 power key; wakes the device from s2idle.";
        devices = [ "${spmi}/c400000.spmi:pmic@0:pon@1300:pwrkey" ];
      };
      volumeKeys = {
        description = "Volume-down (PMIC RESIN) and volume-up (gpio-keys).";
        devices = [
          "${spmi}/c400000.spmi:pmic@0:pon@1300:resin"
          "/devices/platform/gpio-keys"
        ];
      };
      battery = {
        description = ''
          ADSP battery manager over pmic_glink, including the ADSP remoteproc
          that hosts it. Not yet sufficient: battery events do not wake the
          device from s2idle.
        '';
        devices = [
          "${glink}/pmic_glink.power-supply.0/power_supply/qcom-battmgr-bat"
          "/devices/platform/soc@0/3000000.remoteproc"
        ];
      };
      usbPower = {
        description = ''
          USB power and Type-C (battery manager USB supply and UCSI source
          supplies). Plugging USB in does not yet wake the device from s2idle.
        '';
        devices = [
          "${glink}/pmic_glink.power-supply.0/power_supply/qcom-battmgr-usb"
          "${glink}/pmic_glink.ucsi.0/power_supply/ucsi-source-psy-*"
        ];
      };
    };
  };
}
