{ nixpkgs }:
let
  nixpkgsLib = nixpkgs.lib;
  devices = import ./devices.nix;

  mkBuildEnvironment =
    {
      buildSystem,
      overlays ? [ ],
      config ? { },
    }:
    let
      targetSystem = "aarch64-linux";
      compilationPkgs =
        if buildSystem == targetSystem then
          pkgs
        else
          import nixpkgs {
            localSystem = buildSystem;
            crossSystem = targetSystem;
            inherit overlays config;
          };
      pkgs = import nixpkgs {
        system = targetSystem;
        inherit config;
        overlays = [
          (final: _prev: {
            androidDevicePackages = import ../pkgs {
              pkgs = final;
              compilationPkgs = if buildSystem == targetSystem then final else compilationPkgs;
            };
          })
        ]
        ++ overlays;
      };
    in
    assert pkgs.stdenv.buildPlatform.system == targetSystem;
    assert pkgs.stdenv.hostPlatform.system == targetSystem;
    assert compilationPkgs.stdenv.buildPlatform.system == buildSystem;
    assert compilationPkgs.stdenv.hostPlatform.system == targetSystem;
    {
      inherit pkgs compilationPkgs;
      buildPackages = compilationPkgs.buildPackages;
      nixosSystem =
        args:
        nixpkgsLib.nixosSystem (
          args
          // {
            inherit pkgs;
            system = targetSystem;
          }
        );
    };
in
{
  inherit mkBuildEnvironment;
  mkPackageSet = import ../pkgs;
  mkSystem =
    {
      device,
      buildSystem,
      modules ? [ ],
      specialArgs ? { },
      overlays ? [ ],
      nixpkgsConfig ? { },
    }:
    let
      environment = mkBuildEnvironment {
        inherit buildSystem overlays;
        config = nixpkgsConfig;
      };
    in
    assert nixpkgsLib.assertMsg (builtins.hasAttr device devices)
      "Unsupported mobile device: ${device}";
    environment.nixosSystem {
      inherit specialArgs;
      modules = [ devices.${device} ] ++ modules;
    };
  mkArtifacts =
    configuration:
    let
      c = configuration.config;
      pkgs = configuration.pkgs;
    in
    {
      system = c.system.build.toplevel;
      boot = c.system.build.mobileBootImage;
      kernel = c.androidDevices.kernelPackage;
      bootstrap-info = (pkgs.androidDevicePackages.buildPackages or pkgs.buildPackages).closureInfo {
        rootPaths = [ c.system.build.toplevel ];
      };
    }
    //
      nixpkgsLib.optionalAttrs
        (c.androidDevices.persistentImage.enable && !c.androidDevices.recovery.enable)
        {
          rootfs = c.system.build.mobileSystemImage;
        }
    // nixpkgsLib.optionalAttrs (!c.androidDevices.recovery.enable) {
      boot-files = c.system.build.mobileBootFiles;
    }
    // nixpkgsLib.optionalAttrs (c.system.build ? mobileDirectBootImage) {
      boot-kernel = c.system.build.mobileDirectBootImage;
    };
}
