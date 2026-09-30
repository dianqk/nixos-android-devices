# Clover hardware and services layered on the shared persistent image.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cloverFirmware = androidPackages.devices.clover.firmware;
  firmwareLoader = androidPackages.devices.clover.msm-firmware-loader;
  radioQrtr = pkgs.qrtr;
  radioRmtfs = pkgs.rmtfs;
  radioTqftpserv = androidPackages.devices.clover.tqftpserv;
  radioService = command: {
    after = [ "clover-firmware-loader.service" ];
    serviceConfig = {
      ExecStart = command;
      Restart = "no";
    };
  };
in
{
  imports = [ ./multimedia.nix ];

  config = lib.mkIf (!config.androidDevices.recovery.enable) {
    networking.hostName = lib.mkDefault config.hardware.clover.systemHostName;
    androidDevices.persistentImage = {
      enable = true;
    };
    hardware.enableRedistributableFirmware = false;
    hardware.firmware = lib.mkBefore [ cloverFirmware ];
    androidDevices.initrdFirmware = [
      pkgs.wireless-regdb
      cloverFirmware
    ];
    hardware.bluetooth.enable = lib.mkDefault true;
    # MSS is started only by the bounded service below, after its userspace
    # peers are ready. Keep udev from auto-probing it and keep ADSP/CDSP disabled
    # until their own failure handling has been tested.
    boot.blacklistedKernelModules = [
      "qcom_q6v5_mss"
      "qcom_q6v5_pas"
    ];

    system.systemBuilderCommands = ''
      ln -s ${config.system.build.mobileBootImage} $out/clover-boot.img
    '';

    # Make the signed firmware already shipped in the stock Android partitions
    # visible before udev probes modular GPU/radio/multimedia drivers. All source
    # partitions are mounted read-only; persist is deliberately excluded.
    systemd.services.clover-firmware-loader = {
      description = "Expose Clover Android partition firmware read-only";
      wantedBy = [ "sysinit.target" ];
      before = [ "systemd-udevd.service" ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = "/sys /dev";
      };
      path = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/msm-firmware-loader";
        ExecStart = "${firmwareLoader}/bin/msm-firmware-loader-clover";
        ExecStartPost = "${pkgs.coreutils}/bin/ln -sfn /run/msm-firmware-loader/target /lib/firmware";
      };
    };

    systemd.services.clover-bluetooth-address =
      lib.mkIf (config.hardware.clover.bluetoothAddress != null)
        {
          description = "Configure Clover Bluetooth public address";
          wantedBy = [ "multi-user.target" ];
          before = [ "bluetooth.service" ];
          after = [ "clover-firmware-loader.service" ];
          path = with pkgs; [
            bash
            bluez
            coreutils
            gnugrep
          ];
          script = ''
            for attempt in $(seq 1 600); do
              state=$(btmgmt extinfo 2>/dev/null || true)
              if grep -q 'Unconfigured controller' <<<"$state"; then
                exec btmgmt --index 0 public-addr ${lib.escapeShellArg config.hardware.clover.bluetoothAddress}
              fi
              if grep -q 'Primary controller' <<<"$state"; then
                exit 0
              fi
              sleep 0.1
            done
            echo 'Bluetooth controller did not appear within 60 seconds.' >&2
            exit 1
          '';
        };

    # The stock modem image hosts both the modem and WCN3990 WLAN firmware. Its
    # watchdog kills the whole remote processor if the DIAG control channel is
    # not serviced, so diag-router must be alive before MSS starts. RMTFS uses
    # the factory modemst partitions read-only while this bring-up remains
    # reversible; none of these units restart automatically after a failure.
    systemd.services.clover-diag-router =
      lib.recursiveUpdate (radioService "${pkgs.qcom-diag}/bin/diag-router")
        {
          description = "Route Clover Qualcomm diagnostic messages";
          wantedBy = [ "multi-user.target" ];
          before = [
            "clover-rmtfs.service"
            "clover-mss.service"
          ];
          path = [ pkgs.kmod ];
          serviceConfig.ExecStartPre = "${pkgs.kmod}/bin/modprobe qrtr";
        };
    systemd.services.clover-tqftpserv = (radioService "${radioTqftpserv}/bin/tqftpserv") // {
      description = "Serve Clover modem firmware over TQFTP";
      wantedBy = [ "multi-user.target" ];
      before = [ "clover-mss.service" ];
    };
    systemd.services.clover-rmtfs =
      lib.recursiveUpdate (radioService "${radioRmtfs}/bin/rmtfs -P -r -v")
        {
          description = "Serve Clover modem EFS partitions read-only";
          wantedBy = [ "multi-user.target" ];
          requires = [ "clover-diag-router.service" ];
          after = [
            "clover-diag-router.service"
            "clover-firmware-loader.service"
          ];
          before = [ "clover-mss.service" ];
          unitConfig = {
            ConditionPathExists = "/dev/disk/by-partlabel/modemst1";
            ConditionPathExistsGlob = "/dev/disk/by-partlabel/modemst[12]";
          };
          # Loading MSS creates remoteproc0 and its qcom_rmtfs_mem device but does
          # not boot the remote processor. Do this before rmtfs opens the device.
          path = with pkgs; [
            coreutils
            kmod
          ];
          preStart = ''
            modprobe qcom_q6v5_mss
            for attempt in $(seq 1 100); do
              if [ -c /dev/qcom_rmtfs_mem1 ]; then
                exit 0
              fi
              sleep 0.1
            done
            echo 'qcom_rmtfs_mem device did not appear within 10 seconds.' >&2
            exit 1
          '';
        };
    systemd.services.clover-mss = {
      description = "Start Clover modem and WLAN remote processor";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [
        "clover-diag-router.service"
        "clover-rmtfs.service"
        "clover-tqftpserv.service"
      ];
      after = [
        "clover-diag-router.service"
        "clover-rmtfs.service"
        "clover-tqftpserv.service"
      ];
      path = with pkgs; [
        coreutils
        iproute2
        kmod
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "no";
      };
      script = ''
        # A simple service becomes active as soon as exec succeeds. Give rmtfs a
        # bounded interval in which to reject an unusable memory backend before
        # booting MSS; BindsTo stops MSS if a peer fails later.
        sleep 1
        systemctl is-active --quiet clover-diag-router.service
        systemctl is-active --quiet clover-rmtfs.service
        systemctl is-active --quiet clover-tqftpserv.service
        for attempt in $(seq 1 100); do
          for remoteproc in /sys/class/remoteproc/remoteproc*; do
            [ -r "$remoteproc/name" ] || continue
            [ "$(cat "$remoteproc/name")" = 4080000.remoteproc ] || continue
            state=$(cat "$remoteproc/state")
            if [ "$state" = offline ]; then echo start > "$remoteproc/state"; fi
            [ "$(cat "$remoteproc/state")" = running ]
            exit 0
          done
          sleep 0.1
        done
        echo 'MSS remoteproc did not appear within 10 seconds.' >&2
        exit 1
      '';
      preStop = ''
        ip link set wlan0 down 2>/dev/null || true
        for remoteproc in /sys/class/remoteproc/remoteproc*; do
          [ -r "$remoteproc/name" ] || continue
          [ "$(cat "$remoteproc/name")" = 4080000.remoteproc ] || continue
          if [ "$(cat "$remoteproc/state")" = running ]; then echo stop > "$remoteproc/state"; fi
          break
        done
      '';
    };
    systemd.services.clover-wifi-address = lib.mkIf (config.hardware.clover.wifiAddress != null) {
      description = "Configure Clover WLAN public address";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "clover-mss.service" ];
      after = [ "clover-mss.service" ];
      path = with pkgs; [
        coreutils
        iproute2
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for attempt in $(seq 1 600); do
          if [ -e /sys/class/net/wlan0/address ]; then
            ip link set wlan0 down
            ip link set wlan0 address ${lib.escapeShellArg config.hardware.clover.wifiAddress}
            exit 0
          fi
          sleep 0.1
        done
        echo 'WLAN interface did not appear within 60 seconds.' >&2
        exit 1
      '';
    };

    boot.postBootCommands = ''
      if [ -f /nix-path-registration ]; then
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        rm -f /nix-path-registration
      fi
    '';

    environment.systemPackages = with pkgs; [
      bluez
      iw
      qcom-diag
      radioQrtr
      radioRmtfs
    ];
  };
}
