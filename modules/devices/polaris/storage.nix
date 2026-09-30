{ ... }:
{
  boot.initrd.systemd.services.polaris-ufs-safe-mode = {
    description = "Disable UFS runtime suspend, clock gating and scaling";
    requiredBy = [
      "sysroot.mount"
    ];
    before = [
      "sysroot.mount"
    ];
    after = [ "systemd-udev-trigger.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 35;
    };
    script = builtins.readFile ./ufs-safe-mode.sh;
  };
}
