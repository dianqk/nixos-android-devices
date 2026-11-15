# Dodge's MPSS/IPA firmware and remoteproc identity for the shared modem service.
{ config, lib, ... }:
let
  dodge = config.hardware.dodge;
in
{
  options.hardware.dodge.modem.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Experimental installed-system cellular support through rmtfs, tqftpserv
      and ModemManager over QRTR. Set androidDevices.modem.nvDirectory to
      this handset's own NV files: modem_fs1, modem_fs2, modem_fsg,
      modem_fsc, oem_stanvbk and oem_dycnvbk. MPSS starts manually
      unless androidDevices.modem.startAtBoot is enabled. Stopping MPSS may
      reset this board, so the service leaves it running until system reset.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (!dodge.modem.enable) { boot.blacklistedKernelModules = [ "ipa" ]; })
    (lib.mkIf dodge.modem.enable {
      androidDevices.modem = {
        enable = true;
        remoteproc = "4080000.remoteproc";
        firmware = [ dodge.firmwarePackage.modem ];
      };
      # Remoteproc stop can reset this board; leave MPSS to the hardware reset.
      systemd.services.modem-mpss.serviceConfig.ExecStop = lib.mkForce "";
    })
  ];
}
