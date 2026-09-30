#!/bin/sh
set -eu
export MOBILE_RECOVERY_LIBRARY_ONLY=1
. /bin/recovery
test "$#" = 1 || fail 'Usage: recovery prepare-boot --check|--confirm'
case "$1" in --check|--confirm) ;; *) fail 'Explicit check or confirm required' ;; esac
operation_lock
reboot_gate
cleanup() {
  umount /recovery/proc 2>/dev/null || true
  umount /recovery 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
mount_userdata_plain ro,noload
# A previously interrupted deployment must be completed before erasing a volume.
test ! -e /recovery/var/lib/mobile-offline-deploy/pending || fail 'Finish the pending deployment first'
if test -L /recovery/nix/var/nix/profiles/system; then
  selected=$(selected_system)
  mount -t proc proc /recovery/proc
  NIX_CONFIG='extra-experimental-features = nix-command read-only-local-store' NIX_REMOTE='local?read-only=true' \
    chroot /recovery "$selected/sw/bin/nix" store verify --all --no-trust || fail 'The userdata store is not independently valid'
  umount /recovery/proc
else
  # Allow an empty, freshly formatted ext4 root, never unknown existing data.
  initial_root_is_empty
fi
polaris_partition_role esp no
esp=$POLARIS_TARGET
esp_mm=$(cat "/sys/class/block/$(basename "$esp")/dev")
if awk -v mm="$esp_mm" '$3 == mm { found=1 } END { exit !found }' /proc/self/mountinfo; then fail 'The boot filesystem is mounted'; fi
test "$POLARIS_PARTLABEL" = system && test "$POLARIS_FS_TYPE" = vfat || fail 'Expected physical system FAT contract'
if test -n "$POLARIS_FS_UUID"; then
  printf '%s\n' "$POLARIS_FS_UUID" | grep -Eq '^[0-9a-f]{4}-[0-9a-f]{4}$' || fail 'Invalid FAT volume ID'
fi
printf '%s\n' "$POLARIS_FS_LABEL" | grep -Eq '^[A-Z0-9_]{1,11}$' || fail 'Invalid FAT label'
if test "$(blkid -p -s TYPE -o value "$esp" || true)" = vfat; then
  polaris_partition_role esp yes
  fsck.fat -n "$esp"
  echo 'Matching FAT /boot is already prepared; no formatting performed.'
  exit 0
fi
echo "Prepare FAT32 on $esp ($POLARIS_PART_BYTES bytes, $POLARIS_PARTUUID); GPT geometry stays unchanged."
if test "$1" = --check; then echo 'Check only; no filesystem or partition writes performed.'; exit 0; fi
mount -o remount,rw /recovery
mkdir -p /recovery/var/lib/mobile-efi-preparation
printf 'Install and verify EFI boot files before rebooting.\n' > /recovery/var/lib/mobile-efi-preparation/pending
sync
if test -n "$POLARIS_FS_UUID"; then
  mkfs.fat -F 32 -n "$POLARIS_FS_LABEL" -i "$(printf %s "$POLARIS_FS_UUID" | tr -d -)" "$esp"
else
  mkfs.fat -F 32 -n "$POLARIS_FS_LABEL" "$esp"
fi
polaris_partition_role esp yes
fsck.fat -n "$esp"
sync
echo 'FAT /boot prepared. Install the EFI system and U-Boot before rebooting.'
