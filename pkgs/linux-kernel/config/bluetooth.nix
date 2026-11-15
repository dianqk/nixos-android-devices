{ lib, configfile }:
# Shared by every SoC and kernel variant. BlueZ needs RFCOMM for hands-free
# headset audio (HFP/HSP) and serial profiles, BNEP for Bluetooth network
# tethering (PAN) and HIDP for classic Bluetooth keyboards and mice. Add the
# profiles only where the baseline lacks them, as modules (loaded on demand
# when bluetoothd opens the socket); a baseline that already selects them is
# kept as it is.
let
  baseLines = lib.splitString "\n" (builtins.readFile configfile);
  enabled = symbol: lib.any (lib.hasPrefix "CONFIG_${symbol}=") baseLines;
  bluetooth = enabled "BT";
  profiles = with lib.kernel; {
    BT_RFCOMM = module;
    BT_RFCOMM_TTY = yes;
    BT_BNEP = module;
    BT_BNEP_MC_FILTER = yes;
    BT_BNEP_PROTO_FILTER = yes;
    BT_HIDP = module;
  };
in
lib.optionalAttrs bluetooth (lib.filterAttrs (symbol: _: !(enabled symbol)) profiles)
