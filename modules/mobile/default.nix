{
  imports = [
    ./packages.nix
    ./usb-ssh.nix
    ./options.nix
    ./base.nix
    ./cross-packages.nix
    ./uefi.nix
    ./artifacts.nix
    ./persistent-image.nix
    ./initrd-usb.nix
    ./recovery.nix
    ./systemd-initrd.nix
    ./usb-signaller.nix
  ];
}
