{
  description = "NixOS on Android devices: Polaris, Asphalt (Y700 2023), Clover and Sheng";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

  outputs =
    { self, nixpkgs, ... }:
    let
      nixpkgsLib = nixpkgs.lib;
      deviceLib = import ./lib { inherit nixpkgs; };
      deviceModules = import ./lib/devices.nix;
      recurseArtifacts =
        attrs:
        nixpkgsLib.recurseIntoAttrs (
          nixpkgsLib.mapAttrs (
            _: value: if nixpkgsLib.isDerivation value then value else recurseArtifacts value
          ) attrs
        );
      mkPackages =
        buildSystem:
        let
          buildEnvironment = deviceLib.mkBuildEnvironment {
            inherit buildSystem;
          };
          inherit (buildEnvironment) buildPackages nixosSystem;
          devicePackages = deviceLib.mkPackageSet { inherit (buildEnvironment) pkgs; };
          hostPackages = deviceLib.mkPackageSet { pkgs = buildPackages; };
          make =
            device: modules:
            nixosSystem {
              modules = [ deviceModules.${device} ] ++ modules;
            };
          polarisSystem = make "polaris" [ ./examples/polaris/system.nix ];
          polarisMinimal = make "polaris" [ ./examples/polaris/minimal.nix ];
          polarisRecovery = make "polaris" [ ./examples/polaris/recovery.nix ];
          asphaltSystem = make "asphalt" [ ./examples/asphalt/system.nix ];
          asphaltRecovery = make "asphalt" [ ./examples/asphalt/recovery.nix ];
          cloverSystem = make "clover" [ ./examples/clover/system.nix ];
          cloverRecovery = make "clover" [ ./examples/clover/recovery.nix ];
          shengSystem = make "sheng" [ ./examples/sheng/system.nix ];
          shengRecovery = make "sheng" [ ./examples/sheng/recovery.nix ];
        in
        {
          devices.polaris.system = polarisSystem.config.system.build.toplevel;
          devices.polaris.minimal.system = polarisMinimal.config.system.build.toplevel;
          devices.polaris.minimal.rootfs = polarisMinimal.config.system.build.mobileSystemImage;
          devices.polaris.minimal.boot-files = polarisMinimal.config.system.build.mobileBootFiles;
          devices.polaris.minimal.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ polarisMinimal.config.system.build.toplevel ];
          };
          devices.polaris.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ polarisSystem.config.system.build.toplevel ];
          };
          devices.polaris.boot = polarisSystem.config.system.build.mobileBootImage;
          devices.polaris.recovery = polarisRecovery.config.system.build.mobileBootImage;
          devices.polaris.boot-files = polarisSystem.config.system.build.mobileBootFiles;
          devices.polaris.u-boot = devicePackages.mkUBoot { device = "polaris"; };
          devices.polaris.kernel = devicePackages.devices.polaris.kernel;

          usb-signaller = devicePackages.usb-signaller;
          mobile-device = hostPackages.mobile-device;
          android-tools = buildPackages.android-tools;
          kernel-tools = buildPackages.buildEnv {
            name = "android-kernel-host-tools";
            paths = import ./lib/kernel-tools.nix buildPackages;
          };
          devices.asphalt.u-boot = devicePackages.mkUBoot { device = "asphalt"; };
          devices.asphalt.system = asphaltSystem.config.system.build.toplevel;
          devices.asphalt.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ asphaltSystem.config.system.build.toplevel ];
          };
          devices.asphalt.boot-files = asphaltSystem.config.system.build.mobileBootFiles;
          devices.asphalt.boot = asphaltSystem.config.system.build.mobileBootImage;
          devices.asphalt.recovery = asphaltRecovery.config.system.build.mobileBootImage;
          devices.asphalt.kernel = devicePackages.devices.asphalt.kernel;
          devices.asphalt.disabled-dtbo = devicePackages.devices.asphalt.disabled-dtbo;
          devices.clover.u-boot = devicePackages.mkUBoot { device = "clover"; };
          devices.clover.system = cloverSystem.config.system.build.toplevel;
          devices.clover.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ cloverSystem.config.system.build.toplevel ];
          };
          devices.clover.boot-files = cloverSystem.config.system.build.mobileBootFiles;
          devices.clover.boot = cloverSystem.config.system.build.mobileBootImage;
          devices.clover.boot-kernel = cloverSystem.config.system.build.mobileDirectBootImage;
          devices.clover.recovery = cloverRecovery.config.system.build.mobileBootImage;
          devices.clover.kernel = devicePackages.devices.clover.kernel;
          devices.clover.kernel-mainline = devicePackages.devices.clover.kernel-mainline;
          devices.sheng.u-boot = devicePackages.mkUBoot { device = "sheng"; };
          devices.sheng.system = shengSystem.config.system.build.toplevel;
          devices.sheng.bootstrap-info = buildPackages.closureInfo {
            rootPaths = [ shengSystem.config.system.build.toplevel ];
          };
          devices.sheng.boot-files = shengSystem.config.system.build.mobileBootFiles;
          devices.sheng.boot = shengSystem.config.system.build.mobileBootImage;
          devices.sheng.boot-kernel = shengSystem.config.system.build.mobileDirectBootImage;
          devices.sheng.recovery = shengRecovery.config.system.build.mobileBootImage;
          devices.sheng.kernel = devicePackages.devices.sheng.kernel;
          devices.sheng.kernel-mainline = devicePackages.devices.sheng.kernel-mainline;
          devices.sheng.kernel-testing = devicePackages.devices.sheng.kernel-testing;
        };
    in
    {
      lib = deviceLib;
      overlays.default = import ./overlays;
      nixosModules = deviceModules;
      checks = nixpkgsLib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        buildSystem:
        let
          pkgs = (deviceLib.mkBuildEnvironment { inherit buildSystem; }).buildPackages;
          evaluation =
            name: path:
            builtins.seq (builtins.stringLength (
              builtins.toJSON ((import path { flake = self; }).${buildSystem})
            )) (pkgs.runCommand name { } "touch $out");
        in
        {
          packaging = import ./tests/packaging.nix {
            flake = self;
            inherit buildSystem;
          };
          public-api = evaluation "android-public-api" ./tests/public-api.nix;
          platforms = evaluation "android-platforms" ./tests/eval-platforms.nix;
          native-userspace = evaluation "android-native-userspace" ./tests/native-userspace.nix;
          direct-boot = evaluation "android-direct-boot" ./tests/direct-boot.nix;
          module-boundary = evaluation "android-module-boundary" ./tests/mobile-module-boundary.nix;
          release-config = evaluation "android-release-config" ./tests/release-config.nix;
          initial-install =
            pkgs.runCommand "mobile-initial-install-tests"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.nix
                  pkgs.gnutar
                  pkgs.bash
                ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                export MOBILE_TEST_TMP="$TMPDIR"
                mkdir -p tests pkgs/mobile-recovery-deploy
                cp ${./tests/mobile-initial-install.py} tests/mobile-initial-install.py
                cp ${./pkgs/mobile-recovery-deploy/initial.sh} pkgs/mobile-recovery-deploy/initial.sh
                python3 tests/mobile-initial-install.py
                touch "$out"
              '';
          host-tools =
            pkgs.runCommand "android-host-tools"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.bash
                  pkgs.jq
                ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                python3 -m unittest discover -s ${./pkgs/mobile-device} -p 'test_*.py'
                cp -r ${./tests} tests
                cp -r ${./devices} devices
                mkdir tmp
                for test in test_sheng_layout.py test_asphalt_uefi_plan.py mobile-store-device-gates.py; do
                  python3 tests/$test
                done
                bash tests/mobile-ab-recovery-test.sh
                touch $out
              '';
        }
      );
      devShells = nixpkgsLib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        buildSystem:
        let
          environment = deviceLib.mkBuildEnvironment { inherit buildSystem; };
        in
        {
          kernel = environment.buildPackages.mkShell {
            packages = import ./lib/kernel-tools.nix environment.buildPackages;
            ARCH = "arm64";
            LLVM = "1";
            CROSS_COMPILE = environment.compilationPkgs.stdenv.cc.targetPrefix;
          };
        }
      );
      # Keep generic tools in the flat packages schema. Nested device artifacts
      # use legacyPackages and resolve as `nix build .#devices.<device>.<role>`.
      packages = nixpkgsLib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        system: builtins.removeAttrs (mkPackages system) [ "devices" ]
      );
      legacyPackages = nixpkgsLib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (system: {
        devices = recurseArtifacts (mkPackages system).devices;
      });
    };
}
