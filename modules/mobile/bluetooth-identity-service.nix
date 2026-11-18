# Reusable runtime provisioning for boards whose controller lacks its public address.
{ lib, pkgs, utils }:
{
  pathType = lib.types.addCheck lib.types.str (
    value:
    !(builtins.hasContext value)
    && lib.hasPrefix "/" value
    && !(lib.hasPrefix "/nix/store/" value)
    && value != "/nix/store"
    && builtins.match "/[^[:cntrl:]]+" value != null
    && lib.all (part: part != "" && part != "." && part != "..") (
      lib.tail (lib.splitString "/" value)
    )
  );
  mkService = { identityFile, boardCompatible, controllerCompatible }: {
    description = "Configure and verify this device's Bluetooth public address";
    before = [ "bluetooth.service" ];
    requiredBy = [ "bluetooth.service" ];
    after = [ "local-fs.target" "systemd-udev-trigger.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 65;
      UMask = "0077";
      LimitCORE = 0;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      RestrictAddressFamilies = [ "AF_BLUETOOTH" "AF_UNIX" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      ExecStart = utils.escapeSystemdExecArgs [
        "${pkgs.python3}/bin/python3"
        "${../../pkgs/mobile/bluetooth-identity.py}"
        "--identity-file" identityFile
        "--board-compatible" boardCompatible
        "--controller-compatible" controllerCompatible
        "--timeout" "60"
      ];
    };
  };
}
