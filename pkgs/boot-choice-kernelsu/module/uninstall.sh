#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
MODDIR=${0%/*}
"$MODDIR/bin/boot-choice" restore
status=$?
if [ "$status" -ne 0 ]; then
  echo 'Native restore FAILED; KernelSU may still delete this module. Do not assume boot/ESP state was restored.' >&2
  echo 'Keep the public ZIP/CLI externally. Re-extract it into a root-protected directory; run bin/boot-choice recover and inspect its result before retrying restore. ESP undo survives module deletion.' >&2
fi
exit "$status"
