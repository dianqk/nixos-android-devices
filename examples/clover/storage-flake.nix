{
  description = "Clover LTE system and recovery with a measured storage contract";

  inputs.androidDevices.url = "github:dianqk/nixos-android-devices";
  inputs.nixpkgs.follows = "androidDevices/nixpkgs";

  outputs =
    { androidDevices, nixpkgs, ... }:
    let
      mkPackages =
        buildSystem:
        let
          environment = androidDevices.lib.mkBuildEnvironment { inherit buildSystem; };
          inherit (environment) buildPackages;
          make =
            extra:
            environment.nixosSystem {
              modules = [
                androidDevices.nixosModules.clover
                {
                  androidDevices.usbSerial = "my-clover-01";
                  hardware.clover.storageRolesFile = ./storage-roles.sh;
                }
              ]
              ++ extra;
            };
          installed = make [ ];
          recovery = make [
            { androidDevices.recovery.enable = true; }
          ];
        in
        {
          devices.clover.system = installed.config.system.build.toplevel;
          devices.clover.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ installed.config.system.build.toplevel ];
          };
          devices.clover.boot = installed.config.system.build.mobileBootImage;
          devices.clover.recovery = recovery.config.system.build.mobileBootImage;
          mobile-device = androidDevices.packages.${buildSystem}.mobile-device;
          android-tools = androidDevices.packages.${buildSystem}.android-tools;
        };
    in
    {
      legacyPackages = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] mkPackages;
    };
}
