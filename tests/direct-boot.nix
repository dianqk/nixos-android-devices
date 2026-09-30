{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
in
lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  lib.genAttrs [ "sheng" "clover" ] (
    device:
    let
      system = flake.lib.mkSystem {
        inherit device buildSystem;
        modules = [ (flake.outPath + "/examples/${device}/system.nix") ];
      };
      c = system.config;
      recovery = flake.lib.mkSystem {
        inherit device buildSystem;
        modules = [ (flake.outPath + "/examples/${device}/recovery.nix") ];
      };
      direct =
        (system.extendModules {
          modules = [
            (import ../modules/mobile/direct-boot-initrd.nix {
              systemPath = c.system.build.toplevel;
            })
          ];
        }).config;
      artifacts = flake.lib.mkArtifacts system;
      image = artifacts.boot-kernel;
      mounts = builtins.filter (m: m.where == "/sysroot") direct.boot.initrd.systemd.mounts;
      marker = direct.boot.initrd.systemd.contents."/etc/mobile-direct-system".text;
    in
    assert lib.all (a: a.assertion) c.assertions;
    assert lib.all (a: a.assertion) direct.assertions;
    assert c.boot.loader.systemd-boot.enable;
    assert image.system == buildSystem;
    assert image.targetSystem.drvPath == c.system.build.toplevel.drvPath;
    assert image.kernel.drvPath == c.system.build.kernel.drvPath;
    assert image.initrd.drvPath == direct.system.build.initialRamdisk.drvPath;
    assert image.initrd.drvPath != c.system.build.initialRamdisk.drvPath;
    assert image.drvPath == flake.legacyPackages.${buildSystem}.devices.${device}.boot-kernel.drvPath;
    assert
      artifacts.boot.drvPath == flake.legacyPackages.${buildSystem}.devices.${device}.u-boot.drvPath;
    assert !(c.boot.initrd.systemd.contents ? "/etc/mobile-direct-system");
    assert !((flake.lib.mkArtifacts recovery) ? boot-kernel);
    assert marker == toString c.system.build.toplevel;
    assert builtins.getContext marker == { };
    assert builtins.length mounts == 1;
    assert (builtins.head mounts).what == c.fileSystems."/".device;
    assert (builtins.head mounts).type == "ext4";
    assert
      direct.boot.initrd.systemd.contents ? "/etc/systemd/system-generators/systemd-fstab-generator";
    assert lib.hasInfix
      (builtins.unsafeDiscardStringContext "${c.hardware.deviceTree.package}/${c.hardware.deviceTree.name}")
      image.buildCommand;
    assert lib.hasInfix (builtins.unsafeDiscardStringContext "init=${c.system.build.toplevel}/init")
      image.buildCommand;
    assert lib.hasInfix (builtins.unsafeDiscardStringContext (
      toString image.initrd
    )) image.buildCommand;
    assert builtins.hasAttr (builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath) (
      builtins.getContext image.buildCommand
    );
    assert direct.boot.initrd.systemd.services ? mobile-deployment-complete;
    {
      bootKernel = image.drvPath;
      system = c.system.build.toplevel.drvPath;
      initrd = image.initrd.drvPath;
      root = (builtins.head mounts).what;
      selector = direct.boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig.ExecStart;
    }
  )
)
