# Niri desktop on the panel (mediatek-drm), with USB networking.
{ ... }:
{
  imports = [
    ../desktop.nix
    ../usb-network.nix
  ];
  androidDevices.video.vaapi.enable = true;
  example.desktop = {
    # 8.8-inch 1600x2560 portrait panel.
    scale = "2";
    # The panel's DSI connector under mediatek-drm.
    output = "DSI-1";
  };
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=11
  '';
  # Power key (MT6363): a short press powers the system off (logind's
  # default, stated explicitly). There is no suspend on the T880 yet.
  services.logind.settings.Login.HandlePowerKey = "poweroff";
  # niri would take the power key and suspend; suspend is not supported yet.
  example.desktop.niriPowerKey = false;
  systemd.sleep.settings.Sleep.AllowSuspend = "no";
  # The cover's hall sensor reports a lid switch; suspend is not supported
  # yet, so a closed cover does nothing.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
  ];
}
