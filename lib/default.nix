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
            modules =
              (args.modules or [ ])
              ++ nixpkgsLib.optional (buildSystem != targetSystem) (
                { config, lib, ... }:
                let
                  targetPackages = config.nixpkgs.pkgs.appendOverlays config.nixpkgs.overlays;
                  packaging = targetPackages.androidDevicePackages.packaging;
                  hostPackages = compilationPkgs.pkgsBuildBuild;
                  replaceVarsWith = targetPackages.replaceVarsWith.override {
                    stdenvNoCC = compilationPkgs.stdenvNoCC;
                  };
                  nixosEnter = targetPackages.nixos-enter.override {
                    inherit replaceVarsWith;
                    inherit (hostPackages) installShellFiles;
                  };
                  perlHelpers = {
                    buildEnv = targetPackages.perl.buildEnv.override {
                      perl = perlPackage;
                      buildEnv = hostPackages.buildEnv;
                      makeBinaryWrapper = hostPackages.makeBinaryWrapper.override {
                        cc = compilationPkgs.stdenv.cc;
                      };
                      stdenv = compilationPkgs.stdenv;
                    };
                    withPackages =
                      f:
                      perlHelpers.buildEnv.override {
                        extraLibs = f targetPackages.perl.pkgs;
                      };
                  };
                  perlPackage =
                    targetPackages.perl
                    // perlHelpers
                    // {
                      passthru = targetPackages.perl.passthru // perlHelpers;
                    };
                  generators = [
                    "runCommand"
                    "runCommandLocal"
                    "writeText"
                    "writeTextFile"
                    "writeTextDir"
                    "writeScript"
                    "writeScriptBin"
                    "writeShellScript"
                    "writeShellScriptBin"
                    "writeShellApplication"
                    "linkFarm"
                    "concatText"
                    "concatTextFile"
                    "symlinkJoin"
                  ];
                in
                {
                  # NixOS creates units/configuration locally; upstream runtime
                  # packages remain the native target values from this set.
                  _module.args.pkgs = lib.mkForce (
                    targetPackages
                    // lib.genAttrs generators (name: packaging.${name})
                    // {
                      stdenv = compilationPkgs.stdenv;
                      stdenvNoCC = compilationPkgs.stdenvNoCC;
                      makeBinaryWrapper = hostPackages.makeBinaryWrapper.override {
                        cc = compilationPkgs.stdenv.cc;
                      };
                      inherit (hostPackages) compressFirmwareXz compressFirmwareZstd deviceTree;
                      inherit replaceVarsWith;
                      replaceVars = targetPackages.replaceVars.override { inherit replaceVarsWith; };
                      substitute = targetPackages.substitute.override {
                        stdenvNoCC = compilationPkgs.stdenvNoCC;
                      };
                      formats = hostPackages.formats // {
                        nixConf =
                          args:
                          hostPackages.formats.nixConf (
                            args
                            // lib.optionalAttrs (args.checkConfig or true) {
                              package =
                                assert lib.assertMsg (
                                  lib.getName args.package == lib.getName hostPackages.nix && args.version == hostPackages.nix.version
                                ) "Nix configuration validation needs the same build-host package family and version.";
                                hostPackages.nix;
                            }
                          );
                      };
                      nixos-enter = nixosEnter;
                      nixos-install = targetPackages.nixos-install.override {
                        inherit replaceVarsWith;
                        inherit (hostPackages) installShellFiles;
                        nixos-enter = nixosEnter;
                      };
                      nixos-build-vms = targetPackages.nixos-build-vms.override {
                        inherit replaceVarsWith;
                        inherit (hostPackages) installShellFiles;
                      };
                      aggregateModules =
                        modules:
                        targetPackages.callPackage (targetPackages.path + "/pkgs/os-specific/linux/kmod/aggregator.nix") {
                          inherit modules;
                          stdenvNoCC = compilationPkgs.stdenvNoCC;
                          inherit (hostPackages) buildEnv kmod;
                        };
                      perl = perlPackage;
                      makeFontsCache = targetPackages.makeFontsCache.override {
                        inherit (packaging) runCommand writeText;
                        stdenv = compilationPkgs.stdenv;
                        buildPackages = hostPackages;
                      };
                      buildPackages = hostPackages // {
                        # Shell setup hooks execute on the builder but generate
                        # scripts for the target runtime.
                        inherit (targetPackages) makeWrapper makeShellWrapper;
                      };
                      buildEnv = compilationPkgs.pkgsBuildBuild.buildEnv;
                      libcap-text-verifier = compilationPkgs.pkgsBuildBuild.libcap-text-verifier;
                      makeDBusConf = targetPackages.makeDBusConf.override {
                        inherit (packaging) runCommand;
                        inherit (compilationPkgs.pkgsBuildBuild) libxslt findXMLCatalogs;
                      };
                    }
                  );
                }
              );
          }
        );
    };
in
{
  inherit mkBuildEnvironment;
  # Rust source API: AOSP bootloader_control parser and slot helpers. Requires anyhow.
  aospBootControlSource = ../pkgs/mobile-recovery-screen/src/daemon/boot_control.rs;
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
      kernel = c.androidDevices.kernelPackage;
      bootstrap-info = (pkgs.androidDevicePackages.buildPackages or pkgs.buildPackages).closureInfo {
        rootPaths = [ c.system.build.toplevel ];
      };
    }
    // nixpkgsLib.optionalAttrs (c.system.build ? mobileBootImage) {
      boot = c.system.build.mobileBootImage;
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
    }
    // nixpkgsLib.optionalAttrs (c.system.build ? mobileChargerImage) {
      charger = c.system.build.mobileChargerImage;
    };
}
