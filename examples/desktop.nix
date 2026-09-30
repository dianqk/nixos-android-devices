# Shared minimal session; device examples retain their own hardware/storage settings.
{
  pkgs,
  config,
  ...
}:
let
  terminal = pkgs.writeShellScript "example-terminal" ''
    ${pkgs.fastfetch}/bin/fastfetch || true
    exec ${pkgs.bashInteractive}/bin/bash --login
  '';
in
{
  hardware.bluetooth.enable = true;
  users.users.demo = {
    isNormalUser = true;
    hashedPassword = "";
    extraGroups = [
      "video"
      "input"
      "render"
    ];
  };
  programs.sway.enable = true;
  programs.foot.enable = true;
  environment.systemPackages = [
    pkgs.fastfetch
    pkgs.grim
    pkgs.iw
    pkgs.bluez
    config.androidDevices.video.ffmpegPackage
    pkgs.glmark2
    pkgs.vkmark
    config.androidDevices.camera.package
  ];
  environment.etc."sway/config".text = ''
    output DSI-1 transform 90
    output * bg #202020 solid_color
    set $mod Mod4
    for_window [app_id="example-terminal"] fullscreen enable
    bindsym $mod+Return exec ${pkgs.foot}/bin/foot --app-id=example-terminal ${terminal}
    bindsym $mod+Shift+e exit
    exec ${pkgs.foot}/bin/foot --app-id=example-terminal ${terminal}
  '';
  systemd.services."getty@".preStart = ''
    if [ "$TTY" = tty1 ]; then
      for backlight in /sys/class/backlight/*; do
        [ -f "$backlight/max_brightness" ] || continue
        read -r maximum < "$backlight/max_brightness"
        echo "$(( (maximum + 2) / 4 ))" > "$backlight/brightness"
      done
    fi
  '';
  services.getty.autologinUser = "demo";
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ]; then
      exec ${pkgs.dbus}/bin/dbus-run-session ${pkgs.sway}/bin/sway --config /etc/sway/config
    fi
  '';
}
