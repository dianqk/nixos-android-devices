# Marble's modem: device data for the shared androidDevices.modem module.
# No QTEE license services: the postmarketOS port registers, uses mobile
# data and SMS with rmtfs, tqftpserv and the in-kernel pd-mapper alone.
{
  config,
  lib,
  ...
}:
let
  marble = config.hardware.marble;
in
{
  options.hardware.marble.modem.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Experimental cellular modem support through `androidDevices.modem`:
      the firmware package's `modem` output (MPSS, `modem_pr` carrier
      configurations and IPA), rmtfs on the modemst1, modemst2, fsg and fsc
      partitions (read-only unless `androidDevices.modem.allowNvWrites`),
      tqftpserv and ModemManager over QRTR. The installed system only.
    '';
  };

  config = lib.mkIf marble.modem.enable {
    androidDevices.modem = {
      enable = true;
      remoteproc = "4080000.remoteproc";
      nvPartitions = [
        "modemst1"
        "modemst2"
        "fsg"
        "fsc"
      ];
      firmware = [ marble.firmwarePackage.modem ];
    };
  };
}
