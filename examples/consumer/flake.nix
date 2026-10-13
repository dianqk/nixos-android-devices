{
  description = "My mobile NixOS configuration";
  inputs.androidDevices.url = "github:dianqk/nixos-android-devices";
  inputs.nixpkgs.follows = "androidDevices/nixpkgs";
  outputs =
    { androidDevices, ... }:
    let
      buildSystem = "x86_64-linux"; # Or aarch64-linux for a native build host.
      device = "polaris";
      common = {
        androidDevices.usbSerial = "my-polaris-01";
        androidDevices.persistentImage.rootfs.label = "NIXOS";
        # Optional exact per-phone checks; see the device's first-install guide.
        # Optional measured roles: hardware.polaris.storageRoles.root.partuuid = "...";
        system.stateVersion = "26.05";
      };
      phone = androidDevices.lib.mkSystem {
        inherit device buildSystem;
        modules = [
          common
          ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/minimal.nix") ]; })
          {
            hardware.polaris.radio.enable = false;
            hardware.polaris.audio.enable = false;

            androidDevices.usb.ssh.enable = true;
            androidDevices.usb.acm.enable = true;
            # Put your actual public key here; no passwordless login is enabled.
            users.users.root.openssh.authorizedKeys.keys = [ ];
          }
        ];
      };
      recovery = androidDevices.lib.mkSystem {
        inherit device buildSystem;
        modules = [
          common
          { androidDevices.recovery.enable = true; }
        ];
      };
    in
    {
      nixosConfigurations.phone = phone;
      packages.${buildSystem} = androidDevices.lib.mkArtifacts phone // {
        recovery = (androidDevices.lib.mkArtifacts recovery).boot;
        mobile-device = androidDevices.packages.${buildSystem}.mobile-device;
        android-tools = androidDevices.packages.${buildSystem}.android-tools;
      };
    };
}
