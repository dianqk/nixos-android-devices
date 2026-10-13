{
  config,
  lib,
  androidPackages,
  ...
}:
let
  dtb = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
  chargingTree =
    androidPackages.packaging.runCommand "polaris-charger.dtb"
      { nativeBuildInputs = [ androidPackages.buildPackages.dtc ]; }
      ''
        cp ${dtb} $out
        chmod u+w $out
        # Charging uses PMI8998 directly over SPMI. Keep shared power domains
        # and reserved-memory guards, but do not start radio or sensor DSPs.
        for node in /remoteproc-adsp /remoteproc-cdsp \
          /soc@0/remoteproc@4080000 /soc@0/remoteproc@5c00000 \
          /soc@0/wifi@18800000 /soc@0/ipa@1e40000 \
          /soc@0/geniqup@8c0000/serial@898000/bluetooth; do
          fdtput -t s $out "$node" status disabled
        done
      '';
in
{
  androidDevices.charger = {
    enable = lib.mkDefault true;
    # Display and PMIC drivers are built in. Retain the normal GPU firmware;
    # no modem, sensor, audio or userspace charging service is needed.
    firmware = [ androidPackages.devices.polaris.gpu-firmware ];
    kernelParams = config.androidDevices.hardwareKernelParams;
    deviceTree = chargingTree;
    batteryPath = "/sys/class/power_supply/qcom-battery";
    inputPath = "/sys/class/power_supply/pmi8998-charger";
    statePath = "/sys/class/power_supply/pmi8998-charger";
    inputName = "pm8941_pwrkey";
    framebuffer = "msmdrmfb";
    backlightPath = "/sys/class/backlight/backlight";
    display = {
      widthMm = 68;
      heightMm = 136;
    };
  };
}
