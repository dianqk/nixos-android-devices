# Activates the primary GW provisioning session for the first USIM when the
# modem has not done so itself. Arguments: timeout and grace period in seconds.
# Exits 0 when a session exists, after activating one, or when no USIM shows up.
timeout=${1:-90}
grace=${2:-10}
device=qrtr://0

# Prints "<slot> <aid>" for the first USIM application of a present card that
# is waiting for provisioning (qmicli --uim-get-card-status format).
first_usim() {
  awk '
    /^Slot \[/ { match($0, /[0-9]+/); slot = substr($0, RSTART, RLENGTH); present = 0; next }
    /Card state:/ { present = ($0 ~ /\x27present\x27/); next }
    /Application type:/ { usim = ($0 ~ /\x27usim /); next }
    /Application state:/ { state = $0; sub(/.*: \x27/, "", state); sub(/\x27.*/, "", state); next }
    /Application ID:/ { want_aid = 1; next }
    want_aid {
      want_aid = 0; aid = $0; gsub(/[[:space:]]/, "", aid)
      if (present && usim && aid != "" &&
          state ~ /^(detected|pin1-or-upin-pin-required|puk1-or-upin-puk-required|check-personalization-state)$/) {
        print slot, aid; exit
      }
    }'
}

start=$SECONDS
seen=
while ((SECONDS - start < timeout)); do
  if status=$(qmicli -d "$device" --uim-get-card-status 2>/dev/null); then
    if ! grep -q "Primary GW:   session doesn't exist" <<<"$status"; then
      echo "primary GW provisioning session present"
      exit 0
    fi
    target=$(first_usim <<<"$status")
    if [ -n "$target" ]; then
      if [ -z "$seen" ]; then
        seen=$SECONDS
        echo "USIM (slot/AID $target) has no primary GW session; waiting ${grace}s for the modem"
      elif ((SECONDS - seen >= grace)); then
        read -r slot aid <<<"$target"
        echo "activating the primary GW session for slot $slot, AID $aid"
        qmicli -d "$device" --uim-change-provisioning-session="session-type=primary-gw-provisioning,activate=yes,slot=$slot,aid=$aid"
        exit 0
      fi
    fi
  fi
  sleep 2
done
echo "no USIM waiting for provisioning within ${timeout}s"
