# QTEE userspace for Qualcomm devices on the upstream QCOMTEE driver:
# qtee_supplicant (file system, time, RPMB and TA autoload listeners), an
# optional persist partition for QTEE secure files, and the modem's
# IMinkModemOpener bridge on QRTR service 5013.
{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.qtee;
  persistData = "${cfg.persist.mountPoint}/data";
  androidData = cfg.persist.androidDataPath;
  # The same writable directory as seen through the Android-path bind mount.
  androidWritable = map (path: androidData + lib.removePrefix persistData path) (
    lib.filter (lib.hasPrefix "${persistData}/") cfg.persist.writablePaths
  );
  supplicantPackage =
    if cfg.supplicant.debug then
      cfg.supplicant.package.override { withDebugLogs = true; }
    else
      cfg.supplicant.package;
in
{
  options.androidDevices.qtee = {
    supplicant = {
      enable = lib.mkEnableOption ''
        the QTEE supplicant (minkipc qtee_supplicant). It is not started at
        boot by itself; services that need it pull it in
      '';
      package = lib.mkPackageOption androidPackages "minkipc" {
        pkgsText = "androidPackages";
      };
      debug = lib.mkEnableOption ''
        the file system and time listeners' debug messages (each resolved path
        and request) by building the package with `withDebugLogs`
      '';
    };

    persist = {
      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/dev/disk/by-partlabel/persist";
        description = ''
          ext4 persist partition to mount read-write at `mountPoint` (nodev,
          nosuid, noexec, noatime, no automatic fsck). The supplicant's file
          system listener uses `/persist/data/...` paths directly when their
          directory exists there.
        '';
      };
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/persist";
        description = "Mount point of the persist partition.";
      };
      androidDataPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/mnt/vendor/persist/data";
        description = ''
          Also bind `<mountPoint>/data` here (nodev, nosuid, noexec). QTEE
          firmware built for Android asks for its secure files under Android's
          path (`/mnt/vendor/persist/data/...`), which the file system listener
          uses unchanged when the directory exists. Only the `data` directory is
          bound, so other files under the parent (for example sensor registry
          data) stay visible. Writable paths under `<mountPoint>/data` are
          writable through this path as well.
        '';
      };
      writablePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "/persist/data/pfm" ];
        description = ''
          Directories under the persist mount the supplicant may write. The rest
          of the partition stays read-only for the supplicant.
        '';
      };
    };

    modemOpener = {
      enable = lib.mkEnableOption ''
        the IMinkModemOpener service (QRTR 5013 v1 instance 1) through which
        the modem opens QTEE services, e.g. for Smart Transmit licensing
      '';
      package = lib.mkPackageOption androidPackages "mink-modem-opener" {
        pkgsText = "androidPackages";
      };
      clientUid = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        example = 1000;
        description = ''
          UID to present in the QTEE client credentials instead of the service's
          own (root). Android's ssgtzd runs as AID_SYSTEM (1000).
        '';
      };
      trace = lib.mkEnableOption ''
        logging of every invoke on the objects passed between the modem and
        QTEE (method, argument counts and sizes, result, duration, releases)
      '';
      transportTrace = lib.mkEnableOption "MinkSocket's own transport trace";
    };

    qwesd = {
      enable = lib.mkEnableOption ''
        Qualcomm's prebuilt QWES daemon (qwesd, unfree: allow the `qwesd`
        package). It hosts the QMI QTEE license service (1059) that a modem uses
        for licensed features. It runs offline: it may use only QRTR and Unix
        sockets, and writes only its cache directory
      '';
      package = lib.mkPackageOption androidPackages "qwesd" {
        pkgsText = "androidPackages";
      };
    };
  };

  config = lib.mkIf (!config.androidDevices.recovery.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.modemOpener.enable -> cfg.supplicant.enable;
            message = "androidDevices.qtee.modemOpener requires androidDevices.qtee.supplicant.";
          }
          {
            assertion = cfg.qwesd.enable -> cfg.supplicant.enable;
            message = "androidDevices.qtee.qwesd requires androidDevices.qtee.supplicant.";
          }
          {
            assertion = cfg.persist.writablePaths != [ ] -> cfg.persist.device != null;
            message = "androidDevices.qtee.persist.writablePaths requires a persist device.";
          }
          {
            assertion = androidData != null -> cfg.persist.device != null;
            message = "androidDevices.qtee.persist.androidDataPath requires a persist device.";
          }
        ];
      }

      (lib.mkIf (cfg.persist.device != null) {
        fileSystems.${cfg.persist.mountPoint} = {
          device = cfg.persist.device;
          fsType = "ext4";
          noCheck = true;
          options = [
            "rw"
            "nodev"
            "nosuid"
            "noexec"
            "noatime"
            "nofail"
          ];
        };
      })

      # systemd creates the mount point directory when it mounts this.
      (lib.mkIf (cfg.persist.device != null && androidData != null) {
        fileSystems.${androidData} = {
          device = persistData;
          fsType = "none";
          depends = [ cfg.persist.mountPoint ];
          options = [
            "bind"
            "nodev"
            "nosuid"
            "noexec"
            "nofail"
          ];
        };
      })

      (lib.mkIf cfg.supplicant.enable {
        services.udev.extraRules = ''
          SUBSYSTEM=="tee", KERNEL=="tee[0-9]*", TAG+="systemd"
        '';
        systemd.services.qtee-supplicant = {
          description = "QTEE supplicant";
          after = [ "dev-tee0.device" ];
          bindsTo = [ "dev-tee0.device" ];
          unitConfig.RequiresMountsFor = lib.optionals (cfg.persist.device != null) (
            [ cfg.persist.mountPoint ] ++ lib.optional (androidData != null) androidData
          );
          # QTEE may be serving a running modem: never restart on a switch.
          restartIfChanged = false;
          serviceConfig = {
            Type = "exec";
            ExecStart = lib.getExe supplicantPackage;
            Restart = "on-failure";
            # Fallback storage for paths whose /persist directory does not exist.
            StateDirectory = [
              "tee/qtee_supplicant"
              "qtee_supplicant/vendor/tzstorage"
            ];
            StateDirectoryMode = "0700";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadOnlyPaths = lib.optionals (cfg.persist.device != null) (
              [ cfg.persist.mountPoint ] ++ lib.optional (androidData != null) androidData
            );
            ReadWritePaths = cfg.persist.writablePaths ++ lib.optionals (androidData != null) androidWritable;
          };
        };
      })

      (lib.mkIf cfg.modemOpener.enable {
        systemd.services.mink-modem-opener = {
          description = "IMinkModemOpener service for the modem (QRTR 5013)";
          # Wants, not Requires: restarting the supplicant must not restart the
          # bridge, which would drop the objects a running modem registered.
          wants = [ "qtee-supplicant.service" ];
          after = [ "qtee-supplicant.service" ];
          restartIfChanged = false;
          serviceConfig = {
            ExecStart = lib.concatStringsSep " " (
              [ (lib.getExe cfg.modemOpener.package) ]
              ++ lib.optionals (cfg.modemOpener.clientUid != null) [
                "--client-uid"
                (toString cfg.modemOpener.clientUid)
              ]
              ++ lib.optional cfg.modemOpener.trace "--trace"
              ++ lib.optional cfg.modemOpener.transportTrace "--transport-trace"
            );
            Restart = "on-failure";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };
      })

      (lib.mkIf cfg.qwesd.enable {
        systemd.services.qwesd = {
          description = "Qualcomm QWES daemon (QTEE license service)";
          wants = [ "qtee-supplicant.service" ];
          after = [
            "qtee-supplicant.service"
          ]
          ++ lib.optional cfg.modemOpener.enable "mink-modem-opener.service";
          # A modem may hold license sessions with it: never restart it on a
          # switch or by itself.
          restartIfChanged = false;
          serviceConfig = {
            ExecStart = lib.getExe cfg.qwesd.package;
            Restart = "no";
            # As Qualcomm's unit: the daemon may detach.
            RemainAfterExit = true;
            AmbientCapabilities = [
              "CAP_BLOCK_SUSPEND"
              "CAP_WAKE_ALARM"
            ];
            CacheDirectory = "qwes";
            # No network: QMI over QRTR and Unix sockets only.
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_QIPCRTR"
            ];
            IPAddressDeny = "any";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            NoNewPrivileges = true;
          };
        };
      })
    ]
  );
}
