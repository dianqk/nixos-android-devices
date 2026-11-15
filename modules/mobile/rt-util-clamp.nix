# Minimum utilization clamp of real-time tasks. The kernel default (1024)
# runs every RT wakeup, such as a threaded touch or SPI interrupt, at the
# highest CPU frequency, which on cpufreq OPP tables with bandwidth votes also
# raises the DDR frequency. Pixel device init files set 0 (for example
# device/google/gs101 init.gs101.rc), so RT tasks follow schedutil like other
# tasks.
{ config, lib, ... }:
let
  cfg = config.androidDevices.power;
in
{
  options.androidDevices.power.rtUtilClampMin = lib.mkOption {
    type = lib.types.nullOr (lib.types.ints.between 0 1024);
    default = 0;
    description = ''
      `kernel.sched_util_clamp_min_rt_default` for the installed system. `null`
      keeps the kernel default (1024, maximum frequency for RT tasks). Ignored
      by kernels without CONFIG_UCLAMP_TASK.
    '';
  };
  config = lib.mkIf (config.androidDevices.enable && cfg.rtUtilClampMin != null) {
    # "-": systemd-sysctl ignores the key when the kernel lacks uclamp.
    environment.etc."sysctl.d/60-android-rt-util-clamp.conf".text = ''
      -kernel.sched_util_clamp_min_rt_default = ${toString cfg.rtUtilClampMin}
    '';
    # Apply a changed value on switch, not only at the next boot.
    systemd.services.systemd-sysctl.restartTriggers = [
      config.environment.etc."sysctl.d/60-android-rt-util-clamp.conf".source
    ];
  };
}
