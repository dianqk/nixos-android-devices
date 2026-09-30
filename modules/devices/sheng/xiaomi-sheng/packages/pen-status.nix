# ---
# Module: Xiaomi Pen Status
# Description: Pen Status tray utility for Xiaomi Pad 6S Pro 12.4
# Scope: System
# ---

{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:

let
  cfg = config.hardware.sheng.pen-status;
  pkg = cfg.package;
in
{
  options.hardware.sheng.pen-status = {
    package = lib.mkPackageOption androidPackages.devices.sheng "pen-status" {
      pkgsText = "androidPackages.devices.sheng";
    };
    enable = lib.mkEnableOption "Xiaomi Pen Status tray utility";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkg ];
  };
}
