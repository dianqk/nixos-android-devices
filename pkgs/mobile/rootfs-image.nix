{
  pkgs,
  lib,
}:

{
  name,
  system,
  label,
  uuid,
  padding,
  systemLinkName,
  maximumBytes ? null,
  extraPopulateCommands ? "",
}:
let
  buildPackages = pkgs.buildPackages;
  closureInfo = buildPackages.closureInfo { rootPaths = [ system ]; };
in
pkgs.runCommand name
  {
    nativeBuildInputs = with buildPackages; [
      coreutils
      e2fsprogs
      fakeroot
      findutils
      gawk
    ];
  }
  ''
    mkdir -p root/nix/store "$out"
    xargs -r -I % cp -a --reflink=auto % -t root/nix/store/ < ${closureInfo}/store-paths
    cp ${closureInfo}/registration root/nix-path-registration
    mkdir -p root/nix/var/nix/profiles
    ln -s ${system} root/nix/var/nix/profiles/system-1-link
    ln -s system-1-link root/nix/var/nix/profiles/system
    ln -s ${system} root/${systemLinkName}
    ${extraPopulateCommands}

    inodes=$(find root -xdev | wc -l)
    blocks=$(du -s -B 4096 --apparent-size root | awk '{ print int($1 * 1.20) }')
    bytes=$((2 * 4096 * inodes + 4096 * blocks + ${toString padding}))
    bytes=$(((bytes + 1048575) / 1048576 * 1048576))
    image="$out/system.img"
    truncate -s "$bytes" "$image"
    fakeroot ${buildPackages.runtimeShell} -e -c '
      chown -hR 0:0 root
      exec mke2fs -q -F -t ext4 -b 4096 -I 256 -m 0 \
        -O ^64bit,^metadata_csum,^orphan_file \
        -E lazy_itable_init=0,lazy_journal_init=0 \
        -L "$2" -U "$3" -d root "$1"
    ' mobile-ext4 "$image" ${lib.escapeShellArg label} ${lib.escapeShellArg uuid}
    EXT2FS_NO_MTAB_OK=yes fsck.ext4 -n -f "$image"
    debugfs -R 'stat /${systemLinkName}' "$image" 2>&1 | grep -q 'Type: symlink'
    debugfs -R 'stat /nix-path-registration' "$image" 2>&1 | grep -q 'Type: regular'
    ${lib.optionalString (maximumBytes != null) ''
      test "$bytes" -le ${toString maximumBytes} || {
        echo "Filesystem image is $bytes bytes; limit is ${toString maximumBytes}" >&2
        exit 1
      }
    ''}
    mkdir -p "$out/nix-support"
    echo "file system $image" > "$out/nix-support/hydra-build-products"
  ''
