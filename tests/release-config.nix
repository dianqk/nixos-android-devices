# Downstream overrides must remain consistent across image and recovery paths.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    make =
      device: modules:
      flake.lib.mkSystem {
        inherit device buildSystem;
        nixpkgsConfig.allowUnfreePredicate =
          package:
          builtins.elem (lib.getName package) [
            "unicorn-firmware"
            "unicorn-firmware-zstd"
            "aurora-firmware"
            "aurora-firmware-zstd"
            "marble-firmware"
            "marble-firmware-zstd"
          ];
        modules = [ { androidDevices.usbSerial = "release-check"; } ] ++ modules;
      };
    sheng = make "sheng" [
      {
        services.fprintd.enable = true;
        services.greetd.enable = true;
        services.greetd.settings.default_session.command = "false";
        security.pam.services.login.fprintAuth = true;
        security.pam.services.greetd.rules.auth.login.modulePath = lib.mkForce "consumer-auth";
      }
    ];
    c = sheng.config;
  in
  {
    storage = lib.genAttrs [ "asphalt" "sheng" "clover" "aurora" "marble" "unicorn" ] (
      device:
      let
        s = make device [
          {
            androidDevices.recovery.enable = true;
            androidDevices.persistentImage.rootfs.label = "MYROOT";
            androidDevices.boot.uefi.label = "MYBOOT";
            androidDevices.boot.uefi.espSizeBytes = 536870912;
            androidDevices.recovery.minimumRootBytes = 8589934592;
          }
        ];
        cfg = s.config;
      in
      assert lib.all (a: a.assertion) cfg.assertions;
      assert !(s.options.hardware.${device} ? rootLabel);
      let
        contract = builtins.fromJSON cfg.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
      in
      assert contract.root_label == "MYROOT";
      assert contract.boot_label == "MYBOOT";
      assert contract.esp_bytes == 536870912;
      assert contract.minimum_root_bytes == 8589934592;
      assert !(cfg.boot.initrd.systemd.contents ? "/etc/mobile-recovery-target");
      cfg.system.build.mobileRecoveryUtils.drvPath
    );
    fingerprint =
      assert lib.all (a: a.assertion) c.assertions;
      assert c.security.pam.services.login.fprintAuth;
      assert c.security.pam.services.greetd.rules.auth.login.modulePath == "consumer-auth";
      assert !(c.systemd.services.fprintd.environment ? LD_LIBRARY_PATH);
      assert lib.any (
        p: lib.getName p == "xiaomi-sheng-libfprint"
      ) c.services.fprintd.package.buildInputs;
      c.services.fprintd.package.drvPath;
    fingerprintOverride =
      let
        custom =
          (sheng.extendModules {
            modules = [
              ({ pkgs, ... }: {
                services.fprintd.package = pkgs.fprintd;
              })
            ];
          }).config;
      in
      assert custom.services.fprintd.package.drvPath != c.services.fprintd.package.drvPath;
      custom.services.fprintd.package.drvPath;
    audioOrientation =
      let
        enabled =
          (sheng.extendModules {
            modules = [ { androidDevices.audio.orientation.enable = true; } ];
          }).config;
        routes =
          (builtins.fromJSON enabled.environment.etc."android-audio-orientation.json".text).orientations;
        slot =
          orientation: amp:
          (lib.findFirst (e: e.control == "${amp} ASPRX1 Slot Position") null routes.${orientation}).value;
        unit = enabled.systemd.user.services.android-audio-orientation;
      in
      assert !(c.environment.etc ? "android-audio-orientation.json");
      assert !(c.systemd.user.services ? android-audio-orientation);
      assert lib.all (a: a.assertion) enabled.assertions;
      assert lib.all (e: e.card == "XiaomiPad6SPro") (lib.concatLists (lib.attrValues routes));
      assert slot "normal" "TLH" == 0 && slot "normal" "BRL" == 1;
      assert slot "180" "TLH" == 1 && slot "180" "BRL" == 0;
      assert lib.length routes."90" == 6 && lib.length routes."270" == 6;
      assert unit.wantedBy == [ "wireplumber.service" ];
      assert unit.partOf == [ "wireplumber.service" ];
      unit.serviceConfig.ExecStart;
  }
)
