#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
MODDIR=${0%/*}
printf '%s\n' 'Action is read-only. Open this module WebUI and explicitly choose a target to switch/reboot.'
exec "$MODDIR/bin/boot-choice" status
