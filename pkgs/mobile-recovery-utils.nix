{
  lib,
  runCommand,
  e2fsprogs,
  dosfstools,
  util-linux,
  gptfdisk,
  parted,
  mmc-utils,
  file,
  zstd,
  xz,
  systemd,
  gnutar,
  jq,
  recoveryTools,
  screenPackage,
  extended ? false,
}:
let
  select = package: names: {
    package = lib.getBin package;
    inherit names;
  };
  tools = [
    (select util-linux [
      "blkid"
      "blockdev"
      "fdisk"
      "findmnt"
      "flock"
      "lsblk"
      "mount"
      "mountpoint"
      "sfdisk"
      "umount"
      "unshare"
      "uuidgen"
    ])
    (select e2fsprogs [
      "e2fsck"
      "mke2fs"
      "resize2fs"
      "tune2fs"
      "dumpe2fs"
    ])
    (select dosfstools [
      "mkfs.fat"
      "fsck.fat"
    ])
    (select systemd [
      "reboot"
      "poweroff"
    ])
    (select gnutar [ "tar" ])
  ]
  ++ lib.optionals extended [
    (select jq [ "jq" ])
    (select gptfdisk [
      "gdisk"
      "sgdisk"
    ])
    (select parted [
      "parted"
      "partprobe"
    ])
    (select mmc-utils [ "mmc" ])
    (select file [ "file" ])
    (select zstd [ "zstd" ])
    (select xz [ "xz" ])
  ];
in
runCommand "mobile-recovery-utils" { } ''
  mkdir -p $out/bin
  cp ${./mobile-recovery-deploy/initial.sh} $out/bin/mobile-install-initial
  chmod +x $out/bin/mobile-install-initial
  cp ${./mobile-recovery-deploy/deploy.sh} $out/bin/mobile-recovery-deploy
  cp ${./mobile-recovery-deploy/target.sh} $out/bin/mobile-recovery-target
  cp ${./mobile-recovery-deploy/rebuild.sh} $out/bin/mobile-offline-rebuild
  chmod +x $out/bin/mobile-recovery-deploy $out/bin/mobile-recovery-target $out/bin/mobile-offline-rebuild
  ${lib.concatStringsSep "\n" (
    map (
      { package, names }:
      lib.concatMapStringsSep "\n" (name: ''
        if test -x ${package}/bin/${name}; then
          ln -s ${package}/bin/${name} $out/bin/${name}
        else
          test -x ${package}/sbin/${name}
          ln -s ${package}/sbin/${name} $out/bin/${name}
        fi
      '') names
    ) tools
  )}
  ln -s ${recoveryTools}/bin/* ${screenPackage}/bin/* $out/bin/
''
