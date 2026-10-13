{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.sensors;
  deviceUnit = "dev-fastrpc\\x2d${cfg.rpcDomain}.device";
  ready = androidPackages.packaging.writeShellScript "wait-for-ssc-accelerometer" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 6); do
      if samples=$(${pkgs.coreutils}/bin/timeout 8 \
          ${pkgs.libssc}/bin/ssccli --sensor accelerometer --timeout 1 2>&1) \
        && printf '%s\n' "$samples" | ${pkgs.gnugrep}/bin/grep -q '^Accelerometer sensor measurement:'; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    printf '%s\n' "SSC accelerometer did not produce samples" "$samples" >&2
    exit 1
  '';
in
{
  options.androidDevices.sensors = {
    enable = lib.mkEnableOption "SSC sensors through native FastRPC and libssc";
    dataPackage = lib.mkOption {
      type = lib.types.package;
      description = "SSC defaults (etc/sensors, seed), DSP libraries (dsp) and firmware.";
    };
    rpcPackage = lib.mkPackageOption androidPackages "fastrpc" { };
    rpcDomain = lib.mkOption {
      type = lib.types.enum [
        "adsp"
        "sdsp"
      ];
      description = "FastRPC transport domain; selects the native RPC daemon and device.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "/var/lib/[A-Za-z0-9/_-]+";
      default = "/var/lib/ssc-sensors";
      description = "Writable registry parent, retained across system generations.";
    };
    configPaths = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "/[A-Za-z0-9/_-]+");
      default = [
        "/vendor/etc/sensors"
        "/system/vendor/etc/sensors"
      ];
      description = "Absolute sensor configuration directories requested by the DSP firmware.";
    };
    dependencies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional units required before starting the sensor listener.";
    };
    mountMatrix = lib.mkOption {
      type = lib.types.str;
      default = "1, 0, 0; 0, 1, 0; 0, 0, 1";
      description = "Residual screen mounting correction after the SSC backend normalizes device axes for orientation classification.";
    };
  };
  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    nixpkgs.overlays = [ (import ../../overlays/ssc-coordinates.nix) ];
    environment.systemPackages = [
      pkgs.libssc
      cfg.rpcPackage
      cfg.dataPackage
    ];
    environment.pathsToLink = [ "/share/uncompressed-firmware" ];
    hardware.firmware = [ cfg.dataPackage ];
    hardware.sensor.iio.enable = lib.mkDefault true;
    boot.kernelModules = [
      "qcom_q6v5_pas"
      "fastrpc"
    ];
    systemd.tmpfiles.rules = [
      "C ${cfg.stateDirectory} 0750 root root - ${cfg.dataPackage}/seed"
      "z ${cfg.stateDirectory} 0750 root root - -"
    ];
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-${cfg.rpcDomain}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="android-ssc-sensors.service iio-sensor-proxy.service", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity", ENV{ACCEL_MOUNT_MATRIX}="${cfg.mountMatrix}"
    '';
    systemd.services.android-ssc-sensors = {
      description = "SSC sensor-domain FastRPC listener";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-tmpfiles-setup.service"
        deviceUnit
      ]
      ++ cfg.dependencies;
      requires = [ "systemd-tmpfiles-setup.service" ] ++ cfg.dependencies;
      bindsTo = [ deviceUnit ];
      before = [ "iio-sensor-proxy.service" ];
      upholds = [ "iio-sensor-proxy.service" ];
      # Repair field ordering in older generated state while retaining every
      # stored value, including calibration. Never reseed an existing registry.
      preStart = ''
        ${pkgs.python3}/bin/python ${../../pkgs/mobile/ssc-registry/generate.py} \
          --normalize-state ${lib.escapeShellArg cfg.stateDirectory}
      '';
      serviceConfig = {
        Type = "exec";
        ExecStart = "${cfg.rpcPackage}/bin/${
          if cfg.rpcDomain == "sdsp" then "sdsprpcd" else "adsprpcd"
        } sensorspd";
        Restart = "on-failure";
        RestartSec = 3;
        # Empty first component preserves absolute DSP-requested filenames.
        Environment = [ "ADSP_LIBRARY_PATH=;/vendor/etc/sensors;/vendor/dsp;/run/current-system/firmware" ];
        BindReadOnlyPaths = map (path: "${cfg.dataPackage}/etc/sensors:${path}") cfg.configPaths ++ [
          "${cfg.dataPackage}/dsp:/vendor/dsp"
        ];
        BindPaths = [
          "${cfg.stateDirectory}:/persist/sensors"
          "${cfg.stateDirectory}:/mnt/vendor/persist/sensors"
        ];
        PrivateTmp = true;
        UMask = "0027";
      };
    };
    systemd.services.iio-sensor-proxy = {
      requires = [ "android-ssc-sensors.service" ];
      after = [ "android-ssc-sensors.service" ];
      serviceConfig = {
        ExecStartPre = ready;
        TimeoutStartSec = 65;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
