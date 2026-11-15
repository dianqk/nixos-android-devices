# Optional wakeup-source policy: device modules declare named wakeup sources by
# sysfs device path; the consumer chooses which to keep. When enabled, every other
# device's power/wakeup is disabled at boot, when devices appear or bind, and again
# before each system sleep.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.power.wakeup;
  keptPatterns = lib.concatMap (name: cfg.sources.${name}.devices) cfg.keep;

  # udev's DEVPATH match uses fnmatch(3) without FNM_PATHNAME, like Bash's [[ == ]]:
  # `*` also matches `/`.
  rules = pkgs.writeTextDir "lib/udev/rules.d/90-android-devices-wakeup.rules" ''
    ACTION!="add|bind|change", GOTO="android_devices_wakeup_end"
    TEST!="power/wakeup", GOTO="android_devices_wakeup_end"
    ${
      lib.concatMapStrings (pattern: ''
        DEVPATH=="${pattern}", GOTO="android_devices_wakeup_end"
      '') keptPatterns
    }ATTR{power/wakeup}="disabled"
    LABEL="android_devices_wakeup_end"
  '';

  apply = androidPackages.packaging.writeShellApplication {
    name = "android-devices-wakeup-policy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      keep=(${lib.escapeShellArgs keptPatterns})
      find /sys/devices -path '*/power/wakeup' -type f -print0 2>/dev/null \
        | while IFS= read -r -d "" wakeup; do
          device=''${wakeup%/power/wakeup}
          devpath=''${device#/sys}
          kept=false
          for pattern in "''${keep[@]}"; do
            # shellcheck disable=SC2053 # glob match is intended
            if [[ $devpath == $pattern ]]; then
              kept=true
              break
            fi
          done
          state=$(cat "$wakeup" 2>/dev/null || true)
          if [ "$kept" = true ]; then
            printf 'kept wakeup source (%s): %s\n' "''${state:-unknown}" "$devpath"
          elif [ "$state" = enabled ]; then
            if printf '%s\n' disabled > "$wakeup"; then
              printf 'disabled wakeup source: %s\n' "$devpath"
            else
              printf 'failed to disable wakeup source: %s\n' "$devpath" >&2
            fi
          fi
        done
    '';
  };
in
{
  options.androidDevices.power.wakeup = {
    sources = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "What the source is and how well it is known to wake the device.";
            };
            devices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              example = [ "/devices/platform/gpio-keys" ];
              description = ''
                Sysfs device paths (DEVPATH, without the `/sys` prefix) whose
                `power/wakeup` belongs to this source. Shell-style globs are
                allowed; `*` also matches `/`. Use stable device-tree or bus
                paths, never interrupt numbers.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Named wakeup sources declared by the device module. They only describe
        hardware; nothing changes unless `enable` is set.
      '';
    };

    enable = lib.mkEnableOption ''
      the wakeup-source policy. Every device wakeup not listed in `keep` is
      disabled at boot, when a device appears or binds, and before each system
      sleep. Kept sources retain the setting their driver chose
    '';

    keep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "powerKey"
        "battery"
      ];
      description = "Names from `sources` whose device wakeups are left untouched.";
    };
  };

  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    assertions = map (name: {
      assertion = cfg.sources ? ${name};
      message = "androidDevices.power.wakeup.keep: unknown source `${name}`; declared: ${lib.concatStringsSep ", " (lib.attrNames cfg.sources)}.";
    }) cfg.keep;

    services.udev.packages = [ rules ];

    # udev covers new devices; this pass also catches drivers that re-enable
    # wakeup without a uevent, at boot and right before every sleep.
    systemd.services.android-devices-wakeup-policy = {
      description = "Apply the wakeup-source policy";
      wantedBy = [
        "multi-user.target"
        "sleep.target"
      ];
      after = [ "systemd-udev-trigger.service" ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe apply;
      };
    };
  };
}
