# Battery care: hold the battery in a charge window while plugged in, through
# the kernel's standard power_supply charge_control_start/end_threshold, with
# a one-off full charge on request.
#
#   charge-window run       apply the window, serve full-charge requests
#   charge-window restore   window off (start 0, end 100)
#
# Environment:
#   CHARGE_WINDOW_BATTERY   power_supply directory of the battery
#   CHARGE_WINDOW_START     resume charging below this capacity (%)
#   CHARGE_WINDOW_END       stop charging at this capacity (%)
#   CHARGE_WINDOW_RUNDIR    request/state directory (default /run/charge-window)
#
# A full charge is requested by creating $RUNDIR/full-charge. The window is
# then lifted (end 100) until the charger ends the charge (the battery reports
# Full) or is unplugged (Discharging), and the request is removed.
# $RUNDIR/state holds "window START END", "full-charge" or "off".
set -eu

battery=${CHARGE_WINDOW_BATTERY:?}
start=${CHARGE_WINDOW_START:?}
end=${CHARGE_WINDOW_END:?}
rundir=${CHARGE_WINDOW_RUNDIR:-/run/charge-window}
interval=10

log() { echo "charge-window: $*" >&2; }

state() {
  printf '%s\n' "$*" >"$rundir/state.new"
  chmod 0644 "$rundir/state.new"
  mv -f "$rundir/state.new" "$rundir/state"
}

# End first: the kernel requires start < end and lowers start with end.
set_window() {
  if [ "$2" -gt "$(cat "$battery/charge_control_start_threshold")" ]; then
    echo "$2" >"$battery/charge_control_end_threshold"
    echo "$1" >"$battery/charge_control_start_threshold"
  else
    echo "$1" >"$battery/charge_control_start_threshold"
    echo "$2" >"$battery/charge_control_end_threshold"
  fi
}

case "${1:-}" in
restore)
  set_window 0 100
  [ -d "$rundir" ] && state off
  exit 0
  ;;
run) ;;
*)
  echo "usage: charge-window run|restore" >&2
  exit 2
  ;;
esac

[ "$start" -lt "$end" ] || { log "start $start must be below end $end"; exit 1; }
mode=window
set_window "$start" "$end"
state window "$start" "$end"
log "window $start-$end % on $battery"
while :; do
  status=$(cat "$battery/status" 2>/dev/null || echo Unknown)
  capacity=$(cat "$battery/capacity" 2>/dev/null || echo 0)
  if [ "$mode" = window ] && [ -e "$rundir/full-charge" ]; then
    mode=full
    set_window 0 100
    state full-charge
    log "one-off full charge requested at $capacity %"
  elif [ "$mode" = full ] && { [ "$status" = Discharging ] || [ "$status" = Full ]; }; then
    mode=window
    rm -f "$rundir/full-charge"
    set_window "$start" "$end"
    state window "$start" "$end"
    log "full charge ended ($status, $capacity %); window $start-$end %"
  elif [ "$mode" = window ]; then
    # Re-assert after a driver reload.
    if [ "$(cat "$battery/charge_control_end_threshold")" != "$end" ] ||
      [ "$(cat "$battery/charge_control_start_threshold")" != "$start" ]; then
      set_window "$start" "$end"
    fi
  fi
  sleep "$interval"
done
