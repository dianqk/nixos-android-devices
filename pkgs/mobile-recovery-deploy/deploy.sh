#!/bin/sh
# Shared recovery deployment; device scripts provide identity/slot/root checks.
set -eu
ROOT=/recovery
fail() { echo "ERROR: $*" >&2; exit 1; }
device_name=$(cat /etc/mobile-ram-recovery)
MOBILE_RECOVERY_LIBRARY_ONLY=1
export MOBILE_RECOVERY_LIBRARY_ONLY
case "$device_name" in
  polaris)
    . /bin/recovery
    recovery_gate() { reboot_gate; }
    mount_root() { mount_userdata_plain "$1"; }
    ;;
  clover|asphalt|sheng) . "/bin/$device_name-storage" ;;
  *) fail 'Unsupported recovery device' ;;
esac

esp_partition() {
  case "$device_name" in
    polaris) polaris_partition_role esp yes; esp_target=$POLARIS_TARGET ;;
    clover)
      clover_partition_role system no; esp_target=$CLOVER_TARGET
      ;;
    asphalt|sheng)
      check_ufs_partition linux-boot; esp_target=$partition
      test "/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$esp_target")/..")")" = "$linux_disk" || fail 'ESP/root disks differ'
      test "$(blkid -p -s PART_ENTRY_TYPE -o value "$esp_target")" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b || fail 'ESP GPT type mismatch'
      test "${MOBILE_ESP_BYTES:-1073741824}" = 0 ||
        test "$(blockdev --getsize64 "$esp_target")" = "${MOBILE_ESP_BYTES:-1073741824}" || fail 'ESP size differs from configuration'
      ;;
  esac
  test "$(blkid -p -s TYPE -o value "$esp_target")" = vfat || fail 'Prepare the FAT boot partition first'
}

cleanup() {
  cd /
  umount -R "$ROOT/dev" 2>/dev/null || true
  umount "$ROOT/proc" 2>/dev/null || true
  umount -R "$ROOT/sys" 2>/dev/null || true
  umount -R "$ROOT/run" 2>/dev/null || true
  umount "$ROOT/boot" 2>/dev/null || true
  umount "$ROOT/nix/var/nix" 2>/dev/null || true
  umount "$ROOT" 2>/dev/null || true
}
store_hash() {
  NIX_REMOTE=local chroot "$ROOT" "$trusted_system/sw/bin/nix" --extra-experimental-features nix-command hash path --type sha256 --base32 "$1"
}
validate_input() {
  test -s "$deploy_manifest" && test ! -L "$deploy_manifest" || fail 'Missing deployment manifest'
  case "$device_name" in polaris) validate_deploy_manifest "$deploy_manifest" "$deploy_system" ;; *) validate_manifest "$deploy_manifest" "$deploy_system" ;; esac
  while read -r h p extra; do
    test -z "${extra:-}" || fail 'Malformed manifest'
    printf '%s\n' "$h" | grep -Eq '^sha256:[a-z0-9]{52}$' || fail 'Invalid NAR hash'
    printf '%s\n' "$p" | grep -Eq '^/nix/store/[a-z0-9]{32}-[^/[:space:]]+$' || fail 'Invalid store path'
  done < "$deploy_manifest"
  test "$(cut -d ' ' -f 2 "$deploy_manifest" | sort -u | wc -l)" = "$(wc -l < "$deploy_manifest")" || fail 'Duplicate manifest path'
}
check_pending() {
  test ! -e "$ROOT/var/lib/mobile-offline-rebuild/pending" || fail "Complete the interrupted offline rebuild first"
  test ! -e "$ROOT/var/lib/mobile-efi-preparation/pending" || fail "Install EFI boot files before rebooting"
  test ! -e "$ROOT/var/lib/mobile-offline-deploy/pending" || fail 'Resume the pending recovery deployment first'
}
operation_lock
recovery_gate
trap cleanup EXIT HUP INT TERM
case "${1:-}" in
  deploy-check-boot)
    mount_root ro,noload
    check_pending
    selected=$(selected_system)
    test -f "$ROOT$selected/mobile-efi" || fail 'Selected system does not support EFI boot'
    esp_partition
    mkdir -p "$ROOT/boot"
    mount -t vfat -o ro "$esp_target" "$ROOT/boot"
    test -s "$ROOT/boot/EFI/BOOT/BOOTAA64.EFI" || fail 'Missing EFI fallback loader'
    grep -Fq "init=$selected/init" "$ROOT"/boot/loader/entries/*.conf || fail 'Selected EFI generation is missing'
    exit 0
    ;;
  deploy-query|deploy-offline) ;;
  *) fail 'Unknown deployment action' ;;
esac
deploy_manifest=${2:?Missing manifest}
deploy_system=${3:?Missing system}
validate_input
if test "$1" = deploy-query; then
  test "$#" = 3 || fail 'Usage: recovery deploy-query MANIFEST SYSTEM'
  mount_root ro,noload
  if test -e "$ROOT/var/lib/mobile-offline-deploy/pending"; then
    test "$(cat "$ROOT/var/lib/mobile-offline-deploy/pending")" = "$deploy_system" || fail 'Resume the pending deployment first'
  fi
  mount -t proc proc "$ROOT/proc"
  trusted_system=$(selected_system)
  query_state=$(mktemp -d /run/mobile-deploy-query.XXXXXX)
  mkdir "$query_state/temproots"
  cp -a "$ROOT/nix/var/nix/db" "$query_state/db"
  mount --bind "$query_state" "$ROOT/nix/var/nix"
  # shellcheck disable=SC2046
  NIX_CONFIG='extra-experimental-features = read-only-local-store' NIX_REMOTE='local?read-only=true' \
    chroot "$ROOT" "$trusted_system/sw/bin/nix-store" --check-validity --print-invalid $(cut -d ' ' -f 2 "$deploy_manifest")
  cleanup
  rm -rf "$query_state"
  trap - EXIT HUP INT TERM
  exit 0
fi
test "$#" = 5 && test "$5" = --confirm || fail 'Usage: recovery deploy-offline MANIFEST SYSTEM MISSING_COUNT --confirm'
missing_count=$4
case "$missing_count" in ''|*[!0-9]*) fail 'Invalid missing count' ;; esac
manifest_hash=$(sha256sum "$deploy_manifest" | cut -d ' ' -f 1)
result=/run/mobile-offline-deploy.result
printf 'running %s %s\n' "$manifest_hash" "$deploy_system" > "$result"
failed() {
  rc=$?
  trap - EXIT HUP INT TERM
  cleanup
  printf 'failed %s %s %s\n' "$manifest_hash" "$deploy_system" "$rc" > "$result"
}
trap failed EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mount_root rw
test ! -e "$ROOT/var/lib/mobile-offline-rebuild/pending" || fail 'Complete the interrupted offline rebuild first'
test ! -e "$ROOT/var/lib/mobile-efi-preparation/pending" || fail 'Complete the initial EFI installation first'
if test -e "$ROOT/var/lib/mobile-offline-deploy/pending"; then
  test "$(cat "$ROOT/var/lib/mobile-offline-deploy/pending")" = "$deploy_system" || fail 'Resume the pending deployment first'
fi
mkdir -p "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/run"
mount --bind /dev "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount --bind /sys "$ROOT/sys"
mount --bind /run "$ROOT/run"
trusted_system=$(selected_system)
nix_store=$trusted_system/sw/bin/nix-store
nix_env=$trusted_system/sw/bin/nix-env
chroot "$ROOT" "$nix_store" --version >/dev/null
if test "$missing_count" -gt 0; then
  NIX_REMOTE=local chroot "$ROOT" "$nix_store" --import > /run/mobile-offline-imported
  test "$(wc -l < /run/mobile-offline-imported)" = "$missing_count" || fail 'Imported path count mismatch'
else
  test ! -s /dev/stdin || fail 'Unexpected import data'
fi
# Verify actual bytes, including already registered paths, not just DB hashes.
while read -r expected path; do
  NIX_REMOTE=local chroot "$ROOT" "$nix_store" --check-validity "$path"
  test "sha256:$(store_hash "$path")" = "$expected" || fail "Content hash mismatch: $path"
done < "$deploy_manifest"
NIX_REMOTE=local chroot "$ROOT" "$nix_store" --query --requisites "$deploy_system" | sort > /run/mobile-closure.actual
cut -d ' ' -f 2 "$deploy_manifest" | sort > /run/mobile-closure.expected
cmp -s /run/mobile-closure.actual /run/mobile-closure.expected || fail 'Closure differs from manifest'
for candidate in "$trusted_system" "$deploy_system"; do
  test -f "$ROOT$candidate/mobile-efi" || fail 'Deploy requires EFI-capable systems'
done
# The root partition must stay the one validated by the device adapter.
for candidate in "$trusted_system" "$deploy_system"; do
  # shellcheck disable=SC2016
  chroot "$ROOT" "$trusted_system/sw/bin/awk" '$1 !~ /^#/ && $2 == "/" { count++; device=$1; type=$3 } END { if (count == 1) print device, type; else exit 1 }' "$candidate/etc/fstab" > /run/mobile-root-entry.next
  if test "$candidate" = "$trusted_system"; then cp /run/mobile-root-entry.next /run/mobile-root-entry.old; fi
  cmp -s /run/mobile-root-entry.old /run/mobile-root-entry.next || fail 'Deployment changes the validated root partition'
done
if test "$device_name" = polaris && test "${POLARIS_REQUIRE_RADIO_IDENTITY:-0}" = 1; then
  for radio in wifi bluetooth; do
    grep -Eq '^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$' "$ROOT/var/lib/polaris-radio-identity/$radio-address" || fail 'Missing radio identity'
  done
  (cd "$ROOT/var/lib/polaris-radio-snapshot" && sha256sum -c SHA256SUMS >/dev/null) || fail 'Radio snapshot mismatch'
fi
esp_partition
mkdir -p "$ROOT/boot"
mount -t vfat -o rw,umask=0077 "$esp_target" "$ROOT/boot"
mkdir -p "$ROOT/var/lib/mobile-offline-deploy"
printf '%s\n' "$deploy_system" > "$ROOT/var/lib/mobile-offline-deploy/pending"
sync
NIX_REMOTE=local chroot "$ROOT" "$nix_env" -p /nix/var/nix/profiles/system --set "$deploy_system"
sync
NIXOS_INSTALL_BOOTLOADER=1 chroot "$ROOT" "$deploy_system/bin/switch-to-configuration" boot
test -s "$ROOT/boot/EFI/BOOT/BOOTAA64.EFI" || fail 'Missing EFI fallback loader'
grep -Fq "init=$deploy_system/init" "$ROOT"/boot/loader/entries/*.conf || fail 'Selected EFI generation is missing'
test "$(selected_system)" = "$deploy_system" || fail 'Profile selection mismatch'
rm "$ROOT/var/lib/mobile-offline-deploy/pending"
sync
cleanup
! mountpoint -q "$ROOT" || fail 'Root remained mounted'
printf 'installed %s %s\n' "$manifest_hash" "$deploy_system" > "$result"
trap - EXIT HUP INT TERM
echo 'System and EFI generation verified; firmware unchanged. Reboot explicitly.'
