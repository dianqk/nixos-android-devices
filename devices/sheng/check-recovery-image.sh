#!/bin/sh
# Validate the repository's full-size Android v0 + unsigned AVB recovery format.
# No device access or writes. Values outside this format are deliberately refused.
set -efu
fail() { echo "ERROR: $*" >&2; exit 1; }
test "$#" = 1 || fail 'Usage: sheng-check-recovery-image IMAGE'
image=$1
test -f "$image" && test ! -L "$image" || fail 'Expected a regular image file'
test "$(stat -c %s "$image")" = 104857600 || fail 'Recovery must occupy the complete 100 MiB partition'
hex() { od -An -tx1 -j "$1" -N "$2" "$image" | tr -d ' \n'; }
be32() { echo "$((0x$(hex "$1" 4)))"; }
be64() {
  test "$(hex "$1" 4)" = 00000000 || fail 'Oversized AVB field'
  be32 "$(($1 + 4))"
}
le32() { od -An -tu4 -j "$1" -N 4 "$image" | tr -d ' \n'; }
# Sheng and the supported build hosts are little-endian.
test "$(hex 0 8)" = 414e44524f494421 && test "$(le32 36)" = 4096 &&
  test "$(le32 40)" = 0 && test "$(le32 24)" = 0 || fail 'Unsupported Android header'
ksize=$(le32 8); rsize=$(le32 16)
test "$ksize" -gt 40 && test "$ksize" -lt 67108864 && test "$rsize" -gt 0 || fail 'Invalid boot payload sizes'
cstring() {
  dd if="$image" bs=1 skip="$1" count="$2" status=none | od -An -v -tu1 | awk '
    { for (i=1; i<=NF; i++) { if ($i==0) exit; printf "%c", $i; } }'
}
cmdline="$(cstring 64 512)$(cstring 608 1024)"
recovery_unit=no
for argument in $cmdline; do
  case "$argument" in
    rd.systemd.unit=mobile-recovery.target) recovery_unit=yes ;;
    rd.systemd.unit=*) fail 'Conflicting initrd target' ;;
  esac
done
test "$recovery_unit" = yes || fail 'Not a RAM recovery command line'
# Locate an appended FDT whose total size ends exactly at the kernel boundary.
# Inspect its root compatible property, not arbitrary strings in the image.
kend=$((4096 + ksize)); matched=no
# BusyBox grep lacks byte offsets. Scan at most the final 1 MiB of the kernel
# with portable od/awk; current Sheng DTBs are well below this limit.
scan=$(((kend > 1048576 ? kend - 1048576 : 4096) / 4096))
for relative in $(dd if="$image" bs=4096 skip="$scan" count=257 status=none | od -An -v -tu1 | awk '
  { for (i=1; i<=NF; i++) {
      if (a==208 && b==13 && c==254 && $i==237) print n-3;
      a=b; b=c; c=$i; n++;
  } }'); do
  dt=$((scan * 4096 + relative))
  test "$dt" -ge 4096 && test "$((dt + 40))" -le "$kend" || continue
  total=$(be32 "$((dt + 4))")
  test "$((dt + total))" = "$kend" || continue
  test "$(be32 "$((dt + 20))")" = 17 || continue
  structure=$(be32 "$((dt + 8))"); strings=$(be32 "$((dt + 12))")
  stringsize=$(be32 "$((dt + 32))"); structuresize=$(be32 "$((dt + 36))")
  test "$structure" -ge 40 && test "$strings" -ge 40 &&
    test "$((strings + stringsize))" -le "$total" &&
    test "$((structure + structuresize))" -le "$total" || fail 'Invalid FDT bounds'
  pos=$((dt + structure)); end=$((pos + structuresize))
  test "$(hex "$pos" 8)" = 0000000100000000 || fail 'Invalid FDT root'
  pos=$((pos + 8))
  while test "$((pos + 12))" -le "$end"; do
    token=$(be32 "$pos")
    if test "$token" = 4; then pos=$((pos + 4)); continue; fi
    test "$token" = 3 || break
    length=$(be32 "$((pos + 4))"); name=$(be32 "$((pos + 8))")
    test "$name" -lt "$stringsize" && test "$((pos + 12 + length))" -le "$end" || fail 'Invalid FDT property bounds'
    if test "$((name + 11))" -le "$stringsize" && test "$(hex "$((dt + strings + name))" 11)" = 636f6d70617469626c6500; then
      dd if="$image" bs=1 skip="$((pos + 12))" count="$length" status=none | tr '\000' '\n' | grep -qx xiaomi,sheng || fail 'Image belongs to another device'
      matched=yes
      break
    fi
    pos=$((pos + 12 + (length + 3) / 4 * 4))
  done
done
test "$matched" = yes || fail 'No appended Sheng device tree'
footer=$((104857600 - 64))
test "$(hex "$footer" 12)" = 415642660000000100000000 || fail 'Invalid AVB footer'
original=$(be64 "$((footer + 12))"); vbmeta=$(be64 "$((footer + 20))"); vsize=$(be64 "$((footer + 28))")
payload=$((4096 + (ksize + 4095) / 4096 * 4096 + (rsize + 4095) / 4096 * 4096))
test "$original" = "$payload" && test "$vbmeta" = "$original" && test "$vsize" = 448 &&
  test "$((vbmeta + vsize))" -lt "$footer" || fail 'Invalid AVB layout'
test "$(hex "$vbmeta" 4)" = 41564230 && test "$(be64 "$((vbmeta + 12))")" = 0 &&
  test "$(be64 "$((vbmeta + 20))")" = 192 && test "$(be32 "$((vbmeta + 28))")" = 0 &&
  test "$(be64 "$((vbmeta + 96))")" = 0 && test "$(be64 "$((vbmeta + 104))")" = 176 || fail 'Unsupported AVB metadata'
desc=$((vbmeta + 256))
test "$(be64 "$desc")" = 2 && test "$(be64 "$((desc + 8))")" = 160 &&
  test "$(be64 "$((desc + 16))")" = "$original" &&
  test "$(hex "$((desc + 24))" 32)" = 7368613235360000000000000000000000000000000000000000000000000000 &&
  test "$(be32 "$((desc + 56))")" = 8 && test "$(be32 "$((desc + 60))")" = 0 &&
  test "$(be32 "$((desc + 64))")" = 32 && test "$(be32 "$((desc + 68))")" = 0 &&
  test "$(hex "$((desc + 132))" 8)" = 7265636f76657279 || fail 'Not an unsalted recovery hash descriptor'
actual=$(head -c "$original" "$image" | sha256sum | cut -d ' ' -f1)
test "$actual" = "$(hex "$((desc + 140))" 32)" || fail 'AVB recovery payload digest mismatch'
echo 'CHECK PASSED: Sheng DT, recovery command line, full 100 MiB image and AVB payload hash'
