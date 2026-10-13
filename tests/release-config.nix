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
            "aurora-firmware"
            "aurora-firmware-zstd"
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
    storage = lib.genAttrs [ "asphalt" "sheng" "clover" "aurora" ] (
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
      assert !(s.options.hardware.${device} ? rootLabel);
      let
        contract = builtins.fromJSON cfg.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
      in
      assert contract.root_label == "MYROOT";
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
  }
)
