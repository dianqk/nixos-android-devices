{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.hardware.polaris.desktop-switch.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Provide desktop-switch to move the active seat session between Phosh
      and Sway. Both compositors run exclusively on tty1: stopping a
      compositor also kills the terminal that started the switch, so each
      switch runs in a system-level oneshot service instead of being driven
      from the calling shell. Phosh and Sway are made mutually exclusive
      via conflicts. desktop-switch must run as root; allow it through
      polkit or sudo for your user.
    '';
  };

  config = lib.mkIf config.hardware.polaris.desktop-switch.enable {
    systemd.services.phosh.conflicts = [ "sway.service" ];

    systemd.services.sway = {
      conflicts = [ "phosh.service" "getty@tty1.service" ];
      serviceConfig = {
        # Keep both compositors on the same VT: msm_dpu on sdm845 mainline
        # does not survive VT switches (encoder state is lost and the panel
        # never comes back until reboot).
        TTYPath = lib.mkForce "/dev/tty1";
        Restart = lib.mkForce "on-failure";
      };
    };

    systemd.services.switch-to-sway = {
      description = "Stop Phosh and start Sway";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "switch-to-sway" ''
          /run/current-system/sw/bin/systemctl stop phosh || true
          sleep 1
          /run/current-system/sw/bin/systemctl start sway
        '';
      };
    };

    systemd.services.switch-to-phosh = {
      description = "Stop Sway and start Phosh";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "switch-to-phosh" ''
          /run/current-system/sw/bin/systemctl stop sway || true
          sleep 1
          /run/current-system/sw/bin/systemctl start phosh
        '';
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "desktop-switch" ''
        case "''${1:-}" in
          sway)
            /run/current-system/sw/bin/systemctl start --no-block switch-to-sway
            echo "Switching to Sway (takes a few seconds)..."
            ;;
          phosh)
            /run/current-system/sw/bin/systemctl start --no-block switch-to-phosh
            echo "Switching back to Phosh (takes about 10 seconds)..."
            ;;
          status)
            echo "phosh: $(/run/current-system/sw/bin/systemctl is-active phosh)"
            echo "sway : $(/run/current-system/sw/bin/systemctl is-active sway)"
            echo "(mutually exclusive, both on tty1)"
            ;;
          *)
            echo "usage: desktop-switch {sway|phosh|status}"
            exit 1
            ;;
        esac
      '')
    ];
  };
}
