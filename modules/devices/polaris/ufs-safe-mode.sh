# Called by the ordered initrd oneshot; recovery keeps manual opt-in behavior.
set -eu
ufs=${1:-/sys/bus/platform/devices/1d84000.ufshc}
for attempt in $(seq 1 300); do
  if test -e "$ufs/clkscale_enable"; then
    echo on > "$ufs/power/control"
    echo 0 > "$ufs/clkgate_enable"
    echo 0 > "$ufs/clkscale_enable"
    test "$(cat "$ufs/power/control")" = on
    test "$(cat "$ufs/clkgate_enable")" = 0
    test "$(cat "$ufs/clkscale_enable")" = 0
    exit 0
  fi
  sleep 0.1
done
echo 'UFS clock controls did not appear within 30 seconds' >&2
exit 1
