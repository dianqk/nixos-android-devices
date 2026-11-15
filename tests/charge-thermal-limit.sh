#!/usr/bin/env bash
# Host test of modules/mobile/charge-thermal-limit.sh with fake sysfs files.
# Usage: tests/charge-thermal-limit.sh <charge-thermal-limit.sh>
set -eu

script=$(realpath "$1")
root=$(mktemp -d "${MOBILE_TEST_TMP:-${TMPDIR:-/tmp}}/charge-thermal.XXXXXX")
trap 'rm -rf "$root"' EXIT
failures=0

export CHARGE_THERMAL_CURRENT_FILE=$root/constant_charge_current
export CHARGE_THERMAL_SENSORS="$root/battery:100 $root/zone:1 $root/missing:1"
export CHARGE_THERMAL_STEPS="15000:14000:15600000 33500:33000:10000000 41500:41000:3000000 45000:44500:500000"
export CHARGE_THERMAL_DEFAULT=22000000

check() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    echo "ok: $name"
  else
    echo "FAIL: $name: expected '$expected', got '$actual'" >&2
    failures=$((failures + 1))
  fi
}

# evaluate LEVEL BATTERY_DECIDEGREE ZONE_MILLIDEGREE -> "level cap"
step() {
  rm -f "$root/battery" "$root/zone"
  [[ $2 == - ]] || echo "$2" >"$root/battery"
  [[ $3 == - ]] || echo "$3" >"$root/zone"
  local level
  level=$(bash "$script" evaluate "$1")
  echo "$level $(cat "$CHARGE_THERMAL_CURRENT_FILE")"
}

check "cold uses the default" "-1 22000000" "$(step -1 100 -)"
check "first trip" "0 15600000" "$(step -1 150 -)"
check "jump over several trips" "2 3000000" "$(step -1 420 -)"
check "hysteresis keeps the step above clear" "2 3000000" "$(step 2 412 -)"
check "falls one step below clear" "1 10000000" "$(step 2 409 -)"
check "falls several steps" "-1 22000000" "$(step 2 130 -)"
check "rising inside a hysteresis band does not trip" "0 15600000" "$(step 0 334 -)"
check "highest sensor controls" "3 500000" "$(step 0 300 45100)"
check "battery tenths scale" "1 10000000" "$(step 0 336 20000)"
check "unreadable sensors use the last step" "3 500000" "$(step -1 - -)"
echo garbage >"$root/battery"
rm -f "$root/zone"
check "invalid reading is ignored" "3" "$(bash "$script" evaluate -1)"
bash "$script" restore
check "restore writes the default" 22000000 "$(cat "$CHARGE_THERMAL_CURRENT_FILE")"

# The run loop applies the cap and restores the default on SIGTERM.
echo 420 >"$root/battery"
CHARGE_THERMAL_INTERVAL=1 bash "$script" run 2>"$root/run.log" &
pid=$!
for _ in $(seq 50); do
  [[ $(cat "$CHARGE_THERMAL_CURRENT_FILE") == 3000000 ]] && break
  sleep 0.1
done
check "run applies the cap" 3000000 "$(cat "$CHARGE_THERMAL_CURRENT_FILE")"
kill -TERM "$pid"
wait "$pid" || true
check "run restores on stop" 22000000 "$(cat "$CHARGE_THERMAL_CURRENT_FILE")"

if ((failures)); then
  echo "$failures charge-thermal-limit check(s) failed" >&2
  exit 1
fi
echo "all charge-thermal-limit checks passed"
