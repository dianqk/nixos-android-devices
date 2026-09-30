#!/bin/sh
# Installed only inside the isolated recovery chroot, before the ordinary PATH.
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
test "${1:-}" = boot || fail 'Recovery nixos-rebuild only supports boot (including boot --rollback)'
# Remote deployment and alternate profile roots defeat this offline target contract.
for arg in "$@"; do
  case "$arg" in --target-host|--target-host=*|--profile-name|--profile-name=*|-p|--sudo|--use-remote-sudo)
    fail 'Offline rebuild must use the mounted local system profile' ;;
  esac
done
for point in / /boot; do
  case ",$(findmnt -rn -M "$point" -o OPTIONS)," in *,rw,*) ;; *) fail 'Target is read-only; use mount-target --rw' ;; esac
done
test ! -e /var/lib/mobile-offline-deploy/pending || fail 'Complete the existing offline deployment first'
test ! -e /var/lib/mobile-efi-preparation/pending || fail 'Complete the initial EFI installation first'
mkdir -p /var/lib/mobile-offline-rebuild
old=$(readlink -f /nix/var/nix/profiles/system)
printf '%s\n' "$old" > /var/lib/mobile-offline-rebuild/pending
sync
# The original program uses the target Nix database and boot installer.
/run/current-system/sw/bin/nixos-rebuild --no-reexec "$@"
new=$(readlink -f /nix/var/nix/profiles/system)
test -f "$new/mobile-efi" || fail 'Rebuilt system is not an EFI system'
test -s /boot/EFI/BOOT/BOOTAA64.EFI || fail 'EFI fallback loader is missing'
grep -Fq "init=$new/init" /boot/loader/entries/*.conf || fail 'Selected generation is absent from the boot menu'
sync
rm /var/lib/mobile-offline-rebuild/pending
sync
printf 'Offline boot update complete: %s\n' "$new"
