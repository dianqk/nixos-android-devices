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
  moved =
    name:
    lib.mkRenamedOptionModule [ "hardware" "polaris" "radio" name ] [ "androidDevices" "modem" name ];
in
{
  imports = map moved [
    "rmtfsPackage"
    "tqftpservPackage"
  ];

  options.hardware.polaris.radio = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include Polaris radio firmware, identity handling and modem services.";
    };
    snapshotDirectory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9/._-]+");
      default = null;
      description = ''
        Verified modem calibration snapshot directory, served read-only by rmtfs
        through `androidDevices.modem`; null leaves the modem services out.
      '';
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
        "modem-rmtfs.service"
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
        "modem-rmtfs.service"
        "modem-tqftpserv.service"
      ];
      path = [ pkgs.kmod ];
      serviceConfig = {
        ExecStartPre = "${pkgs.kmod}/bin/modprobe qrtr";
        ExecStart = "${pkgs.qcom-diag}/bin/diag-router";
        Restart = "no";
      };
    };
    # MSS through the shared modem module: rmtfs -s starts it from the
    # read-only calibration snapshot once the snapshot's checksums exist,
    # stops it when rmtfs exits, and nothing restarts on its own. No clock
    # wait, SIM provisioning or ModemManager integration.
    androidDevices.modem = lib.mkIf (cfg.snapshotDirectory != null) {
      enable = true;
      startMethod = "rmtfs";
      startAtBoot = true;
      nvDirectory = cfg.snapshotDirectory;
      rmtfsVerbose = false;
      rmtfsPackage = lib.mkDefault androidPackages.devices.polaris.rmtfs;
      timeSyncTimeout = 0;
      simProvisioning = false;
      modemManager = false;
    };
    systemd.services.modem-rmtfs = lib.mkIf (cfg.snapshotDirectory != null) {
      requires = [
        "qrtr-ns.service"
        "polaris-diag-router.service"
        "polaris-pd-mapper.service"
      ];
      after = [
        "qrtr-ns.service"
        "polaris-diag-router.service"
        "polaris-pd-mapper.service"
      ];
      unitConfig.ConditionPathExists = "${cfg.snapshotDirectory}/SHA256SUMS";
    };
    systemd.services.modem-tqftpserv = lib.mkIf (cfg.snapshotDirectory != null) {
      requires = [ "qrtr-ns.service" ];
      after = [ "qrtr-ns.service" ];
    };
  };
}
