{ config, pkgs, ... }:
{
  imports = [
    ./baseline.nix
    ../console.nix
  ];
  androidDevices.usb.ssh.enable = true;
  androidDevices.usb.acm.enable = true;
  networking.nftables.enable = true;
  networking.networkmanager.enable = true;
  hardware.unicorn.hardwareKeys.enable = true;
  services.pipewire = {
    enable = true;
    systemWide = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PermitEmptyPasswords = true;
    PasswordAuthentication = true;
  };
  security.pam.services.sshd.allowNullPassword = true;
  users.users.root.hashedPassword = "";
  services.getty.autologinUser = "root";
  environment.systemPackages = with pkgs; [
    libdrm
    drm_info
    kmscube
    iw
    bluez
    config.androidDevices.camera.package
    v4l-utils
    python3
    libssc
  ];
  hardware.bluetooth.enable = true;
  hardware.graphics.enable = true;
}
