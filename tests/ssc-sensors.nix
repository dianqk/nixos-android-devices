{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    };
    make =
      board: extra:
      env.nixosSystem {
        modules = [
          flake.nixosModules.${board}
          {
            androidDevices.usbSerial = "ssc-${board}";
            hardware.${board}.sensors.enable = true;
          }
          extra
        ];
      };
  in
  lib.genAttrs [ "asphalt" "polaris" "aurora" ] (
    board:
    let
      s = make board { };
      c = s.config;
      recovery = (make board { androidDevices.recovery.enable = true; }).config;
      disabled = (make board { hardware.${board}.sensors.enable = lib.mkForce false; }).config;
      alone =
        (make board (
          lib.optionalAttrs (board == "polaris") {
            hardware.polaris = {
              radio.enable = false;
              audio.enable = false;
            };
          }
        )).config;
      data = c.androidDevices.sensors.dataPackage;
      rpc = c.androidDevices.sensors.rpcPackage;
    in
    assert lib.all (a: a.assertion) c.assertions;
    assert lib.all (a: a.assertion) alone.assertions;
    assert c.hardware.sensor.iio.enable;
    assert !(recovery.systemd.services ? android-ssc-sensors);
    assert !(disabled.systemd.services ? android-ssc-sensors);
    assert !c.programs.sway.enable;
    assert lib.hasSuffix "/bin/${
      if board == "aurora" then "adsprpcd" else "sdsprpcd"
    } sensorspd" c.systemd.services.android-ssc-sensors.serviceConfig.ExecStart;
    assert
      c.systemd.services.android-ssc-sensors.bindsTo
      == [ "dev-fastrpc\\x2d${if board == "aurora" then "adsp" else "sdsp"}.device" ];
    assert board != "aurora" || lib.elem "/odm/etc/sensors" c.androidDevices.sensors.configPaths;
    assert lib.elem "/share/uncompressed-firmware" alone.environment.pathsToLink;
    assert board != "polaris" || alone.systemd.services ? polaris-pd-mapper;
    assert rpc.stdenv.hostPlatform.system == "aarch64-linux";
    assert rpc.stdenv.buildPlatform.system == buildSystem;
    {
      data = data.drvPath;
      rpc = rpc.drvPath;
      rotate = s.pkgs.androidDevicePackages.sensor-rotate.drvPath;
      unit = c.systemd.units."android-ssc-sensors.service".text;
      proxy = c.systemd.units."iio-sensor-proxy.service".text;
      udev = c.services.udev.extraRules;
    }
  )
)
