#!/usr/bin/env bash
# Stage a standard EFI generation. No live activation, firmware write or reboot.
set -Eeuo pipefail
check_only=false
if [[ ${1:-} == --check ]]; then check_only=true; shift; fi
fail() { echo "$*" >&2; exit 1; }
[[ $# == 2 && $EUID == 0 ]] || fail 'Usage: polaris-update-system [--check] SYSTEM UBOOT_SHA256'
source "${POLARIS_STORAGE_ROLES:?Missing storage contract}"
new_system=$(readlink -f "$1")
[[ $new_system == /nix/store/*-nixos-system-${POLARIS_SYSTEM_HOSTNAME:?Missing system hostname}-* && -x $new_system/init && -e $new_system/mobile-efi ]] || fail 'Invalid EFI system'
[[ -e /run/current-system/mobile-efi && ! -e /etc/initrd-release ]] || fail 'Run updates from the installed Polaris EFI system; use RAM recovery for first installation'
[[ $2 =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid firmware hash'
tr '\0' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,polaris || fail 'Wrong board'
cmp -s "$POLARIS_STORAGE_ROLES" /run/current-system/polaris-storage-roles || fail 'Storage contract changed'
polaris_partition_role userdata yes
[[ $(readlink -f "$(findmnt -rn -M / -o SOURCE)") == "$POLARIS_TARGET" ]] || fail 'Wrong root device'
polaris_partition_role esp yes
[[ $(findmnt -rn -M /boot -o FSTYPE) == vfat ]] || fail 'FAT /boot is not mounted'
[[ $(readlink -f "$(findmnt -rn -M /boot -o SOURCE)") == "$POLARIS_TARGET" ]] || fail 'Wrong /boot device'
root_entry() { awk '$1 !~ /^#/ && $2 == "/" { count++; device=$1; type=$3 } END { if (count == 1) print device, type; else exit 1 }' "$1/etc/fstab"; }
new_root=$(root_entry "$new_system") || fail 'Invalid target root entry'
old_root=$(root_entry /run/current-system) || fail 'Invalid current root entry'
[[ $new_root == "$old_root" ]] || fail 'Update changes the root filesystem'
image=$new_system/polaris-boot.img
[[ $(sha256sum "$image" | cut -d ' ' -f 1) == "$2" ]] || fail 'Transferred firmware hash mismatch'
polaris_partition_role boot
image_bytes=$(stat -Lc %s "$image")
(( image_bytes > 4096 && image_bytes <= POLARIS_PART_BYTES )) || fail 'Invalid firmware size'
[[ $(head -c "$image_bytes" "$POLARIS_TARGET" | sha256sum | cut -d ' ' -f 1) == "$2" ]] || fail 'Install the changed U-Boot explicitly before this update'
mapfile -t paths < <(nix-store --query --requisites "$new_system")
[[ ${#paths[@]} -gt 0 ]] || fail 'Empty closure'
nix-store --check-validity "${paths[@]}"
exec 8>/run/lock/polaris-update.lock
flock -n 8 || fail 'Another update is running'
if $check_only; then echo 'Validated EFI generation; no changes performed.'; exit 0; fi
profile=/nix/var/nix/profiles/system
old_system=$(readlink -f "$profile")
rollback() {
  trap - ERR
  nix-env -p "$profile" --set "$old_system"
  "$old_system/bin/switch-to-configuration" boot || echo 'Inspect /boot before rebooting' >&2
  exit 1
}
trap rollback ERR
nix-env -p "$profile" --set "$new_system"
"$new_system/bin/switch-to-configuration" boot
sync
trap - ERR
echo 'EFI generation staged. Firmware unchanged; reboot explicitly when ready.'
