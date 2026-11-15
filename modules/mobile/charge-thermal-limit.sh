# Charge current cap from temperature, a stepped form of the battery stage of
# Android thermal daemons such as Xiaomi's mi_thermald (thermal_fcc_override).
#
#   charge-thermal-limit run              poll and apply; restore the default on stop
#   charge-thermal-limit restore          write the default cap
#   charge-thermal-limit evaluate LEVEL   one step from LEVEL (-1: no step): write
#                                         the cap and print the next level
#
# Environment (all required except INTERVAL and REFRESH):
#   CHARGE_THERMAL_CURRENT_FILE  writable cap in uA (power_supply constant_charge_current)
#   CHARGE_THERMAL_SENSORS       "path:multiplier ...": value * multiplier = millidegree C;
#                                the highest readable sensor controls the cap
#   CHARGE_THERMAL_STEPS         "trip:clear:current ...", trips ascending, millidegree C
#                                and uA; a step applies from its trip until the
#                                temperature falls below its clear temperature
#   CHARGE_THERMAL_DEFAULT       uA below the first step and after stopping
#   CHARGE_THERMAL_INTERVAL      seconds between polls (default 5)
#   CHARGE_THERMAL_REFRESH       polls between rewrites of an unchanged cap (default 12)
# Without a readable sensor the most restrictive step applies.
set -eu

current_file=${CHARGE_THERMAL_CURRENT_FILE:?}
default_current=${CHARGE_THERMAL_DEFAULT:?}
interval=${CHARGE_THERMAL_INTERVAL:-5}
refresh=${CHARGE_THERMAL_REFRESH:-12}
read -r -a sensors <<<"${CHARGE_THERMAL_SENSORS:?}"
read -r -a steps <<<"${CHARGE_THERMAL_STEPS:?}"

log() { echo "charge-thermal-limit: $*" >&2; }

trips=() clears=() currents=()
for step in "${steps[@]}"; do
  IFS=: read -r trip clear current <<<"$step"
  trips+=("$trip") clears+=("$clear") currents+=("$current")
done
count=${#trips[@]}

# Highest sensor reading in millidegree C, or nothing.
temperature() {
  local sensor path multiplier value best=
  for sensor in "${sensors[@]}"; do
    path=${sensor%:*} multiplier=${sensor##*:}
    value=
    { read -r value <"$path"; } 2>/dev/null || continue
    [[ $value =~ ^-?[0-9]+$ ]] || continue
    value=$((value * multiplier))
    if [[ -z $best ]] || ((value > best)); then best=$value; fi
  done
  echo "$best"
}

next_level() {
  local level=$1 temp=$2
  if [[ -z $temp ]]; then
    echo $((count - 1))
    return
  fi
  while ((level + 1 < count)) && ((temp >= trips[level + 1])); do level=$((level + 1)); done
  while ((level >= 0)) && ((temp < clears[level])); do level=$((level - 1)); done
  echo "$level"
}

cap() {
  if (($1 < 0)); then echo "$default_current"; else echo "${currents[$1]}"; fi
}

write_cap() {
  if ! printf '%s\n' "$1" 2>/dev/null >"$current_file"; then
    log "cannot write $1 to $current_file"
    return 1
  fi
}

case ${1:-} in
  restore)
    write_cap "$default_current"
    ;;
  evaluate)
    level=$(next_level "${2:?level}" "$(temperature)")
    write_cap "$(cap "$level")"
    echo "$level"
    ;;
  run)
    trap 'write_cap "$default_current" || true; exit 0' TERM INT
    level=-1 last='' polls=0
    while :; do
      temp=$(temperature)
      level=$(next_level "$level" "$temp")
      value=$(cap "$level")
      if [[ $value != "$last" ]] || ((polls >= refresh)); then
        if [[ $value != "$last" ]]; then
          log "temperature ${temp:-unavailable} mC: cap $value uA (step $level)"
        fi
        if write_cap "$value"; then last=$value; else last=''; fi
        polls=0
      fi
      polls=$((polls + 1))
      sleep "$interval" &
      wait $! || true
    done
    ;;
  *)
    echo "Usage: charge-thermal-limit run|restore|evaluate LEVEL" >&2
    exit 2
    ;;
esac
