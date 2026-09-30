{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  env = flake.lib.mkBuildEnvironment {
    buildSystem = "aarch64-linux";
    config.allowUnfree = true;
  };
  base = env.nixosSystem {
    modules = [
      flake.nixosModules.polaris
      (flake.outPath + "/examples/polaris/recovery.nix")
    ];
  };
  config = module: (base.extendModules { modules = [ module ]; }).config;
  defaults = base.config;
  acm = config { androidDevices.initrdUsb.network.enable = false; };
  ncm = config { androidDevices.initrdUsb.acm.enable = false; };
  secure = config {
    androidDevices.initrdUsb.ssh.requirePublicKey = true;
    androidDevices.initrdUsb.authorizedKeys = [ "ssh-ed25519 TEST" ];
  };
  neither = config {
    androidDevices.initrdUsb = {
      acm.enable = false;
      network.enable = false;
    };
  };
  conflict = config { boot.initrd.systemd.services.mobile-usb-gadget.script = "true"; };
  valid = c: lib.all (a: a.assertion) c.assertions;
  rejects = c: prefix: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) c.assertions;
  ssh = c: c.boot.initrd.systemd.contents."/etc/ssh/recovery_sshd_config".text;
in
assert valid defaults && valid acm && valid ncm && valid secure;
assert
  defaults.androidDevices.initrdUsb.acm.enable && defaults.androidDevices.initrdUsb.network.enable;
assert acm.androidDevices.initrdUsb.acm.enable && !acm.androidDevices.initrdUsb.network.enable;
assert !ncm.androidDevices.initrdUsb.acm.enable && ncm.androidDevices.initrdUsb.network.enable;
assert !(acm.boot.initrd.systemd.services ? mobile-recovery-sshd);
assert !(ncm.boot.initrd.systemd.services ? mobile-recovery-console);
assert lib.hasInfix "PermitEmptyPasswords yes" (ssh defaults);
assert lib.hasInfix "PubkeyAuthentication no" (ssh defaults);
assert lib.hasInfix "PermitEmptyPasswords no" (ssh secure);
assert lib.hasInfix "PubkeyAuthentication yes" (ssh secure);
assert
  secure.boot.initrd.systemd.contents."/etc/ssh/recovery_authorized_keys".text
  == "ssh-ed25519 TEST\n";
assert rejects neither "initrdUsb needs ACM or NCM";
assert rejects conflict "initrdUsb owns the initrd USB controller";
{
  composite = true;
  acmOnly = true;
  ncmOnly = true;
  passwordless = true;
  publicKey = true;
  conflictChecks = true;
}
