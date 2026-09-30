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
    storage = lib.genAttrs [ "asphalt" "sheng" "clover" ] (
      device:
      let
        s = make device [
          {
            androidDevices.recovery.enable = true;
            androidDevices.persistentImage.rootfs.label = "MYROOT";
            androidDevices.boot.uefi.espSizeBytes = 536870912;
            androidDevices.recovery.minimumRootBytes = 8589934592;
          }
        ];
        cfg = s.config;
      in
      assert lib.all (a: a.assertion) cfg.assertions;
      assert lib.hasInfix "TARGET_ROOT_LABEL=MYROOT"
        cfg.boot.initrd.systemd.contents."/etc/mobile-recovery-target".text;
      assert lib.hasInfix "ROOT_LABEL=MYROOT" cfg.androidDevices.recovery.tools.buildCommand;
      assert
        device == "clover"
        || lib.hasInfix "MOBILE_ESP_BYTES=536870912" cfg.androidDevices.recovery.tools.buildCommand;
      assert !(s.options.hardware.${device} ? rootLabel);
      cfg.androidDevices.recovery.tools.drvPath
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
  }
)
