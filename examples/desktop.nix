# Shared minimal session; device examples retain their own hardware/storage settings.
{
  pkgs,
  config,
  lib,
  utils,
  ...
}:
let
  cfg = config.example.desktop;
  terminal = pkgs.writeShellScript "example-terminal" ''
    ${pkgs.fastfetch}/bin/fastfetch || true
    exec ${pkgs.bashInteractive}/bin/bash --login
  '';
in
{
  options.example.desktop = {
    scale = lib.mkOption {
      type = lib.types.str;
      default = "1";
      description = "Scale of the internal display.";
    };
  };

  config = {
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
    programs.niri.enable = true;
    programs.foot.enable = true;
    environment.systemPackages = [
      pkgs.fastfetch
      pkgs.iw
      pkgs.bluez
      pkgs.wvkbd
      config.androidDevices.video.ffmpegPackage
      pkgs.glmark2
      pkgs.vkmark
      config.androidDevices.camera.package
    ];
    environment.etc."niri/config.kdl".text = ''
      input {
        touch { map-to-output "DSI-1"; }
      }
      output "DSI-1" {
        scale ${cfg.scale}
      }
      layout {
        gaps 0
        background-color "#202020"
        default-column-width { proportion 1.0; }
        focus-ring { off; }
        border { off; }
      }
      animations { off; }
      hotkey-overlay { skip-at-startup; }
      binds {
        Mod+Return { spawn "${pkgs.foot}/bin/foot" "--app-id=example-terminal" "${terminal}"; }
        Mod+Shift+E { quit skip-confirmation=true; }
        Mod+Q { close-window; }
        Mod+Left { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up { focus-workspace-up; }
        Mod+Down { focus-workspace-down; }
        Mod+O { toggle-overview; }
        Print { screenshot-screen; }
      }
      // Keep the keyboard visible; its exclusive zone reserves space below windows.
      spawn-at-startup "${pkgs.wvkbd}/bin/wvkbd-mobintl"
      spawn-at-startup "${pkgs.foot}/bin/foot" "--app-id=example-terminal" "${terminal}"
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
    # Automatic desktop login belongs only to the local display, not USB serial.
    systemd.services."getty@tty1" = {
      overrideStrategy = "asDropin";
      serviceConfig.ExecStart = [
        ""
        "${lib.last (lib.toList config.systemd.services."getty@".serviceConfig.ExecStart)} --autologin demo"
      ];
    };
    # Preserve the template's environment and backlight hook when this instance's
    # equally named overrides.conf takes precedence over the template drop-in.
    systemd.units."getty@tty1.service".text = lib.mkForce (
      config.systemd.units."getty@.service".text
      + "\n"
      + (utils.systemdUtils.lib.serviceToUnit (
        config.systemd.services."getty@tty1" // { name = "getty@tty1.service"; }
      )).text
    );
    programs.bash.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ]; then
        export NIRI_CONFIG=/etc/niri/config.kdl
        # This hook already runs in a login shell; skip niri-session's shell re-entry.
        exec ${config.programs.niri.package}/bin/niri-session -l
      fi
    '';
  };
}
