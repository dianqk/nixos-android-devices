{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  cfg = config.hardware.asphalt.radio;
  wifiMacConfig = androidPackages.packaging.runCommand "asphalt-wifi-mac.conf" { } ''
    printf '[connection]\nwifi.cloned-mac-address=%s\n' "$(cat ${cfg.wifiAddressFile})" > "$out"
  '';
  # NetworkManager ignores cloned-mac-address with its IWD backend, and IWD
  # keeps the kernel interface, so udev must set the address when wlan0 appears.
  # The 10- prefix takes precedence over IWD's 80-iwd.link, so keep its name policy.
  wifiMacLink = androidPackages.packaging.runCommand "asphalt-wifi.link" { } ''
    address=$(tr -d '[:space:]' < ${cfg.wifiAddressFile})
    if ! [[ $address =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
      echo "invalid Wi-Fi address in ${cfg.wifiAddressFile}" >&2
      exit 1
    fi
    printf '[Match]\nPath=platform-1c00000.pcie-pci-0000:01:00.0\n\n[Link]\nMACAddressPolicy=none\nMACAddress=%s\nNamePolicy=keep kernel\n' "$address" > "$out"
  '';
in
{
  options.hardware.asphalt.radio = {
    bluetoothAddressFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Saved Qualcomm Bluetooth NVM address in controller byte order.";
    };
    wifiAddressFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File containing this tablet's factory Wi-Fi MAC address.";
    };
  };
  config = lib.mkIf (!config.androidDevices.recovery.enable) {
    environment.etc."NetworkManager/conf.d/90-asphalt-wifi-mac.conf" = lib.mkIf (
      cfg.wifiAddressFile != null
    ) { source = wifiMacConfig; };
    environment.etc."systemd/network/10-asphalt-wifi.link" = lib.mkIf (cfg.wifiAddressFile != null) {
      source = wifiMacLink;
    };
    systemd.services.asphalt-bluetooth-address = lib.mkIf (cfg.bluetoothAddressFile != null) {
      description = "Set the TB320FC factory Bluetooth address";
      after = [ "bluetooth.service" ];
      wants = [ "bluetooth.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for attempt in $(seq 1 30); do
          test -e /sys/class/bluetooth/hci0 && break
          sleep 1
        done
        test -e /sys/class/bluetooth/hci0
        # The saved Qualcomm NVM address is in controller byte order. BlueZ's
        # public-addr argument uses the displayed (Android) byte order.
        IFS=: read -r a b c d e f < ${lib.escapeShellArg cfg.bluetoothAddressFile}
        address="$f:$e:$d:$c:$b:$a"
        current=$(${pkgs.bluez}/bin/btmgmt --index 0 info | ${pkgs.gnused}/bin/sed -nE 's/^[[:space:]]*addr ([[:xdigit:]:]{17}) version .*/\1/p' | head -n 1)
        if [[ ''${current,,} == ''${address,,} ]]; then
          exit 0
        fi
        ${pkgs.bluez}/bin/btmgmt --index 0 public-addr "$address"
      '';
    };

  };
}
