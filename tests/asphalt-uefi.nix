{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      # The example enables the proprietary Asphalt sensor data.
      config.allowUnfree = true;
    };
    make =
      example:
      env.nixosSystem {
        modules = [
          flake.nixosModules.asphalt
          (flake.outPath + "/examples/asphalt/${example}.nix")
        ];
      };
    c = (make "system").config;
    recovery = (make "recovery").config;
  in
  assert c.boot.loader.systemd-boot.enable;
  assert !recovery.boot.loader.systemd-boot.enable;
  assert c.boot.loader.systemd-boot.configurationLimit == 10;
  assert c.boot.loader.systemd-boot.installDeviceTree;
  assert c.fileSystems."/boot".device == "/dev/disk/by-partlabel/linux-boot";
  assert c.fileSystems."/".device == "/dev/disk/by-partlabel/linux";
  assert c.hardware.deviceTree.name == "qcom/sm8475-lenovo-asphalt.dtb";
  assert c.system.boot.loader.kernelFile == "Image";
  assert c.androidDevices.kernelPackage.config.isYes "EFI_STUB";
  assert c.androidDevices.kernelPackage.config.isYes "EFI";
  assert
    c.system.build.mobileBootImage.drvPath
    == flake.legacyPackages.${buildSystem}.devices.asphalt.u-boot.drvPath;
  assert !(c.boot.initrd.systemd.services ? mobile-initial-profile);
  assert !(builtins.elem "init=/nix/var/nix/profiles/system/init" c.boot.kernelParams);
  assert flake.inputs.nixpkgs.lib.all (a: a.assertion) c.assertions;
  {
    system = c.system.build.toplevel.drvPath;
    bootFiles = c.system.build.mobileBootFiles.drvPath;
    installer = c.system.build.installBootLoader;
    firmware = c.system.build.mobileBootImage.drvPath;
    recovery = recovery.system.build.mobileBootImage.drvPath;
  }
)
