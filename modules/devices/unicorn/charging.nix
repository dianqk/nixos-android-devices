{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.services.xiaomi-mipps-auth;
in
{
  options.services.xiaomi-mipps-auth.enable = lib.mkEnableOption "Unicorn Xiaomi charger authentication";
  options.services.xiaomi-mipps-auth.package =
    lib.mkPackageOption androidPackages.devices.unicorn "mipps-auth"
      { };
  options.services.xiaomi-mipps-auth.allowDataRoleSwap = lib.mkEnableOption ''
    host data role discovery for a known Xiaomi charger (may interrupt USB data)
  '';
  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
      environment.systemPackages = [ cfg.package ];
      systemd.services.xiaomi-mipps-auth = {
        description = "Unicorn Xiaomi charger authentication";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-udev-trigger.service"
        ]
        ++ lib.optional cfg.allowDataRoleSwap "usb-signaller.service";
        requires = lib.optional cfg.allowDataRoleSwap "usb-signaller.service";
        serviceConfig = {
          Type = "simple";
          ExecStart =
            "${lib.getExe cfg.package} --daemon"
            + lib.optionalString cfg.allowDataRoleSwap " --allow-data-role-swap";
          Restart = "on-failure";
          RestartSec = 5;
          RuntimeDirectory = "xiaomi-mipps-auth";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "yes";
          # Only the identified charging controls are writable; /sys/class and
          # /sys/devices DRM/Type-C/power telemetry stay readable.
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = [ "/sys" ];
          ReadWritePaths = [ "-/sys/devices/platform/pmic-glink" ];
          PrivateTmp = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = [ ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        };
      };
    })
  ];
}
