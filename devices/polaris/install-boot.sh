#!/usr/bin/env bash
# Explicit U-Boot firmware installation guarded by the selected storage role resolver.
set -Eeuo pipefail
current_system=/run/current-system
initial=false
if [[ ${1:-} == --initial ]]; then initial=true; shift; fi
if [[ ${1:-} == --current-system ]]; then
  $initial && { echo '--initial cannot select a rollback system' >&2; exit 2; }
  current_system=${2:?Missing current system}
  shift 2
fi
check_only=false
if [[ ${1:-} == --check ]]; then check_only=true; shift; fi
if [[ $# != 3 ]]; then
  echo 'Usage: polaris-install-boot [--initial|--current-system SYSTEM] [--check] BOOT_IMAGE NIXOS_SYSTEM EXPECTED_FULL_BOOT_SHA256' >&2
  exit 2
fi
fail() { echo "$*" >&2; exit 1; }
storage_roles=${POLARIS_STORAGE_ROLES:?Set POLARIS_STORAGE_ROLES to a verified per-phone contract}
# shellcheck source=/dev/null
source "$storage_roles"
[[ $EUID == 0 ]] || fail 'Must run as root on Polaris.'
image=$(readlink -f -- "$1")
new_system=$(readlink -f -- "$2")
expected_sha=$3
[[ $expected_sha =~ ^[0-9a-f]{64}$ ]] || fail 'Expected SHA-256 is mandatory.'
[[ -f $image && -x $new_system/init && -f $new_system/mobile-efi ]] || fail 'A Polaris EFI system and its U-Boot image are required.'
[[ $(readlink -f -- "$new_system/polaris-boot.img") == "$image" ]] ||
  fail 'Image does not belong to the supplied system closure.'
profile=/nix/var/nix/profiles/system
if ! $check_only; then
  [[ $(readlink -f -- "$profile") == "$new_system" ]] ||
    fail 'Select the new system profile before installing its boot image.'
fi
tr '\0' '\n' < /proc/device-tree/compatible | grep -qx 'xiaomi,polaris' ||
  fail 'Not a Polaris device.'
polaris_partition_role boot
target=$POLARIS_TARGET
block_name=$(basename "$target")
block_sysfs=$(readlink -f "/sys/class/block/$block_name")
[[ $block_sysfs == /sys/devices/platform/soc@0/1d84000.ufshc/* ]] || fail 'Wrong UFS controller.'
[[ $(cat "$block_sysfs/start") == "$POLARIS_PART_OFFSET" ]] || fail 'Wrong boot start sector.'
[[ $(cat "$block_sysfs/size") == "$((POLARIS_PART_BYTES / 512))" ]] || fail 'Wrong boot sector count.'
[[ $(blockdev --getsize64 "$target") == "$POLARIS_PART_BYTES" ]] || fail 'Wrong boot size.'
[[ $(head -c 8 "$image") == 'ANDROID!' ]] || fail 'Not an Android boot image.'
image_size=$(stat -Lc '%s' "$image")
(( image_size > 4096 && image_size <= POLARIS_PART_BYTES )) || fail 'Image size is invalid.'
exec 9>/run/lock/polaris-install-boot.lock
flock -n 9 || fail 'Another Polaris boot install is running.'
read -r installed_sha _ < <(sha256sum "$target")
[[ $installed_sha == "$expected_sha" ]] || fail 'Boot changed: expected hash mismatch.'
read -r image_sha _ < <(sha256sum "$image")
tail_size=$((POLARIS_PART_BYTES - image_size))
read -r expected_new_sha _ < <(
  { cat "$image"; head -c "$tail_size" /dev/zero; } | sha256sum
)
echo "Validated: $target, image $image_size bytes, old SHA-256 $installed_sha"
if ! $initial; then
  # Pair the installed firmware with the current EFI generation before replacing it.
  old_system=$(readlink -f -- "$current_system")
  [[ -x $old_system/init && -f $old_system/mobile-efi && -f $old_system/polaris-boot.img ]] || fail 'Invalid rollback system.'
  old_image_size=$(stat -Lc '%s' "$old_system/polaris-boot.img")
  (( old_image_size > 4096 && old_image_size <= POLARIS_PART_BYTES )) || fail 'Invalid rollback image size.'
  # Fastboot may leave a nonzero partition tail. Pair the current system with
  # the exact installed image prefix; never infer a zero-filled tail.
  rollback_sha=$(sha256sum "$old_system/polaris-boot.img")
  rollback_sha=${rollback_sha%% *}
  installed_prefix_sha=$(head -c "$old_image_size" "$target" | sha256sum)
  installed_prefix_sha=${installed_prefix_sha%% *}
  [[ $rollback_sha == "$installed_prefix_sha" ]] ||
    fail 'Current system does not match old boot; supply --current-system with its paired system.'
fi
# Require complete registered closures, but do not reread every store file on
# every update.  The closure import verifies new NARs and compares their DB hashes.
systems=("$new_system")
if ! $initial; then systems+=("$old_system"); fi
for system in "${systems[@]}"; do
  closure=$(nix-store --query --requisites "$system")
  mapfile -t paths <<< "$closure"
  [[ -n $closure && ${#paths[@]} -gt 0 ]] || fail 'Empty system closure.'
  nix-store --check-validity "${paths[@]}"
done
if $check_only; then exit 0; fi
if [[ $installed_sha == "$expected_new_sha" ]]; then
  echo 'Matching U-Boot image already installed; no partition write needed.'
  exit 0
fi

write_started=false
write_failure() {
  local rc=$?
  trap - ERR INT TERM HUP
  if $write_started; then
    echo 'CRITICAL: boot write or readback failed and no backup was made. Do not reboot; reinstall a matching, rebuildable boot image.' >&2
  fi
  exit "${rc:-1}"
}
trap write_failure ERR
trap 'false' INT TERM HUP
write_started=true
dd if="$image" of="$target" bs=4M conv=fsync status=none
# Remove the old Android AVB footer/trailing image data, within boot only.
dd if=/dev/zero of="$target" bs=1M oflag=seek_bytes iflag=count_bytes \
  seek="$image_size" count="$tail_size" conv=notrunc,fsync status=none
read -r readback_sha _ < <(
  dd if="$target" bs=1M iflag=count_bytes count="$image_size" status=none | sha256sum
)
[[ $readback_sha == "$image_sha" ]]
read -r whole_readback_sha _ < <(sha256sum "$target")
[[ $whole_readback_sha == "$expected_new_sha" ]]
sync
trap - ERR INT TERM HUP
echo "Verified image SHA-256: $readback_sha"
echo 'Whole-partition SHA-256 to use for the next update:'
echo "$whole_readback_sha  $target"
echo 'Installation complete; reboot explicitly when ready.'
