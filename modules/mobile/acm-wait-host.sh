# Run as the main process of a Type=simple service, with no TTY stdio.
# A gadget TTY exists before its USB host connects; opening it then can block.
state_file=$1
shift

while :; do
  state=
  if { IFS= read -r state < "$state_file"; } 2>/dev/null &&
     [ "$state" = configured ]; then
    # Keep the getty's arguments and PID, so normal hangup/restart still applies.
    exec "$@"
  fi
  sleep 1
done
