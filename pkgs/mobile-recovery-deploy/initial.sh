#!/bin/sh
# Shared first installation. Adapters supply identity/slot/partition checks only.
set -eu
ROOT=/recovery
RESULT=/run/mobile-initial-install.result
fail() { echo "ERROR: $*" >&2; exit 1; }
. /etc/mobile-recovery-target
MOBILE_RECOVERY_LIBRARY_ONLY=1
export MOBILE_RECOVERY_LIBRARY_ONLY
. /etc/mobile-initial-install-adapter

test "$#" = 6 && test "$1" = install-initial ||
  fail 'Usage: recovery install-initial MANIFEST REGISTRATION SYSTEM MIN_BYTES --check|--confirm'
case "$6" in --check|--confirm) ;; *) fail 'Choose --check or --confirm' ;; esac
initial_manifest=$2
initial_registration=$3
initial_system=$4
initial_bytes=$5
case "$initial_system" in
  /nix/store/*-nixos-system-"$TARGET_HOSTNAME"-*) ;;
  *) fail 'System does not match the configured target host' ;;
esac
case "$initial_bytes" in ''|*[!0-9]*) fail 'Invalid closure size' ;; esac
test "$initial_bytes" -gt 0 && test "$initial_bytes" -le 1099511627776 || fail 'Invalid closure size'
for input in "$initial_manifest" "$initial_registration"; do
  test -f "$input" && test ! -L "$input" && test -s "$input" || fail 'Missing bootstrap input'
done
found=false
while read -r hash path extra; do
  test -z "${extra:-}" || fail 'Malformed manifest'
  printf '%s\n' "$hash" | grep -Eq '^sha256:[0-9abcdfghijklmnpqrsvwxyz]{52}$' || fail 'Invalid NAR hash'
  printf '%s\n' "$path" | grep -Eq '^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/[:space:]]+$' || fail 'Invalid store path'
  if test "$path" = "$initial_system"; then found=true; fi
done < "$initial_manifest"
$found || fail 'System is absent from manifest'
test "$(cut -d ' ' -f 2 "$initial_manifest" | sort -u | wc -l)" = "$(wc -l < "$initial_manifest")" || fail 'Duplicate manifest path'

# Reject ambiguous GPT names, mounted devices, or changed partition identity.
checked_devices() {
  initial_devices
  test "$root_device" != "$esp_device" && test "$root_device" != "$boot_device" &&
    test "$esp_device" != "$boot_device" || fail 'Partition roles overlap'
  for partition in "$root_device" "$esp_device" "$boot_device"; do
    test -b "$partition" || fail 'Expected a block partition'
    label=$(blkid -p -s PART_ENTRY_NAME -o value "$partition")
    test -n "$label" || fail 'Missing GPT label'
    matches=$(lsblk -rnpo PATH,PARTLABEL | awk -v label="$label" '$2 == label { print $1 }')
    test "$matches" = "$partition" || fail 'Ambiguous GPT partition label'
  done
  test "$(blkid -p -s TYPE -o value "$root_device")" = ext4 || fail 'Prepare the ext4 root first'
  test "$(blkid -p -s LABEL -o value "$root_device")" = "$TARGET_ROOT_LABEL" || fail 'Root filesystem label mismatch'
  test "$(blkid -p -s TYPE -o value "$esp_device")" = vfat || fail 'Prepare the FAT boot partition first'
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$esp_device")" = "$TARGET_ESP_LABEL" || fail 'ESP label mismatch'
}
identities() {
  for partition in "$root_device" "$esp_device" "$boot_device"; do
    printf '%s %s %s %s\n' "$partition" "$(blockdev --getsize64 "$partition")" \
      "$(blkid -p -s PART_ENTRY_UUID -o value "$partition")" \
      "$(blkid -p -s PART_ENTRY_OFFSET -o value "$partition")"
  done
}
empty_root() {
  for directory in boot var var/lib var/lib/mobile-efi-preparation lost+found; do
    test ! -L "$ROOT/$directory" || fail 'Unsafe initial root directory'
  done
  test -z "$(find "$ROOT" -mindepth 1 \
    -path "$ROOT/lost+found" -prune -o \
    ! -path "$ROOT/boot" ! -path "$ROOT/var" ! -path "$ROOT/var/lib" \
    ! -path "$ROOT/var/lib/mobile-efi-preparation" \
    ! -path "$ROOT/var/lib/mobile-efi-preparation/pending" -print -quit)" ||
    fail 'Root is not empty; first installation refuses to overwrite it'
}
cleanup() {
  cd /
  for point in dev proc sys run boot; do
    if mountpoint -q "$ROOT/$point"; then umount -R "$ROOT/$point" || return 1; fi
  done
  if mountpoint -q "$ROOT"; then umount "$ROOT" || return 1; fi
}
failed() {
  rc=$?
  trap - EXIT HUP INT TERM
  if ! cleanup; then echo 'Cleanup failed: inspect remaining mounts before retrying.' >&2; fi
  printf 'failed %s %s %s\n' "$manifest_hash" "$initial_system" "$rc" > "$RESULT"
  if test "${writing_boot:-false}" = true; then
    echo 'Boot write/readback failed; stay in recovery and reinstall matching firmware before rebooting.' >&2
  fi
  exit "$rc"
}

operation_lock
recovery_gate
checked_devices
before=$(identities)
boot_before=$(sha256sum "$boot_device" | cut -d ' ' -f 1)
boot_bytes=$(blockdev --getsize64 "$boot_device")
e2fsck -fn "$root_device" || fail 'Root failed read-only fsck'
fsck.fat -n "$esp_device" || fail 'FAT boot failed read-only fsck'
test ! -L "$ROOT" || fail 'Unsafe root mountpoint'
mkdir -p "$ROOT"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mount -t ext4 -o ro,noload "$root_device" "$ROOT"
empty_root
available=$(df -Pk "$ROOT" | awk 'END { print $4 }')
case "$available" in ''|*[!0-9]*) fail 'Cannot measure root free space' ;; esac
test "$available" -gt $(((initial_bytes + 1073741824) / 1024)) || fail 'Root needs closure space plus 1 GiB reserve'
cleanup
trap - EXIT HUP INT TERM
if test "$6" = --check; then
  echo "Ready: empty $root_device, FAT $esp_device, firmware $boot_device ($boot_before)"
  echo 'Check only; --confirm receives the closure and installs EFI before firmware.'
  exit 0
fi

manifest_hash=$(sha256sum "$initial_manifest" | cut -d ' ' -f 1)
printf 'running %s %s\n' "$manifest_hash" "$initial_system" > "$RESULT"
trap failed EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
checked_devices
test "$(identities)" = "$before" || fail 'Partition identities changed'
mount -t ext4 -o rw "$root_device" "$ROOT"
empty_root
mkdir -p "$ROOT/var/lib/mobile-efi-preparation"
printf 'First installation incomplete.\n' > "$ROOT/var/lib/mobile-efi-preparation/pending"
sync
mkdir -p "$ROOT/nix/store" "$ROOT/nix/var/nix/profiles" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/run" "$ROOT/tmp"
chmod 1777 "$ROOT/tmp"
# The host streams relative nix/store members only. Interrupted extraction leaves
# a nonempty root and pending marker; a retry must explicitly prepare an empty root.
tar --extract --file=- --directory="$ROOT" --numeric-owner --same-permissions
for file in init sw/bin/nix-store sw/bin/nix-env sw/bin/nix bin/switch-to-configuration; do
  chroot "$ROOT" "$initial_system/sw/bin/test" -x "$initial_system/$file" || fail 'Incomplete system tools'
done
test -f "$ROOT$initial_system/mobile-efi" || fail 'System must support EFI'
test "$(cat "$ROOT$initial_system/mobile-device")" = "$(cat /etc/mobile-ram-recovery)" || fail 'System belongs to another device'
initial_check_system
for point in dev proc sys; do
  mount --rbind "/$point" "$ROOT/$point"
  # Cleanup must not propagate unmounts back into the live recovery.
  mount --make-rslave "$ROOT/$point"
done
# Keep recovery's PID1 and service sockets out of the installation chroot.
mount -t tmpfs -o mode=0755 tmpfs "$ROOT/run"
ln -s "$initial_system" "$ROOT/run/current-system"
export NIX_REMOTE=local
unset NIX_DAEMON_SOCKET_PATH
nix_store=$initial_system/sw/bin/nix-store
nix_env=$initial_system/sw/bin/nix-env
chroot "$ROOT" "$nix_store" --load-db < "$initial_registration"
chroot "$ROOT" "$nix_store" --verify --check-contents || fail 'Store content verification failed'
chroot "$ROOT" "$nix_store" --query --requisites "$initial_system" | sort > /run/mobile-initial-closure.actual
cut -d ' ' -f 2 "$initial_manifest" | sort > /run/mobile-initial-closure.expected
cmp -s /run/mobile-initial-closure.actual /run/mobile-initial-closure.expected || fail 'Closure differs from manifest'
while read -r expected path; do
  actual=$(chroot "$ROOT" "$initial_system/sw/bin/nix" --extra-experimental-features nix-command hash path --type sha256 --base32 "$path")
  test "sha256:$actual" = "$expected" || fail "Content hash mismatch: $path"
done < "$initial_manifest"
# Match both fstab entries to the actual validated partitions, independent of
# whether configuration uses LABEL, UUID, PARTLABEL or PARTUUID symlinks.
for entry in / /boot; do
  if test "$entry" = /; then expected_device=$root_device; expected_type=ext4; else expected_device=$esp_device; expected_type=vfat; fi
  root_entry=$(chroot "$ROOT" "$initial_system/sw/bin/awk" -v point="$entry" \
    '$1 !~ /^#/ && $2 == point { count++; device=$1; type=$3 } END { if (count == 1) print device, type; else exit 1 }' \
    "$initial_system/etc/fstab") || fail 'Expected exactly one root and boot fstab entry'
  read -r configured_device configured_type extra <<ENTRIES
$root_entry
ENTRIES
  test -z "${extra:-}" && test "$configured_type" = "$expected_type" || fail 'Filesystem type mismatch'
  test "$(readlink -f "$configured_device")" = "$expected_device" || fail 'System fstab selects another partition'
done
image=$(chroot "$ROOT" "$initial_system/sw/bin/readlink" -f "$initial_system/mobile-boot.img")
printf '%s\n' "$image" | grep -Eq '^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/[:space:]]+(/[^[:space:]]*)?$' || fail 'Firmware is outside the closure'
chroot "$ROOT" "$nix_store" --query --requisites "$initial_system" | grep -Fxq "$(printf '%s' "$image" | cut -d / -f 1-4)" || fail 'Firmware is not in system closure'
image_file=$ROOT$image
test -f "$image_file" && test "$(head -c 8 "$image_file")" = 'ANDROID!' || fail 'Expected Android-format U-Boot image'
image_bytes=$(stat -Lc '%s' "$image_file")
test "$image_bytes" -gt 4096 && test "$image_bytes" -le "$boot_bytes" || fail 'Firmware does not fit the boot partition'
chroot "$ROOT" "$nix_env" -p /nix/var/nix/profiles/system --set "$initial_system"
mkdir -p "$ROOT/etc" "$ROOT/boot"
touch "$ROOT/etc/NIXOS"
mount -t vfat -o rw,umask=0077 "$esp_device" "$ROOT/boot"
NIXOS_INSTALL_BOOTLOADER=1 chroot "$ROOT" "$initial_system/bin/switch-to-configuration" boot
test -s "$ROOT/boot/EFI/BOOT/BOOTAA64.EFI" || fail 'Missing EFI fallback loader'
grep -Fq "init=$initial_system/init" "$ROOT"/boot/loader/entries/*.conf || fail 'Selected EFI generation is missing'
selected=$(chroot "$ROOT" "$initial_system/sw/bin/readlink" -f /nix/var/nix/profiles/system)
test "$selected" = "$initial_system" || fail 'Initial profile selection mismatch'
# Firmware is the last write. Recheck the adapter and whole-partition hash;
# no backup/readback image is retained, and no A/recovery/super partition is written.
checked_devices
test "$(identities)" = "$before" || fail 'Partition identities changed'
test "$(sha256sum "$boot_device" | cut -d ' ' -f 1)" = "$boot_before" || fail 'Boot changed during installation'
tail_bytes=$((boot_bytes - image_bytes))
expected_boot=$({ cat "$image_file"; head -c "$tail_bytes" /dev/zero; } | sha256sum | cut -d ' ' -f 1)
if test "$boot_before" != "$expected_boot"; then
  writing_boot=true
  chroot "$ROOT" "$initial_system/sw/bin/dd" if="$image" of="$boot_device" bs=4M conv=notrunc,fsync status=none
  chroot "$ROOT" "$initial_system/sw/bin/dd" if=/dev/zero of="$boot_device" bs=1M \
    oflag=seek_bytes iflag=count_bytes seek="$image_bytes" count="$tail_bytes" conv=notrunc,fsync status=none
fi
test "$(sha256sum "$boot_device" | cut -d ' ' -f 1)" = "$expected_boot" || fail 'Firmware readback mismatch'
writing_boot=false
sync
rm "$ROOT/var/lib/mobile-efi-preparation/pending"
sync
cleanup
printf 'installed %s %s\n' "$manifest_hash" "$initial_system" > "$RESULT"
trap - EXIT HUP INT TERM
echo 'Initial closure, EFI generation and firmware verified. Reboot explicitly after inspection.'
