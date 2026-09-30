# Optional suspend workarounds used by the downstream Sheng system profile.
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
      pkgs.systemd
      shengWakePolicy
    ];
    text = ''
      case "''${1:-}" in
        pre)
          if [ -d /sys/module/ath12k_wifi7 ]; then
            echo "removing ath12k_wifi7 before suspend"
            modprobe --remove ath12k_wifi7
          fi
          ;;
        post)
          echo "loading ath12k_wifi7 after resume"
          modprobe ath12k_wifi7
          udevadm settle --timeout=15 || true
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
