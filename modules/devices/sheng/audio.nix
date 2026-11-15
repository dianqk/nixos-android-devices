# Speaker routing data for androidDevices.audio.orientation. Each CS35L43
# amplifier selects its TDM input slot: slot 0 carries FL, slot 1 FR. The UCM
# verb starts with T* on slot 0 and B* on slot 1, which is correct in the
# native landscape transform (T amplifiers at the left edge).
{ lib, ... }:
let
  amplifiers = {
    top = [
      "TLH"
      "TLL"
      "TRL"
    ];
    bottom = [
      "BLH"
      "BLL"
      "BRL"
    ];
  };
  slots =
    { top, bottom }:
    map (amp: {
      control = "${amp} ASPRX1 Slot Position";
      value = top;
    }) amplifiers.top
    ++ map (amp: {
      control = "${amp} ASPRX1 Slot Position";
      value = bottom;
    }) amplifiers.bottom;
  native = slots {
    top = 0;
    bottom = 1;
  };
in
{
  androidDevices.audio.orientation = {
    card = lib.mkDefault "XiaomiPad6SPro";
    routes = lib.mapAttrs (_: lib.mkDefault) {
      normal = native;
      "180" = slots {
        top = 1;
        bottom = 0;
      };
      # Unverified, pending the portrait corner check: keep the native mapping.
      "90" = native;
      "270" = native;
    };
  };
}
