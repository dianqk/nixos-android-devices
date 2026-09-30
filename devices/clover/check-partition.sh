clover_check_partition() {
  role=$1
  require_fs=${2:-no}
  printf '%s\n' "$CLOVER_PARTUUID" | grep -Eiq \
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' ||
    fail "$role has an invalid GPT UUID"
  case "$CLOVER_PART_BYTES" in ''|*[!0-9]*) fail "$role has invalid geometry" ;; esac
  for value in "$CLOVER_PART_NUMBER" "$CLOVER_PART_OFFSET"; do
    case "$value" in *[!0-9]*) fail "$role has invalid geometry" ;; esac
  done
  CLOVER_TARGET=$(readlink -f "/dev/disk/by-partuuid/$CLOVER_PARTUUID") || fail "$role is absent"
  test -b "$CLOVER_TARGET" || fail "$role target is not a block device"
  test "$(blkid -p -s PART_ENTRY_UUID -o value "$CLOVER_TARGET" | tr A-F a-f)" = \
    "$(printf '%s' "$CLOVER_PARTUUID" | tr A-F a-f)" || fail "$role GPT UUID mismatch"
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$CLOVER_TARGET")" = "$role" ||
    fail "$role GPT label mismatch"
  test -z "$CLOVER_PART_NUMBER" || test "$(blkid -p -s PART_ENTRY_NUMBER -o value "$CLOVER_TARGET")" = "$CLOVER_PART_NUMBER" ||
    fail "$role GPT number mismatch"
  test -z "$CLOVER_PART_OFFSET" || test "$(blkid -p -s PART_ENTRY_OFFSET -o value "$CLOVER_TARGET")" = "$CLOVER_PART_OFFSET" ||
    fail "$role GPT offset mismatch"
  test "$(blockdev --getsize64 "$CLOVER_TARGET")" = "$CLOVER_PART_BYTES" ||
    fail "$role size mismatch"
  case "$(readlink -f "/sys/class/block/$(basename "$CLOVER_TARGET")")" in
    */c0c4000.sdhci/*) ;;
    *) fail "$role is not on Clover's main eMMC controller" ;;
  esac
  parent=$(basename "$(readlink -f "/sys/class/block/$(basename "$CLOVER_TARGET")/..")")
  test "$(cat "/sys/class/block/$parent/removable")" = 0 || fail "$role parent is removable"
  if test "$require_fs" = yes; then
    if test -n "${CLOVER_ROOT_UUID:-}"; then
      test "$(blkid -p -s UUID -o value "$CLOVER_TARGET" | tr A-F a-f)" = \
        "$(printf '%s' "$CLOVER_ROOT_UUID" | tr A-F a-f)" || fail "$role root UUID mismatch"
    fi
    test "$(blkid -p -s TYPE -o value "$CLOVER_TARGET")" = ext4 || fail "$role is not ext4"
    test "$(blkid -p -s LABEL -o value "$CLOVER_TARGET")" = "$CLOVER_ROOT_LABEL" ||
      fail "$role filesystem label mismatch"
  fi
}
