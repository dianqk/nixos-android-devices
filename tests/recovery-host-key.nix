{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  checkPlatform =
    buildSystem:
    let
      env = flake.lib.mkBuildEnvironment {
        inherit buildSystem;
        config.allowUnfree = true;
      };
      make =
        device: extra:
        (env.nixosSystem {
          modules = [
            flake.nixosModules.${device}
            (flake.outPath + "/examples/${device}/recovery.nix")
            extra
          ];
        }).config;
      hasService = c: c.boot.initrd.systemd.services ? mobile-recovery-host-key;
      check =
        device: compatible: controller: partition:
        let
          c = make device { };
          service = c.boot.initrd.systemd.services.mobile-recovery-host-key;
          contract = builtins.fromJSON c.boot.initrd.systemd.contents."/etc/recovery-host-key.json".text;
        in
        assert lib.all (a: a.assertion) c.assertions;
        assert hasService c;
        assert contract.compatible == compatible;
        assert contract.controller == controller;
        assert contract.root_device == "/dev/disk/by-partlabel/${partition}";
        assert contract.root_label == c.androidDevices.persistentImage.rootfs.label;
        assert service.serviceConfig.PrivateMounts;
        assert service.serviceConfig.TimeoutStartSec == 15;
        assert lib.all (n: builtins.elem n service.before) [
          "mobile-recovery-sshd.service"
          "mobile-recovery-daemon.service"
          "mobile-recovery-console.service"
          "mobile-recovery-screen.service"
        ];
        contract;
      disabled = make "aurora" { androidDevices.initrdUsb.ssh.hostKeyStorage.enable = false; };
      acm = make "aurora" { androidDevices.initrdUsb.network.enable = lib.mkForce false; };
      minimal = make "aurora" { androidDevices.recovery.minimal = lib.mkForce true; };
      early = make "aurora" { androidDevices.recovery.enable = lib.mkForce false; };
    in
    assert !hasService disabled && !hasService acm && !hasService minimal && !hasService early;
    assert !(disabled.boot.initrd.systemd.contents ? "/etc/recovery-host-key.json");
    assert lib.hasInfix "ssh-keygen"
      disabled.boot.initrd.systemd.services.mobile-recovery-sshd.preStart;
    {
      polaris = check "polaris" "xiaomi,polaris" "1d84000.ufshc" "userdata";
      clover = check "clover" "xiaomi,clover" "c0c4000.sdhci" "userdata";
      asphalt = check "asphalt" "lenovo,asphalt" "1d84000.ufshc" "linux";
      sheng = check "sheng" "xiaomi,sheng" "1d84000.ufshc" "linux";
      aurora = check "aurora" "xiaomi,aurora" "1d84000.ufshc" "linux";
      ramFallback = true;
    };
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] checkPlatform
