#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Sourced by the standard KernelSU installer after default ZIP extraction.
[ "${KSU:-}" = true ] || abort 'Install this ZIP through KernelSU Manager, not recovery or Magisk.'
[ -n "${MODPATH:-}" ] || abort 'KernelSU did not provide MODPATH.'
set_perm_recursive "$MODPATH" 0 0 0755 0444 || abort 'KernelSU permission/SELinux setup failed.'
set_perm "$MODPATH/bin/boot-choice" 0 0 0755 || abort 'KernelSU permission/SELinux setup failed.'
set_perm "$MODPATH/system/bin/boot-choice" 0 0 0755 || abort 'KernelSU permission/SELinux setup failed.'
set_perm "$MODPATH/action.sh" 0 0 0755 || abort 'KernelSU permission/SELinux setup failed.'
set_perm "$MODPATH/uninstall.sh" 0 0 0755 || abort 'KernelSU permission/SELinux setup failed.'
# KernelSU legitimately stages below modules_update mode0777. Do not change
# that shared directory or weaken native admission. Copy only template assets
# into a unique private sibling below the root-protected /data/adb boundary.
# This script is SOURCED: leave KernelSU's EXIT trap entirely untouched.
BOOT_CHOICE_STAGE=$(mktemp -d /data/adb/boot-choice-template.XXXXXX) || abort 'Cannot create private template directory; native operation not started.'
if ! cp -R "$MODPATH/template/." "$BOOT_CHOICE_STAGE/"; then
  rm -rf -- "$BOOT_CHOICE_STAGE" || ui_print '! Private template cleanup failed.'
  abort 'Cannot copy template assets; native operation not started.'
fi
if ! set_perm_recursive "$BOOT_CHOICE_STAGE" 0 0 0700 0400; then
  rm -rf -- "$BOOT_CHOICE_STAGE" || ui_print '! Private template cleanup failed.'
  abort 'Cannot protect private template assets; native operation not started.'
fi
ui_print '- Native owner: install or validated owned update; no reboot here.'
if "$MODPATH/bin/boot-choice" install "$BOOT_CHOICE_STAGE"; then
  if ! rm -rf -- "$BOOT_CHOICE_STAGE"; then
    abort 'Native operation VERIFIED, but private template cleanup failed. Do not assume rollback; retain the native output.'
  fi
  ui_print '- Native image and owned ESP files verified. Keep recovery available.'
else
  rm -rf -- "$BOOT_CHOICE_STAGE" || ui_print '! Private template cleanup failed.'
  abort 'Native operation failed: retain its output. Re-extract this ZIP and run its CLI recover before retrying; installation failure does not prove boot state was rolled back.'
fi
