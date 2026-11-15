# SPDX-License-Identifier: MIT
# Inputs are a battery-class directory and care thresholds in microvolts.
battery=$1
ceiling=$2
restart=$3
once=${4:-loop}
held_since=

care_decide() {
  now=$1
  previous=$2
  voltage=$3
  hold=1
  if [ "$previous" = 1 ]; then
    held_since=${held_since:-$now}
  else
    held_since=
  fi
  case "$voltage" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$voltage" -ge "$ceiling" ]; then
        hold=1
      elif [ "$voltage" -le "$restart" ]; then
        if [ -z "$held_since" ] || [ "$((now - held_since))" -ge 30 ]; then
          hold=0
        fi
      elif [ "$previous" = 0 ]; then
        hold=0
      fi
      ;;
  esac
  if [ "$hold" = 1 ]; then
    held_since=${held_since:-$now}
  else
    held_since=
  fi
}

while :; do
  if [ -e "$battery/wireless_care_hold" ]; then
    # Uptime is monotonic across suspend. Inherited holds get a fresh 30s minimum.
    read -r uptime _ < /proc/uptime
    now=${uptime%%.*}
    previous=$(cat "$battery/wireless_care_hold" 2>/dev/null) || previous=1
    voltage=$(cat "$battery/wireless_voltage_max" 2>/dev/null) || voltage=
    care_decide "$now" "$previous" "$voltage"
    if [ "$hold" != "$previous" ]; then
      printf '%s\n' "$hold" > "$battery/wireless_care_hold"
    fi
  fi
  [ "$once" != once ] || break
  sleep 1
done
