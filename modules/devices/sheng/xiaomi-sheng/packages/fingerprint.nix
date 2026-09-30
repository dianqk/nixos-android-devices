# ---
# Module: Xiaomi Sheng Fingerprint (FPC1553)
# Description: Prebuilt QTEE runtime + udev rules + systemd services
# Scope: System
# ---

{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:

let
  pkg = androidPackages.devices.sheng.fingerprint;
  fpcTa = androidPackages.devices.sheng.fingerprint-ta;
in
{
  config = lib.mkIf (config.services.fprintd.enable && !config.androidDevices.recovery.enable) {
    environment.systemPackages = [ pkg ];

    services.fprintd.package = lib.mkDefault androidPackages.devices.sheng.fprintd;

    # Only hardware runtime setup belongs here. NixOS owns PAM integration.
    systemd.services.fprintd = {
      requires = [ "qteesupplicant.service" ];
      after = [ "qteesupplicant.service" ];
      environment = {
        FP_FPC1553 = "1";
        FPC1553_TA_PATH = "${fpcTa}/lib/firmware/fpcsheng.elf";
        FPC1553_SYSFS_NODE = "/sys/bus/platform/devices/fingerprint_fpc";
        FPC1553_DATA_DIR = "/var/lib/fpc1553";
      };
      serviceConfig = {
        StateDirectory = [
          "fprint"
          "fpc1553"
        ];
        StateDirectoryMode = "0700";
        DeviceAllow = [ "/dev/tee0 rw" ];
      };
    };

    services.udev.packages = [
      (androidPackages.packaging.writeTextFile {
        name = "sheng-fingerprint-udev";
        destination = "/etc/udev/rules.d/99-qcomtee-fpc.rules";
        text = ''
          SUBSYSTEM=="tee", KERNEL=="tee[0-9]*", MODE="0600", OWNER="root", GROUP="root", TAG+="systemd", ENV{SYSTEMD_WANTS}+="qteesupplicant.service"
        '';
      })
    ];

    systemd.services.qteesupplicant = {
      description = "Qualcomm TEE listener services";
      after = [ "sfsconfig.service" ];
      requires = [ "sfsconfig.service" ];
      bindsTo = [ "dev-tee0.device" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkg}/libexec/qteesupplicant";
        Environment = "LD_LIBRARY_PATH=${pkg}/lib/qtee-listeners";
        Restart = "always";
        AmbientCapabilities = "CAP_SYS_RAWIO";
        CapabilityBoundingSet = "CAP_SYS_RAWIO";
        ProtectSystem = "full";
        ProtectHome = false;
        PrivateTmp = false;
        NoNewPrivileges = false;
        DeviceAllow = [
          "/dev/tee0 rw"
          "/dev/bsg/0:0:0:49476 rw"
          "/dev/bsg/ufs-bsg0 rw"
        ];
      };
    };

    systemd.services.sfsconfig = {
      description = "QTEE secure-file-system configuration";
      before = [ "qteesupplicant.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkg}/libexec/fpc-sfs-config";
      };
    };
  };
}
