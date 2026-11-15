# T880 motion sensors through the SCP sensor hub (EXPERIMENTAL).
#
# LK loads the stock SCP firmware and leaves the SCP in reset; the kernel's
# mt6897-scp-bringup driver releases it on request through the vendor TF-A
# call, then sets up the sensor hub and exposes the accelerometer
# ("scp-accel", for iio-sensor-proxy), the ambient light sensor
# ("scp-als", illuminance in lux), the gyroscope ("scp-gyro", rad/s) and the
# magnetometer ("scp-magn", Gauss) as IIO. This module requests the release
# once per boot.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.t880.sensors;
in
{
  options.hardware.t880.sensors.enable = lib.mkEnableOption ''
    the SCP sensor hub (accelerometer as IIO) at boot (EXPERIMENTAL)
  '';

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.androidDevices.recovery.enable;
        message = "hardware.t880.sensors is for the installed system, not RAM recovery.";
      }
    ];
    systemd.services.t880-scp = {
      description = "T880 SCP sensor hub (release the SCP once per boot)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      before = [ "iio-sensor-proxy.service" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.coreutils ];
      script = ''
        dev=/sys/bus/platform/devices/1c400000.scp
        for _ in $(seq 50); do
          [ -e "$dev/release" ] && break
          sleep 0.2
        done
        if grep -q '^released=1' "$dev/state"; then
          echo "SCP already released"
          exit 0
        fi
        echo 1 > "$dev/release"
        for _ in $(seq 50); do
          grep -q ' hub=1 ' "$dev/state" && break
          sleep 0.2
        done
        cat "$dev/state"
      '';
    };
  };
}
