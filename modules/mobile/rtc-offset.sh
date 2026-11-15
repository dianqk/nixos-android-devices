# Userspace offset for a hardware RTC that Linux cannot set (as Android's
# time_daemon does). The RTC keeps counting while the phone is off; the saved
# offset turns its count back into wall-clock time.
#
#   rtc-offset restore <rtc>   set the clock to RTC + saved offset (never backwards)
#   rtc-offset save <rtc>      save wall clock - RTC when the clock is trustworthy
#
# State: "<rtc seconds at save> <offset seconds>" in $RTC_OFFSET_STATE_DIR/offset.
# A restore creates $RTC_OFFSET_RUN_DIR/restored. Paths and commands can be
# replaced through the environment for host tests.
set -eu

sysfs=${RTC_OFFSET_SYSFS:-/sys/class/rtc}
state_dir=${RTC_OFFSET_STATE_DIR:-/var/lib/rtc-offset}
run_dir=${RTC_OFFSET_RUN_DIR:-/run/rtc-offset}
sync_file=${RTC_OFFSET_SYNC_FILE:-/run/systemd/timesync/synchronized}
min_epoch=${RTC_OFFSET_MIN_EPOCH:-0}
rtc_wait=${RTC_OFFSET_RTC_WAIT:-5}
state=$state_dir/offset
marker=$run_dir/restored

log() { echo "rtc-offset: $*" >&2; }

now() {
  if [ -n "${RTC_OFFSET_NOW_CMD:-}" ]; then "$RTC_OFFSET_NOW_CMD"; else date +%s; fi
}

set_clock() {
  if [ -n "${RTC_OFFSET_SET_CLOCK_CMD:-}" ]; then
    "$RTC_OFFSET_SET_CLOCK_CMD" "$1"
  else
    date -u -s "@$1" >/dev/null
  fi
}

# NTP synchronisation: systemd-timesyncd's flag file, or the kernel's
# synchronised state as reported by timedated.
synced() {
  if [ -n "${RTC_OFFSET_SYNCED_CMD:-}" ]; then
    [ "$("$RTC_OFFSET_SYNCED_CMD")" = yes ]
    return
  fi
  [ -e "$sync_file" ] && return 0
  [ "$(timeout 5 timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]
}

is_int() {
  case $1 in
    '' | *[!0-9-]* | ?*-*) return 1 ;;
  esac
  [ "$1" != - ]
}

read_rtc() {
  local file=$sysfs/$1/since_epoch value i=0
  while [ ! -r "$file" ] && [ "$i" -lt "$rtc_wait" ]; do
    sleep 1
    i=$((i + 1))
  done
  if ! value=$(cat "$file" 2>/dev/null) || ! is_int "$value" || [ "$value" -lt 0 ]; then
    log "cannot read $file"
    return 1
  fi
  echo "$value"
}

# Prints "<saved rtc> <offset>" for a well-formed state file.
read_state() {
  local line saved offset rest
  [ -f "$state" ] || return 1
  IFS= read -r line <"$state" || [ -n "${line:-}" ] || return 2
  read -r saved offset rest <<<"$line"
  if ! is_int "${saved:-}" || ! is_int "${offset:-}" || [ -n "${rest:-}" ] || [ "$saved" -lt 0 ]; then
    return 2
  fi
  echo "$saved $offset"
}

discard() {
  log "discarding saved offset: $1"
  rm -f "$state"
}

restore() {
  local rtc=$1 rtc_now saved offset parsed rc target current
  rtc_now=$(read_rtc "$rtc") || return 0
  rc=0
  parsed=$(read_state) || rc=$?
  case $rc in
    0) ;;
    1)
      log "no saved offset; leaving the clock unchanged"
      return 0
      ;;
    *)
      discard "malformed state file"
      return 0
      ;;
  esac
  read -r saved offset <<<"$parsed"
  if [ "$rtc_now" -lt "$saved" ]; then
    # The RTC counted backwards: it was reset (for example the battery ran out).
    discard "$rtc reads $rtc_now s, below $saved s at save (RTC reset)"
    return 0
  fi
  target=$((rtc_now + offset))
  if [ "$target" -lt "$min_epoch" ]; then
    discard "restored time $target is before the minimum $min_epoch"
    return 0
  fi
  current=$(now)
  mkdir -p "$run_dir"
  if [ "$target" -le "$current" ]; then
    log "clock $current is not behind RTC + offset ($rtc_now + $offset = $target); leaving it"
    echo "kept $current" >"$marker"
    return 0
  fi
  set_clock "$target"
  echo "restored $target" >"$marker"
  log "set the clock from $current to $target ($rtc reads $rtc_now s, offset $offset s)"
}

save() {
  local rtc=$1 rtc_now wall offset parsed saved old tmp
  if synced; then
    :
  elif [ -e "$marker" ]; then
    :
  else
    log "clock neither synchronised nor restored this boot; not saving"
    return 0
  fi
  rtc_now=$(read_rtc "$rtc") || return 0
  wall=$(now)
  if [ "$wall" -lt "$min_epoch" ]; then
    log "clock $wall is before the minimum $min_epoch; not saving"
    return 0
  fi
  offset=$((wall - rtc_now))
  if parsed=$(read_state); then
    read -r saved old <<<"$parsed"
    # An unchanged offset needs no write; the older RTC value stays a valid
    # lower bound for reset detection.
    if [ "$saved" -le "$rtc_now" ] && [ $((offset - old)) -le 1 ] && [ $((old - offset)) -le 1 ]; then
      log "offset $offset s unchanged; not rewriting"
      return 0
    fi
  fi
  mkdir -p "$state_dir"
  tmp=$(mktemp "$state_dir/.offset.XXXXXX")
  echo "$rtc_now $offset" >"$tmp"
  sync "$tmp"
  mv -f "$tmp" "$state"
  log "saved offset $offset s ($rtc reads $rtc_now s, clock $wall)"
}

case "${1:-}" in
  restore | save)
    [ -n "${2:-}" ] || {
      log "usage: $0 restore|save <rtc>"
      exit 2
    }
    "$1" "$2"
    ;;
  *)
    log "usage: $0 restore|save <rtc>"
    exit 2
    ;;
esac
