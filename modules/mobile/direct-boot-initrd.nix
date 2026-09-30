# Only imported by the supplemental boot-kernel artifact evaluation.
# Keep the installed system and its normal EFI initrd unchanged.
{ systemPath }:
{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  findClosure = androidPackages.packaging.writeShellScript "mobile-direct-find-nixos-closure" ''
    set -eu
    closure=$(cat /etc/mobile-direct-system)
    test -x "/sysroot$closure/init"
    ln -s "$closure" /nixos-closure
    printf 'NEW_INIT=\n' > /etc/switch-root.conf
  '';
in
{
  boot.initrd.systemd = {
    # Do not collect the entire installed closure into RAM. The image's
    # uncompressed init= parameter retains the real Nix store reference.
    contents."/etc/mobile-direct-system".text = builtins.unsafeDiscardStringContext systemPath;
    # Use the configured root mount even when firmware rewrites init=/root=.
    # This supplemental image selects its closure explicitly.
    contents."/etc/systemd/system-generators/systemd-fstab-generator".source =
      androidPackages.packaging.runCommand "disable-direct-boot-fstab-generator" { }
        ''
          ln -s /dev/null $out
        '';
    mounts = [
      {
        what = config.fileSystems."/".device;
        where = "/sysroot";
        type = config.fileSystems."/".fsType;
        options = lib.concatStringsSep "," ([ "rw" ] ++ config.fileSystems."/".options);
        requiredBy = [ "initrd-root-fs.target" ];
        before = [ "initrd-root-fs.target" ];
        unitConfig.DefaultDependencies = false;
      }
    ];
    services.initrd-find-nixos-closure.serviceConfig.ExecStart = lib.mkForce findClosure;
  };
}
