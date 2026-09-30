# shellcheck shell=sh
# Sourced by Sheng recovery tools. Never mutate Android slot metadata.
sheng_check_boot_slot() {
  slot_seen=no
  vbmeta_uuid=
  for arg in $1; do
    case "$arg" in
      androidboot.slot_suffix=_b|boot.slot_suffix=_b) slot_seen=yes ;;
      androidboot.slot_suffix=*|boot.slot_suffix=*) fail 'Run the Sheng recovery from slot B' ;;
      androidboot.vbmeta.device=PARTUUID=*)
        value=${arg#androidboot.vbmeta.device=PARTUUID=}
        test -n "$value" || fail 'Empty vbmeta UUID'
        test -z "$vbmeta_uuid" || test "$vbmeta_uuid" = "$value" || fail 'Conflicting vbmeta identities'
        vbmeta_uuid=$value
        ;;
      androidboot.vbmeta.device=*) fail 'Unsupported bootloader vbmeta identity' ;;
    esac
  done
  # Reject A/unknown/conflicting bootconfig values before accepting any B hint.
  values=$(printf '%s\n' "$2" | sed -nE 's/^[[:space:]]*(androidboot|boot)\.slot_suffix[[:space:]]*=[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\2/p')
  for value in $values; do
    test "$value" = _b || fail 'Run the Sheng recovery from slot B'
    slot_seen=yes
  done
  if test -n "$vbmeta_uuid"; then
    printf '%s\n' "$vbmeta_uuid" | grep -Eq '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' || fail 'Invalid vbmeta UUID'
    node=$(readlink -f /dev/disk/by-partlabel/vbmeta_b) || fail 'Missing vbmeta_b'
    test -b "$node" || fail 'vbmeta_b is not a block device'
    test "$(blkid -p -s PART_ENTRY_NAME -o value "$node")" = vbmeta_b || fail 'vbmeta_b GPT label mismatch'
    uuid=$(blkid -p -s PART_ENTRY_UUID -o value "$node" | tr A-F a-f)
    test "$(printf '%s' "$vbmeta_uuid" | tr A-F a-f)" = "$uuid" || fail 'Bootloader did not select vbmeta_b'
    case "$(readlink -f "/sys/class/block/$(basename "$node")")" in
      */1d84000.ufshc/*) ;;
      *) fail 'vbmeta_b is not on the Sheng UFS controller' ;;
    esac
    slot_seen=yes
  fi
  test "$slot_seen" = yes || fail 'Cannot verify active slot B'
}
sheng_slot_gate() {
  bootconfig=
  if test -r /proc/bootconfig; then bootconfig=$(cat /proc/bootconfig); fi
  sheng_check_boot_slot "$(cat /proc/cmdline)" "$bootconfig"
}
