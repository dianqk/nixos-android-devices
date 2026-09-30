{
  lib,
  config,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.polaris.radio;
  firmware = androidPackages.devices.polaris.wifi-firmware;
  rmtfs = cfg.rmtfsPackage;
  tqftpserv = cfg.tqftpservPackage;
  service = command: {
    requires = [ "qrtr-ns.service" ];
    after = [ "qrtr-ns.service" ];
    serviceConfig = {
      ExecStart = command;
      Restart = "no"; # No unattended firmware crash loops during initial tests.
    };
  };
in
{
  options.hardware.polaris.radio = {
    rmtfsPackage = lib.mkPackageOption androidPackages.devices.polaris "rmtfs" {
      pkgsText = "androidPackages.devices.polaris";
    };
    tqftpservPackage = lib.mkPackageOption androidPackages "mobile-tqftpserv" {
      pkgsText = "androidPackages";
    };
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include Polaris radio firmware, identity handling and modem services.";
    };
    snapshotDirectory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9/._-]+");
      default = null;
      description = "Verified modem calibration snapshot directory; null skips RMTFS startup.";
    };
    bluetoothIdentityFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9/._-]+");
      default = null;
      description = "Device-side file containing the verified Bluetooth public address.";
    };
    identityFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9/._-]+");
      default = null;
      description = "Device-side file containing the verified Wi-Fi MAC address.";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.polaris-bluetooth-address =
      lib.mkIf (config.hardware.bluetooth.enable && cfg.bluetoothIdentityFile != null)
        {
          before = [ "bluetooth.service" ];
          requiredBy = [ "bluetooth.service" ];
          after = [ "systemd-udev-trigger.service" ];
          path = with pkgs; [
            bluez
            coreutils
            gnugrep
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            POLARIS_BLUETOOTH_IDENTITY=${lib.escapeShellArg cfg.bluetoothIdentityFile} ${pkgs.bash}/bin/bash ${./bluetooth-address.sh}
          '';
        };
    environment.systemPackages = [
      firmware
      pkgs.qrtr
      pkgs.iw
    ];
    environment.pathsToLink = [ "/share/uncompressed-firmware" ];
    systemd.services.polaris-wifi-address = lib.mkIf (cfg.identityFile != null) {
      wantedBy = [ "multi-user.target" ];
      requiredBy = lib.optional config.networking.networkmanager.enable "NetworkManager.service";
      before = [
        "polaris-rmtfs.service"
      ]
      ++ lib.optional config.networking.networkmanager.enable "NetworkManager.service";
      after = [ "systemd-udevd.service" ];
      unitConfig.ConditionPathExists = cfg.identityFile;
      path = [
        pkgs.coreutils
        pkgs.systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        POLARIS_WIFI_IDENTITY=${lib.escapeShellArg cfg.identityFile} ${pkgs.bash}/bin/bash ${./wifi-address.sh}
      '';
    };
    # Keep diagnostic and firmware services ahead of rmtfs -s, which publishes
    # its QRTR service and starts MSS. The built-in driver has auto_boot=false.
    systemd.services.polaris-diag-router = {
      description = "Route Polaris Qualcomm diagnostic messages";
      wantedBy = [ "sysinit.target" ];
      before = [
        "polaris-rmtfs.service"
        "polaris-tqftpserv.service"
      ];
      path = [ pkgs.kmod ];
      serviceConfig = {
        ExecStartPre = "${pkgs.kmod}/bin/modprobe qrtr";
        ExecStart = "${pkgs.qcom-diag}/bin/diag-router";
        Restart = "no";
      };
    };
    systemd.services.polaris-rmtfs = lib.mkIf (cfg.snapshotDirectory != null) (
      (service "${rmtfs}/bin/rmtfs -s -r -o ${cfg.snapshotDirectory}")
      // {
        wantedBy = [ "multi-user.target" ];
        requires = [
          "qrtr-ns.service"
          "polaris-diag-router.service"
          "polaris-pd-mapper.service"
          "polaris-tqftpserv.service"
        ];
        after = [
          "qrtr-ns.service"
          "polaris-diag-router.service"
          "polaris-pd-mapper.service"
          "polaris-tqftpserv.service"
        ];
        unitConfig.ConditionPathExists = "${cfg.snapshotDirectory}/SHA256SUMS";
        serviceConfig = {
          ExecStart = "${rmtfs}/bin/rmtfs -s -r -o ${cfg.snapshotDirectory}";
          Restart = "no";
          ProtectSystem = "strict";
          ReadOnlyPaths = [ "${cfg.snapshotDirectory}" ];
        };
      }
    );
    systemd.services.polaris-tqftpserv = service "${tqftpserv}/bin/tqftpserv";
  };
}
