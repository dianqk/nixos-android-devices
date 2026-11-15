# System suspend mode, UFS suspend level and named wakeup sources for the
# shared wakeup policy. The sources describe the hardware only; nothing
# changes unless the consumer enables androidDevices.power.wakeup.
{ config, lib, ... }:
let
  cfg = config.hardware.marble.suspend;
  pmic = "/devices/platform/soc@0/c400000.spmi/spmi-0/0-00";
  pon = "${pmic}/c400000.spmi:pmic@0:pon@1300";
  glink = "/devices/platform/pmic-glink";
  ufsHost = "/sys/devices/platform/soc@0/1d84000.ufshc";
in
{
  options.hardware.marble.suspend = {
    memSleep = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "s2idle"
          "deep"
        ]
      );
      default = null;
      description = ''
        Default system suspend mode, passed as `mem_sleep_default`. The firmware
        offers `deep` (PSCI system suspend, the kernel's default; verified) and
        `s2idle` (not yet measured). `null` keeps the kernel's choice (`deep`).
      '';
    };
    ufsSpmLevel = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 0 6);
      default = null;
      example = 3;
      description = ''
        UFS host `spm_lvl` (system-suspend power level) written at boot.
        `null` keeps the driver's default, 5 with kernel patch 0081 (device
        powered down, link off, full reinitialization on resume), as on
        Asphalt: the UFS PHY does not keep its state across a CX collapse.
        With the SM8475 UFS series (0082-0091) level 5 resumes from `s2idle`
        on Marble; without it the controller was not re-enabled
        ("Enabling the controller failed"). Level 3 (device SLEEP, link
        HIBERN8) also resumes, but the UFS GDSC stays on.
      '';
    };
  };

  config = {
    systemd.tmpfiles.settings."10-marble-ufs-spm" = lib.mkIf (cfg.ufsSpmLevel != null) {
      "${ufsHost}/spm_lvl".w.argument = toString cfg.ufsSpmLevel;
    };

    androidDevices = {
      hardwareKernelParams = lib.optional (cfg.memSleep != null) "mem_sleep_default=${cfg.memSleep}";

      power.wakeup.sources = {
        powerKey = {
          description = "PMK8350 power key; wakes the device from deep sleep.";
          devices = [ "${pon}/c400000.spmi:pmic@0:pon@1300:pwrkey" ];
        };
        volumeKeys = {
          description = ''
            Volume-up (gpio-keys, `wakeup-source`). Volume-down (PMIC RESIN) has
            no wakeup setting.
          '';
          devices = [ "/devices/platform/gpio-keys" ];
        };
        rtc = {
          description = ''
            PMK8350 RTC alarm and its alarmtimer device (rtcwake, timers with
            `WakeSystem`); wakes the device from deep sleep.
          '';
          devices = [
            "${pmic}/c400000.spmi:pmic@0:rtc@6100"
            "${pmic}/c400000.spmi:pmic@0:rtc@6100/rtc/*"
          ];
        };
        battery = {
          description = ''
            Battery supply of the ADSP battery manager. Its periodic status
            updates wake the device from deep sleep about every two minutes;
            keep it only for battery-level wake.
          '';
          devices = [ "${glink}/pmic_glink.power-supply.0/power_supply/qcom-battmgr-bat" ];
        };
        usbPower = {
          description = ''
            Charger and Type-C events: the battery manager's USB and wireless
            supplies and the UCSI source supplies. They also receive the ADSP's
            periodic pmic_glink status, which woke the device from deep sleep
            after about three minutes; plugging in USB therefore cannot wake
            the device without these spurious wakes yet.
          '';
          devices = [
            "${glink}/pmic_glink.power-supply.0/power_supply/qcom-battmgr-usb"
            "${glink}/pmic_glink.power-supply.0/power_supply/qcom-battmgr-wls"
            "${glink}/pmic_glink.ucsi.0/power_supply/ucsi-source-psy-*"
          ];
        };
        adsp = {
          description = ''
            ADSP remoteproc, which hosts the battery manager, Type-C (pmic_glink)
            and audio. Its routine messages (most likely the battery manager's
            periodic status) wake the device from deep sleep about every seven
            minutes.
          '';
          devices = [ "/devices/platform/soc@0/3000000.remoteproc" ];
        };
        modem = {
          description = ''
            Modem remoteproc (MPSS): incoming calls and SMS over QMI. Like the
            other remoteprocs it also wakes the device for routine messages
            (deep suspends ended about every seven minutes); needs a policy
            that suspends again after such a dark wake.
          '';
          devices = [ "/devices/platform/soc@0/4080000.remoteproc" ];
        };
        mobileData = {
          description = ''
            IPA (mobile data path). With no SIM or data connection it woke the
            device from deep sleep after a few seconds without a wake
            interrupt; keep it only for mobile-data wake.
          '';
          devices = [ "/devices/platform/soc@0/3f40000.ipa" ];
        };
        sensors = {
          description = "SLPI remoteproc (SSC sensors); wakes the device for routine messages like the ADSP.";
          devices = [ "/devices/platform/soc@0/2400000.remoteproc" ];
        };
        thermal = {
          description = "TSENS thermal sensors (trip interrupts).";
          devices = [
            "/devices/platform/soc@0/c263000.thermal-sensor"
            "/devices/platform/soc@0/c265000.thermal-sensor"
          ];
        };
        wifi = {
          description = ''
            WCN6855 (ath11k over PCIe and MHI). The chip is powered off during
            suspend and powered up again on resume, so it does not wake the
            device in practice.
          '';
          devices = [ "/devices/platform/soc@0/1c00000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0*" ];
        };
      };
    };
  };
}
