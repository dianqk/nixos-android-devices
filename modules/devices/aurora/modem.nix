# Aurora's modem: device data for the shared androidDevices.modem module, and
# the QTEE services that answer the modem's Smart Transmit license checks.
{
  config,
  lib,
  ...
}:
let
  aurora = config.hardware.aurora;
  cfg = aurora.modem;
in
{
  options.hardware.aurora.modem = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Experimental cellular modem support through `androidDevices.modem`:
        Android 14 modem/IPA firmware, rmtfs on the modemst1, modemst2, fsg and
        fsc partitions, tqftpserv and ModemManager over QRTR. The installed
        system only.
      '';
    };
    license.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Serve the modem's Smart Transmit license checks: QTEE supplicant with
        write access to `/persist/data/pfm` only (also bound at Android's
        `/mnt/vendor/persist/data`), and the IMinkModemOpener bridge. Without
        them the modem stops ~190 s after start with "Smart Transmit License
        Check Failure".
      '';
    };
    license.qwesd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also run Qualcomm's prebuilt QWES daemon (`androidDevices.qtee.qwesd`,
        unfree) before MPSS. The modem repeats its Smart Transmit license check
        about 15 minutes after start; without the daemon's QMI license service
        that check fails and the modem stops. Allow the unfree `qwesd` package
        to enable this.
      '';
    };
  };

  config = lib.mkMerge [
    # IPA firmware is only installed with the modem; do not probe IPA without it.
    (lib.mkIf (!cfg.enable) { boot.blacklistedKernelModules = [ "ipa" ]; })
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = aurora.firmwareVariant == "android14";
          message = "Aurora modem support requires the OS1.0.3.0.UNACNXM Android 14 firmware baseline.";
        }
      ];

      androidDevices.modem = {
        enable = true;
        remoteproc = "4080000.remoteproc";
        nvPartitions = [
          "modemst1"
          "modemst2"
          "fsg"
          "fsc"
        ];
        firmware = [ aurora.firmwarePackage.modem ];
      };

      androidDevices.qtee = lib.mkIf cfg.license.enable {
        supplicant.enable = true;
        persist = {
          device = "/dev/disk/by-partlabel/persist";
          writablePaths = [ "/persist/data/pfm" ];
          # QTEE asks for its license store under Android's persist path.
          androidDataPath = "/mnt/vendor/persist/data";
        };
        modemOpener.enable = true;
        qwesd.enable = cfg.license.qwesd;
      };
    })
  ];
}
