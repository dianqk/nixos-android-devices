{
  config,
  lib,
  ...
}:
{
  options.hardware.dodge.touch.wakeDisplay = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Report touches while the panel is off, allowing the compositor to wake it.
      When false, the controller enters deep sleep with its interrupt masked
      while the panel is off. Other input devices are unaffected.
    '';
  };

  config.boot.extraModprobeConfig = lib.optionalString config.hardware.dodge.touch.wakeDisplay ''
    options synaptics_tcm2 follow_panel=0
  '';
}
