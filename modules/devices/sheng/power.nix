# Optional, opt-in Sheng suspend workarounds (wake-source filtering and Wi-Fi reload).
{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  shengWakePolicy = androidPackages.packaging.writeShellApplication {
    name = "sheng-wake-policy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      find /sys/devices -path '*/power/wakeup' -type f -print0 2>/dev/null \
        | while IFS= read -r -d "" wakeup; do
          case "$wakeup" in
            */fingerprint_fpc/power/wakeup | \
            */qcom-battmgr-bat/power/wakeup | \
            */32300000.remoteproc/power/wakeup | \
            */3f40000.ipa/power/wakeup | \
            */6800000.remoteproc/power/wakeup | \
            */mhi0/power/wakeup | \
            */hid-*-battery-*/power/wakeup)
              if [ "$(cat "$wakeup" 2>/dev/null || true)" != disabled ]; then
                if printf '%s\n' disabled > "$wakeup"; then
                  printf 'disabled wake source: %s\n' "$wakeup"
                else
                  printf 'failed to disable wake source: %s\n' "$wakeup" >&2
                fi
              fi
              ;;
          esac
        done
    '';
  };

  shengAth12kSleep = androidPackages.packaging.writeShellApplication {
    name = "sheng-ath12k-sleep";
    runtimeInputs = [
      pkgs.kmod
      pkgs.coreutils
      pkgs.systemd
      shengWakePolicy
    ];
    text = ''
      state_dir=/run/sheng-ath12k-sleep
      restore_iwd() {
        if [ -e "$state_dir/iwd-stopped" ]; then
          rm -f "$state_dir/iwd-stopped"
          systemctl start --no-block iwd.service
        fi
      }
      case "''${1:-}" in
        pre)
          # A running IWD can raise a hotplugged interface before udev applies
          # its .link MAC address (EBUSY). Prevent D-Bus reactivation until the
          # reloaded interface has completed udev initialization.
          if systemctl is-active --quiet iwd.service; then
            mkdir -p "$state_dir"
            touch "$state_dir/iwd-stopped"
            trap 'restore_iwd' ERR
            systemctl stop iwd.service
          fi
          if [ -d /sys/module/ath12k_wifi7 ]; then
            echo "removing ath12k_wifi7 before suspend"
            modprobe --remove ath12k_wifi7
          fi
          ;;
        post)
          trap 'restore_iwd' EXIT
          echo "loading ath12k_wifi7 after resume"
          modprobe ath12k_wifi7
          # Firmware probing continues after modprobe returns. An empty udev
          # queue alone does not mean the replacement network interface exists.
          found=false
          for ((attempt = 0; attempt < 100; attempt++)); do
            for interface in /sys/bus/pci/devices/0000:01:00.0/net/*; do
              if [ -e "$interface" ]; then
                udevadm wait --initialized=yes --timeout=10 "$interface"
                found=true
                break 2
              fi
            done
            sleep 0.1
          done
          if [ "$found" != true ]; then
            echo "Sheng Wi-Fi interface did not reappear" >&2
            exit 1
          fi
          sheng-wake-policy
          ;;
        *)
          echo "Usage: sheng-ath12k-sleep {pre|post}" >&2
          exit 2
          ;;
      esac
    '';
  };

in
{
  options.hardware.sheng.suspendWorkarounds.enable =
    lib.mkEnableOption "Sheng wake-source filtering and ath12k cold cycling across suspend";
  config =
    lib.mkIf (!config.androidDevices.recovery.enable && config.hardware.sheng.suspendWorkarounds.enable)
      {
        systemd.services.sheng-wake-policy = {
          description = "Disable unused Sheng wake sources";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-udev-settle.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${shengWakePolicy}/bin/sheng-wake-policy";
          };
        };

        # NM may D-Bus-activate IWD even after an explicit stop. Keep it from
        # racing udev on resume; the helper clears this runtime gate and starts
        # IWD again only if it was active before the cold cycle.
        systemd.services.iwd = lib.mkIf config.networking.wireless.iwd.enable {
          unitConfig.ConditionPathExists = "!/run/sheng-ath12k-sleep/iwd-stopped";
        };

        systemd.services.sheng-ath12k-sleep = {
          description = "Cold-cycle Sheng Wi-Fi across suspend";
          wantedBy = [ "sleep.target" ];
          before = [ "sleep.target" ];
          unitConfig.StopWhenUnneeded = true;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = 30;
            TimeoutStopSec = 30;
            ExecStart = "${shengAth12kSleep}/bin/sheng-ath12k-sleep pre";
            ExecStop = "${shengAth12kSleep}/bin/sheng-ath12k-sleep post";
          };
        };

      };
}
