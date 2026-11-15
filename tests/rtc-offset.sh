#!/usr/bin/env bash
# Host test of modules/mobile/rtc-offset.sh with a fake sysfs RTC, clock and
# NTP state. Usage: tests/rtc-offset.sh <rtc-offset.sh>
set -eu

script=$(realpath "$1")
root=$(mktemp -d "${MOBILE_TEST_TMP:-${TMPDIR:-/tmp}}/rtc-offset.XXXXXX")
trap 'rm -rf "$root"' EXIT
failures=0
bash_path=$(command -v bash)

setup() {
  rm -rf "$root/case"
  mkdir -p "$root/case/sys/rtc0" "$root/case/bin"
  export RTC_OFFSET_SYSFS=$root/case/sys
  export RTC_OFFSET_STATE_DIR=$root/case/state
  export RTC_OFFSET_RUN_DIR=$root/case/run
  export RTC_OFFSET_SYNC_FILE=$root/case/synchronized
  export RTC_OFFSET_MIN_EPOCH=1767225600
  export RTC_OFFSET_RTC_WAIT=0
  export RTC_OFFSET_NOW_CMD=$root/case/bin/now
  export RTC_OFFSET_SET_CLOCK_CMD=$root/case/bin/set-clock
  export RTC_OFFSET_SYNCED_CMD=$root/case/bin/synced
  cat >"$RTC_OFFSET_NOW_CMD" <<EOF
#!$bash_path
cat "$root/case/clock"
EOF
  cat >"$RTC_OFFSET_SET_CLOCK_CMD" <<EOF
#!$bash_path
echo "\$1" >"$root/case/clock"
echo "\$1" >>"$root/case/set-calls"
EOF
  cat >"$RTC_OFFSET_SYNCED_CMD" <<EOF
#!$bash_path
cat "$root/case/ntp"
EOF
  chmod +x "$root/case/bin/"*
  echo no >"$root/case/ntp"
}

rtc() { echo "$1" >"$root/case/sys/rtc0/since_epoch"; }
clock() { echo "$1" >"$root/case/clock"; }
ntp() { echo "$1" >"$root/case/ntp"; }
state() {
  mkdir -p "$RTC_OFFSET_STATE_DIR"
  echo "$1" >"$RTC_OFFSET_STATE_DIR/offset"
}
# restore and save never fail their units; record any failure.
run() { bash "$script" "$@" 2>>"$root/case/log" || echo "exit $? from $*" >>"$root/errors"; }

check() {
  local name=$1
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name" >&2
    sed 's/^/  log: /' "$root/case/log" >&2 2>/dev/null || true
    failures=$((failures + 1))
  fi
}

equals() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; }
absent() { [ ! -e "$1" ]; }

# First boot: no state, nothing happens.
setup
rtc 800000
clock 1000
run restore rtc0
check "first boot leaves the clock" equals "$root/case/clock" 1000
check "first boot sets no marker" absent "$RTC_OFFSET_RUN_DIR/restored"
check "first boot calls no clock set" absent "$root/case/set-calls"

# Valid restore: RTC advanced 3600 s while off.
setup
state "800000 1780000000"
rtc 803600
clock 1000
run restore rtc0
check "restore sets RTC + offset" equals "$root/case/clock" $((803600 + 1780000000))
check "restore creates the marker" equals "$RTC_OFFSET_RUN_DIR/restored" "restored $((803600 + 1780000000))"
check "restore keeps the state" equals "$RTC_OFFSET_STATE_DIR/offset" "800000 1780000000"

# RTC reset: the count is below the saved value; the state is discarded.
setup
state "800000 1780000000"
rtc 120
clock 1000
run restore rtc0
check "reset leaves the clock" equals "$root/case/clock" 1000
check "reset discards the state" absent "$RTC_OFFSET_STATE_DIR/offset"
check "reset sets no marker" absent "$RTC_OFFSET_RUN_DIR/restored"

# Never backwards: the clock is already later than RTC + offset.
setup
state "800000 1780000000"
rtc 800010
clock 1790000000
run restore rtc0
check "restore never moves the clock back" equals "$root/case/clock" 1790000000
check "a later clock calls no clock set" absent "$root/case/set-calls"
check "a later clock is marked plausible" equals "$RTC_OFFSET_RUN_DIR/restored" "kept 1790000000"

# Below the minimum: an implausible result is discarded.
setup
state "800000 -700000"
rtc 800010
clock 1000
run restore rtc0
check "implausible result leaves the clock" equals "$root/case/clock" 1000
check "implausible result discards the state" absent "$RTC_OFFSET_STATE_DIR/offset"

# Malformed state is discarded.
setup
state "garbage"
rtc 800010
clock 1000
run restore rtc0
check "malformed state leaves the clock" equals "$root/case/clock" 1000
check "malformed state is discarded" absent "$RTC_OFFSET_STATE_DIR/offset"

# Missing RTC: nothing happens.
setup
rm "$root/case/sys/rtc0/since_epoch" 2>/dev/null || true
state "800000 1780000000"
clock 1000
run restore rtc0
check "missing RTC leaves the clock" equals "$root/case/clock" 1000
check "missing RTC keeps the state" equals "$RTC_OFFSET_STATE_DIR/offset" "800000 1780000000"

# Save after NTP synchronisation.
setup
rtc 900000
clock 1785000000
ntp yes
run save rtc0
check "synchronised clock is saved" equals "$RTC_OFFSET_STATE_DIR/offset" "900000 $((1785000000 - 900000))"
check "save leaves no temporary files" equals <(find "$RTC_OFFSET_STATE_DIR" -mindepth 1 | wc -l) 1

# An unchanged offset is not rewritten.
rtc 900100
clock 1785000100
run save rtc0
check "unchanged offset is not rewritten" equals "$RTC_OFFSET_STATE_DIR/offset" "900000 $((1785000000 - 900000))"
# A changed offset is.
clock 1785000200
run save rtc0
check "changed offset is rewritten" equals "$RTC_OFFSET_STATE_DIR/offset" "900100 $((1785000200 - 900100))"

# The synchronisation flag file also counts as synchronised.
setup
unset RTC_OFFSET_SYNCED_CMD
touch "$RTC_OFFSET_SYNC_FILE"
rtc 900000
clock 1785000000
run save rtc0
check "timesyncd flag file allows saving" equals "$RTC_OFFSET_STATE_DIR/offset" "900000 $((1785000000 - 900000))"

# No save when unsynchronised and not restored.
setup
state "800000 1780000000"
rtc 900000
clock 1000
run save rtc0
check "unsynchronised clock is not saved" equals "$RTC_OFFSET_STATE_DIR/offset" "800000 1780000000"
setup
rtc 900000
clock 1785000000
run save rtc0
check "unsynchronised clock creates no state" absent "$RTC_OFFSET_STATE_DIR/offset"

# Save after a restore (shutdown without NTP) keeps the offset current.
setup
state "800000 1780000000"
rtc 803600
clock 1000
run restore rtc0
rtc 810000
clock $((810000 + 1780000000 + 5))
run save rtc0
check "restored clock is saved" equals "$RTC_OFFSET_STATE_DIR/offset" "810000 1780000005"

# A synchronised clock before the minimum is not saved.
setup
rtc 900000
clock 1000
ntp yes
run save rtc0
check "clock before the minimum is not saved" absent "$RTC_OFFSET_STATE_DIR/offset"

# Usage errors fail.
setup
usage_fails() { ! bash "$script" restore 2>/dev/null; }
check "missing rtc argument fails" usage_fails

check "restore and save exit successfully" absent "$root/errors"

if [ "$failures" -ne 0 ]; then
  echo "$failures rtc-offset check(s) failed" >&2
  exit 1
fi
echo "all rtc-offset checks passed"
