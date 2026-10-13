{
  config,
  lib,
  androidPackages,
  ...
}:
let
  dtb = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
  chargingTree =
    androidPackages.packaging.runCommand "asphalt-charger.dtb"
      {
        nativeBuildInputs = [ androidPackages.buildPackages.dtc ];
      }
      ''
        cp ${dtb} $out
        chmod u+w $out
        # Sensors are not needed by the portrait charging interface. Do not start
        # SLPI with missing firmware or pull its sensor runtime into this initramfs.
        fdtput -t s $out /soc@0/remoteproc@2400000 status disabled
      '';
in
{
  androidDevices.charger = {
    enable = lib.mkDefault true;
    firmware = [ androidPackages.devices.asphalt.firmware ];
    kernelModules = [
      "qcom_pd_mapper"
      "qcom_glink_smem"
      "pmic_glink"
      "pmic_glink_altmode"
      "qcom_battmgr"
      "ucsi_glink"
      "fsa4480"
      "qcom_q6v5_pas"
    ];
    # The charger always keeps unclaimed clocks and power domains on, even when
    # hardware.asphalt.ignoreUnusedClocksAndDomains drops them from the system.
    kernelParams = lib.unique (
      config.androidDevices.hardwareKernelParams
      ++ [
        "clk_ignore_unused"
        "pd_ignore_unused"
      ]
    );
    deviceTree = chargingTree;
    batteryPath = "/sys/class/power_supply/qcom-battmgr-bat";
    inputPath = "/sys/class/power_supply/qcom-battmgr-usb";
    inputName = "pmic_pwrkey";
    framebuffer = "msmdrmfb";
    display.fontWidth = 32;
    backlightPath = "/sys/class/backlight/ktz8866-backlight";
  };
}
