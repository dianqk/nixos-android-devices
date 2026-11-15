# The published RAM recovery is the one a consumer gets from the exported
# device module with only recovery enabled: no example policy, no serial or
# label override. Evaluation only; no image is built.
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  devices = [
    "polaris"
    "asphalt"
    "clover"
    "sheng"
    "aurora"
    "t880"
    "marble"
  ];
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  lib.genAttrs devices (
    device:
    let
      consumer = flake.lib.mkSystem {
        inherit device buildSystem;
        # Licence acceptance only gates evaluation; it does not change derivations.
        nixpkgsConfig.allowUnfree = true;
        modules = [ { androidDevices.recovery.enable = true; } ];
      };
      published = flake.legacyPackages.${buildSystem}.devices.${device}.recovery.drvPath;
      built = consumer.config.system.build.mobileBootImage.drvPath;
    in
    assert lib.assertMsg (published == built)
      "devices.${device}.recovery (${buildSystem}) differs from nixosModules.${device} with recovery.enable";
    assert lib.assertMsg (
      consumer.config.androidDevices.usbSerial == "RECOVERY_${lib.toUpper device}"
    ) "${device} recovery must default to its fixed per-model USB serial";
    assert lib.assertMsg (
      (builtins.fromJSON consumer.config.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text)
      .boot_label == "BOOT"
    ) "${device} recovery must create and check the BOOT boot label by default";
    published
  )
)
