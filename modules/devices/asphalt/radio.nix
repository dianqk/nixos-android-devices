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
