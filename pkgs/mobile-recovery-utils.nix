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
  for name in recovery mobile-recovery-daemon mobile-recovery-screen mobile-recovery-host-key; do
    ln -s ${screenPackage}/bin/$name $out/bin/$name
  done
''
