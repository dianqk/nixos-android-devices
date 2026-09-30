{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
    make =
      example:
      env.nixosSystem {
        modules = [
          flake.nixosModules.clover
          (flake.outPath + "/examples/clover/${example}.nix")
        ];
      };
    c = (make "system").config;
    recovery = (make "recovery").config;
  in
  assert c.boot.loader.systemd-boot.enable;
  assert !recovery.boot.loader.systemd-boot.enable;
  assert c.boot.loader.systemd-boot.configurationLimit == 10;
  assert c.boot.loader.systemd-boot.installDeviceTree;
  assert c.fileSystems."/boot".device == "/dev/disk/by-partlabel/system";
  assert c.fileSystems."/".device == "/dev/disk/by-partlabel/userdata";
  assert c.hardware.deviceTree.name == "qcom/sdm660-xiaomi-clover.dtb";
  assert c.system.boot.loader.kernelFile == "Image";
  assert c.androidDevices.kernelPackage.config.isYes "EFI_STUB";
  assert c.androidDevices.kernelPackage.config.isYes "EFI";
  assert c.androidDevices.kernelPackage.drvPath == recovery.androidDevices.kernelPackage.drvPath;
  assert c.androidDevices.kernelPackage.drvPath == flake.legacyPackages.${buildSystem}.devices.clover.kernel.drvPath;
  assert c.androidDevices.kernelPackage.config.isYes "DRM_MSM";
  assert c.androidDevices.kernelPackage.config.isYes "DRM_PANEL_NOVATEK_NT51021";
  assert
    c.system.build.mobileBootImage.drvPath
    == flake.legacyPackages.${buildSystem}.devices.clover.u-boot.drvPath;
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
