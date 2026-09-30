#!/usr/bin/env bash
# Configure only an unconfigured controller; never modify factory partitions.
set -euo pipefail
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -d /sys/class/bluetooth/hci0 ]] && break
  sleep 0.1
done
[[ -d /sys/class/bluetooth/hci0 ]] || {
  echo 'Bluetooth controller hci0 did not appear within 10 seconds.' >&2
  exit 1
}
address=$(cat "${POLARIS_BLUETOOTH_IDENTITY:?Bluetooth identity file is required}")
[[ $address =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]
# The identity was verified from LineageOS; missing files must not generate a MAC.
if btmgmt extinfo | grep 'Unconfigured controller (hci0,' > /dev/null; then
  btmgmt -i 0 public-addr "$address"
fi
# Public-address assignment completes before normal mgmt registration does.
for ((attempt = 0; attempt < 30; attempt++)); do
  if btmgmt -i 0 info 2>/dev/null | grep -Fi "addr $address " > /dev/null; then
    exit 0
  fi
  sleep 0.2
done
echo 'Factory Bluetooth address did not become ready; refusing fallback.' >&2
exit 1
