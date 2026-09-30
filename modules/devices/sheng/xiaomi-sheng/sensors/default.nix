# ---
# Module: Sensors Entry
# Description: Entry point for sensor services and hacks
# Scope: Host
# ---

{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:

let
  cfg = config.hardware.sheng.sensors;
  fastrpc = cfg.fastrpcPackage;
  sheng-sensors-file = cfg.registryPackage;
  qrtr = cfg.qrtrPackage;
  sheng-devauth = cfg.devauthPackage;

in
{
  options.hardware.sheng.sensors = {
    enable = lib.mkEnableOption "Sheng ADSP sensor services";
    fastrpcPackage = lib.mkPackageOption androidPackages.devices.sheng "fastrpc" {
      pkgsText = "androidPackages.devices.sheng";
    };
    registryPackage = lib.mkPackageOption androidPackages.devices.sheng "sensors-file" {
      pkgsText = "androidPackages.devices.sheng";
    };
    qrtrPackage = lib.mkPackageOption androidPackages.devices.sheng "qrtr" {
      pkgsText = "androidPackages.devices.sheng";
    };
    devauthPackage = lib.mkPackageOption androidPackages.devices.sheng "devauth" {
      pkgsText = "androidPackages.devices.sheng";
    };
  };

  config = lib.mkIf (config.hardware.sheng.sensors.enable && !config.androidDevices.recovery.enable) {
    # 2. Provide the user-space daemon and registry files in system path
    environment.systemPackages = [
      pkgs.libssc
      fastrpc
      sheng-sensors-file
      qrtr
      sheng-devauth
    ];

    # 2b. sns_reg_config hardcodes paths to /usr/share/qcom/..., but NixOS uses read-only store paths.
    #     We must make it writable because ADSP sensor registry writes a temp.json cache to this dir.
    #     Copy the static files to /var/lib/qcom and symlink /usr/share/qcom to it.
    systemd.tmpfiles.rules = [
      "C /var/lib/qcom - - - - ${sheng-sensors-file}/share/qcom"
      "z /var/lib/qcom 0755 root root - -"
      "d /usr/share 0755 root root -"
      "L+ /usr/share/qcom - - - - /var/lib/qcom"
      "d /usr/lib 0755 root root -"
      "L+ /usr/lib/firmware - - - - /lib/firmware"
    ];

    # 3. Define the root adsprpcd service
    systemd.services.adsprpcd = {
      description = "aDSP RPC root daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${fastrpc}/bin/adsprpcd";
        Restart = "on-failure";
        RestartSec = "5";
        Environment = [
          "ADSP_LIBRARY_PATH=/usr/share/qcom/sm8550/Xiaomi/sheng;/run/current-system/firmware;/lib/firmware;/lib/firmware/qcom/sm8550/sheng;/run/current-system/firmware/rfsa/adsp"
        ];
      };
    };

    # 4. Define xiaomi_devauth service for Nanosic Authentication
    systemd.services.sheng-devauth = {
      description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "adsprpcd.service"
        "systemd-modules-load.service"
      ];
      before = [ "adsprpcd-sensorspd.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${sheng-devauth}/bin/xiaomi_devauth";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # 5. Define the adsprpcd-sensorspd service (sensor PD fastrpc channel)
    systemd.services.adsprpcd-sensorspd = {
      description = "sensorspd aDSP RPC daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "adsprpcd.service"
        "sheng-devauth.service"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [ "adsprpcd.service" ];
      before = [ "iio-sensor-proxy.service" ];

      # Run only if the fastrpc node exists
      unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";

      serviceConfig = {
        Type = "exec";
        ExecStart = "${fastrpc}/bin/adsprpcd sensorspd";
        Restart = "on-failure";
        RestartSec = "5";
        Environment = [
          "ADSP_LIBRARY_PATH=/usr/share/qcom/sm8550/Xiaomi/sheng;/lib/firmware/qcom/sm8550/sheng"
        ];
      };
    };

    # 6. Upstream rules already detect SSC light/compass and start the proxy.
    # Add Sheng's accelerometer/proximity and board-specific mounting matrix.
    # Keep the physical gpio-keys lid switch visible to systemd-logind.
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, -1"
    '';

    # 7. Use the upstream module for the package, D-Bus, udev and service.
    # Only add Sheng's DSP readiness dependencies here.
    hardware.sensor.iio.enable = lib.mkDefault true;
    systemd.services.iio-sensor-proxy = {
      after = [
        "adsprpcd-sensorspd.service"
        "systemd-udev-settle.service"
      ];
      wants = [ "adsprpcd-sensorspd.service" ];
      serviceConfig.ExecStartPre = androidPackages.packaging.writeShellScript "wait-for-sheng-ssc" ''
        for _ in $(seq 1 10); do
          if ${pkgs.libssc}/bin/ssccli --sensor light --timeout 1 >/dev/null 2>&1; then
            exit 0
          fi
          sleep 1
        done

        exit 0
      '';
    };

  };
}
