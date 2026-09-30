#!/usr/bin/env bash
set -euo pipefail
install -d /run/systemd/network
identity=${POLARIS_WIFI_IDENTITY:?}
if [[ ! -e $identity ]]; then
  echo 'Polaris Wi-Fi identity is absent; refusing to start IWD.' >&2
  exit 1
fi
address=$(cat "$identity")
[[ $address =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]
# Loaded by udev when the delayed firmware creates the interface.
printf '[Match]\nDriver=ath10k_snoc\n[Link]\nMACAddressPolicy=none\nMACAddress=%s\n' \
  "$address" > /run/systemd/network/10-polaris-wifi.link
udevadm control --reload
