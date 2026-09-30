# Intentionally passwordless lab image; regular consumers select their own keys.
{ lib, ... }:
{
  imports = [
    ../console.nix
    ./baseline.nix
  ];
  hardware.polaris = {
    radio.enable = false;
    audio.enable = false;
  };
  androidDevices = {
    usb.ssh.enable = true;
    usb.acm.enable = true;
    persistentImage = {
      rootfs = {
        name = "polaris-minimal-rootfs";
        uuid = lib.mkDefault "b14f5820-7762-4a6e-b44d-26cda94f17ed";
      };
    };
  };
  boot.kernelParams = [ "consoleblank=0" ];
  # An intentionally open local USB console for this distributable lab image.
  # Listen only on the USB IPv4 address; the gadget module opens only usb0.
  services.getty.autologinUser = "root";
  users.users.root.hashedPassword = "";
  services.openssh = {
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = true;
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "root" ];
    };
  };
  security.pam.services.sshd.allowNullPassword = true;

}
