{ config, lib, ... }:
{
  options.androidDevices.usb.ssh.enable = lib.mkEnableOption "SSH on the USB management address";
  config = lib.mkIf config.androidDevices.usb.ssh.enable {
    assertions = [
      {
        assertion = config.androidDevices.usb.enable && !config.androidDevices.recovery.enable;
        message = "androidDevices.usb.ssh requires USB on an installed system.";
      }
    ];
    services.openssh = {
      enable = true;
      startWhenNeeded = lib.mkDefault true;
      openFirewall = false;
      listenAddresses = [
        {
          addr = builtins.head (lib.splitString "/" config.androidDevices.usb.signaller.address);
        }
      ];
      settings = {
        PermitRootLogin = lib.mkDefault "prohibit-password";
        PermitEmptyPasswords = lib.mkDefault false;
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };
    systemd.sockets.sshd = lib.mkIf config.services.openssh.startWhenNeeded {
      socketConfig.FreeBind = true;
    };
  };
}
