# Qualcomm modem (MPSS) on the mainline remoteproc driver: rmtfs serving the
# modem's NV partitions, tqftpserv, a unit that starts and stops MPSS through
# remoteproc sysfs (or rmtfs -s), SIM provisioning and ModemManager over
# QRTR. Devices supply the remoteproc, NV storage (partition labels or a
# directory) and firmware. QTEE license services enabled through
# androidDevices.qtee start before MPSS.
{
  config,
  lib,
  pkgs,
  utils,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.modem;
  qtee = config.androidDevices.qtee;
  partitionPath = name: "/dev/disk/by-partlabel/${name}";
  partitionUnits = map (
    name: "${utils.escapeSystemdPath (partitionPath name)}.device"
  ) cfg.nvPartitions;
  nvAccess = if cfg.allowNvWrites then "rw" else "r";
  rmtfsStarts = cfg.startMethod == "rmtfs";
  # The unit whose start brings MPSS up.
  startUnit = if rmtfsStarts then "modem-rmtfs" else "modem-mpss";
  waitForTimeEnabled = cfg.timeSyncTimeout > 0;
  mmWanted = cfg.modemManager && config.networking.modemmanager.enable;
  # QTEE services that answer the modem's license checks start before MPSS.
  licenseUnits =
    lib.optional qtee.supplicant.enable "qtee-supplicant.service"
    ++ lib.optional qtee.modemOpener.enable "mink-modem-opener.service"
    ++ lib.optional qtee.qwesd.enable "qwesd.service";
  # MPSS start/stop through remoteproc sysfs. A crashed MPSS is never stopped
  # (a phone reset followed stopping it from the crashed state).
  mpssControl = pkgs.writeShellScript "modem-mpss" ''
    set -eu
    rproc=
    for candidate in /sys/class/remoteproc/remoteproc*; do
      device=$(${pkgs.coreutils}/bin/readlink -f "$candidate/device")
      if [ "''${device##*/}" = ${lib.escapeShellArg cfg.remoteproc} ]; then
        rproc=$candidate
        break
      fi
    done
    if [ -z "$rproc" ]; then
      echo "modem remoteproc ${cfg.remoteproc} not found" >&2
      exit 1
    fi
    state=$(cat "$rproc/state")
    case "$1" in
      start)
        echo ${if cfg.crashRecovery then "enabled" else "disabled"} > "$rproc/recovery"
        if [ "$state" = offline ]; then
          echo start > "$rproc/state"
        else
          echo "MPSS is $state, not starting it" >&2
          [ "$state" = running ]
        fi
        ;;
      stop)
        if [ "$state" = running ]; then
          echo stop > "$rproc/state"
        else
          echo "MPSS is $state, leaving it alone" >&2
        fi
        ;;
    esac
  '';
  # MPSS started before the wall clock was set stalled in initialisation on
  # SM8650. Wait for clock synchronisation, but start anyway after the timeout
  # so that an offline phone can still use cellular.
  waitForTime = pkgs.writeShellScript "modem-mpss-wait-time" ''
    for _ in $(${pkgs.coreutils}/bin/seq ${toString cfg.timeSyncTimeout}); do
      if [ "$(${config.systemd.package}/bin/timedatectl show -p NTPSynchronized --value)" = yes ]; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "clock not synchronised after ${toString cfg.timeSyncTimeout} s, starting MPSS anyway" >&2
  '';
  simProvision = pkgs.writeShellApplication {
    name = "modem-sim-provision";
    runtimeInputs = [
      pkgs.libqmi
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = builtins.readFile ./modem-sim-provision.sh;
  };
in
{
  options.androidDevices.modem = {
    enable = lib.mkEnableOption ''
      Qualcomm modem (MPSS) support: rmtfs, tqftpserv, an MPSS start unit,
      SIM provisioning and ModemManager over QRTR. Installed system only
    '';
    remoteproc = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "4080000.remoteproc";
      description = ''
        Device name of the modem's remoteproc (the last component of
        `/sys/class/remoteproc/remoteproc*/device`). Required for the
        `remoteproc-unit` start method.
      '';
    };
    startMethod = lib.mkOption {
      type = lib.types.enum [
        "remoteproc-unit"
        "rmtfs"
      ];
      default = "remoteproc-unit";
      description = ''
        How MPSS is started. `remoteproc-unit`: `modem-mpss.service` writes
        `start` to the remoteproc after rmtfs is up, and `stop` only to a running
        MPSS. `rmtfs`: rmtfs starts MPSS itself (`rmtfs -s`) once its QMI service
        is registered and stops it when rmtfs exits; there is no
        `modem-mpss.service` and `modem-rmtfs.service` is the start unit.
      '';
    };
    nvPartitions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "modemst1"
        "modemst2"
        "fsg"
        "fsc"
      ];
      description = "GPT partition labels of the modem NV storage served by rmtfs.";
    };
    nvDirectory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9/._-]+");
      default = null;
      example = "/var/lib/modem-nv";
      description = ''
        Serve the modem NV storage from files in this directory (`rmtfs -o`)
        instead of `nvPartitions`. Read-only to rmtfs unless `allowNvWrites`.
      '';
    };
    rmtfsVerbose = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run rmtfs with verbose logging (`-v`).";
    };
    modemManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable ModemManager (with the bundled netlink fix) and start it with
        MPSS. When false, the module leaves ModemManager's settings alone.
      '';
    };
    allowNvWrites = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let rmtfs write modem NV data back to the NV partitions. When false,
        rmtfs reads them once and keeps modem writes in RAM, and the service
        cgroup can only read those block devices.
      '';
    };
    rmtfsMemoryDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/qcom_rmtfs_mem1";
      description = "rmtfs shared-memory device.";
    };
    firmware = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Modem firmware packages (MPSS, modem DTB, IPA and the modem's TFTP tree).
        Installed in the root file system only.
      '';
    };
    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start MPSS (`modem-mpss.service`, which pulls in its services) during
        boot. When false, start `modem-mpss.service` manually.
      '';
    };
    crashRecovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let the kernel restart MPSS automatically after a modem crash.";
    };
    timeSyncTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 120;
      description = ''
        Seconds `modem-mpss.service` waits for the system clock to be
        synchronised (`timedatectl` NTPSynchronized) before starting MPSS.
        After the timeout MPSS starts anyway, so that an offline boot can still
        bring up cellular. 0 disables the wait.
      '';
    };
    simProvisioning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        After MPSS starts, activate the primary GW provisioning session for the
        first USIM when the modem has not activated one within a grace period.
        It does nothing when a session exists or no USIM is present.
      '';
    };
    rmtfsPackage = lib.mkPackageOption pkgs "rmtfs" { };
    tqftpservPackage = lib.mkPackageOption androidPackages "mobile-tqftpserv" {
      pkgsText = "androidPackages";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.androidDevices.recovery.enable;
        message = "androidDevices.modem is for the installed system, not RAM recovery.";
      }
      {
        assertion = cfg.startMethod == "remoteproc-unit" -> cfg.remoteproc != null;
        message = "androidDevices.modem.remoteproc is required to start MPSS with modem-mpss.service.";
      }
      {
        assertion = cfg.nvDirectory != null -> cfg.nvPartitions == [ ];
        message = "androidDevices.modem: set either nvPartitions or nvDirectory, not both.";
      }
    ];
    hardware.firmware = cfg.firmware;
    environment.systemPackages = [
      pkgs.qrtr
      pkgs.libqmi
    ];
    # SMS also goes through ModemManager (mmcli or a desktop messaging app).
    networking.modemmanager.enable = lib.mkIf cfg.modemManager (lib.mkDefault true);
    # ModemManager 1.24.2 frees a netlink transaction before calling its
    # completion and crashed on the first QMAP data connection. Upstream fix
    # 9317cbc4 (MR !1509) is on main only; drop this once nixpkgs ships a
    # release containing it. Only the daemon uses this package; clients such
    # as NetworkManager keep the stock libmm-glib.
    networking.modemmanager.package = lib.mkIf cfg.modemManager (
      lib.mkDefault (
        pkgs.modemmanager.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../../pkgs/modemmanager/netlink-transaction-use-after-free.patch
          ];
        })
      )
    );

    systemd.services = lib.mkMerge [
      {
        # Serves the modem's /readonly/firmware/image/ tree from the firmware
        # directory next to modem.mdt; /readwrite/ goes to /var/lib/tqftpserv.
        modem-tqftpserv = {
          restartIfChanged = false;
          description = "Modem TFTP server over QRTR";
          after = licenseUnits;
          before = [ "modem-rmtfs.service" ];
          serviceConfig = {
            ExecStart = lib.getExe' cfg.tqftpservPackage "tqftpserv";
            Restart = "no";
            StateDirectory = "tqftpserv";
            StateDirectoryMode = "0700";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            DevicePolicy = "closed";
          };
        };

        # rmtfs serves the NV storage; with startMethod "rmtfs" it also starts
        # and stops MPSS.
        modem-rmtfs = {
          restartIfChanged = false;
          description = "Modem remote file system (${
            if cfg.allowNvWrites then "NV writes enabled" else "read-only NV"
          })";
          requires = [ "modem-tqftpserv.service" ] ++ partitionUnits;
          after = [
            "modem-tqftpserv.service"
            "systemd-modules-load.service"
          ]
          ++ licenseUnits
          ++ partitionUnits;
          serviceConfig = {
            ExecStart = lib.concatStringsSep " " (
              [ (lib.getExe cfg.rmtfsPackage) ]
              ++ lib.optional rmtfsStarts "-s"
              ++ lib.optional (cfg.nvDirectory == null) "-P"
              ++ lib.optional cfg.rmtfsVerbose "-v"
              ++ lib.optional (!cfg.allowNvWrites) "-r"
              ++ lib.optionals (cfg.nvDirectory != null) [
                "-o"
                cfg.nvDirectory
              ]
            );
            Restart = "no";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            # The cgroup device filter enforces the NV access mode independently of rmtfs.
            DevicePolicy = "closed";
            DeviceAllow = [
              "${cfg.rmtfsMemoryDevice} rw"
            ]
            ++ map (name: "${partitionPath name} ${nvAccess}") cfg.nvPartitions;
          }
          // lib.optionalAttrs (cfg.nvDirectory != null) (
            if cfg.allowNvWrites then
              { ReadWritePaths = [ cfg.nvDirectory ]; }
            else
              { ReadOnlyPaths = [ cfg.nvDirectory ]; }
          );
        };
      }

      # Order: QTEE license services -> tqftpserv -> rmtfs -> clock synchronised
      # (or timeout) -> MPSS -> SIM provisioning -> ModemManager.
      {
        ${startUnit} = {
          wantedBy = lib.optional cfg.startAtBoot "multi-user.target";
          wants =
            licenseUnits
            ++ lib.optional cfg.simProvisioning "modem-sim-provision.service"
            ++ lib.optional mmWanted "ModemManager.service";
        };
      }

      (lib.mkIf (!rmtfsStarts) {
        # Stopping (also at shutdown) writes `stop` only to a running MPSS.
        modem-mpss = {
          description = "Modem (MPSS) start";
          requires = [ "modem-rmtfs.service" ];
          after = [
            "modem-rmtfs.service"
            "time-sync.target"
          ]
          ++ licenseUnits;
          # A switch must not stop a running modem.
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStartPre = lib.mkIf waitForTimeEnabled "${waitForTime}";
            ExecStart = "${mpssControl} start";
            ExecStop = "${mpssControl} stop";
            TimeoutStartSec = cfg.timeSyncTimeout + 60;
          };
        };
      })

      (lib.mkIf (rmtfsStarts && waitForTimeEnabled) {
        modem-rmtfs = {
          after = [ "time-sync.target" ];
          serviceConfig = {
            ExecStartPre = "${waitForTime}";
            TimeoutStartSec = cfg.timeSyncTimeout + 60;
          };
        };
      })

      (lib.mkIf cfg.simProvisioning {
        modem-sim-provision = {
          description = "Modem SIM provisioning session";
          after = [ "${startUnit}.service" ];
          before = lib.optional mmWanted "ModemManager.service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe simProvision} 90 10";
            TimeoutStartSec = 150;
          };
        };
      })
    ];
  };
}
