# Validate exported capability behavior without importing desktop examples.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  native = (flake.lib.mkBuildEnvironment { buildSystem = "aarch64-linux"; }).pkgs;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    };
    driver = env.pkgs.androidDevicePackages.libva-v4l2;
    replacement = env.pkgs.emptyDirectory;
    make =
      device: extra:
      env.nixosSystem {
        modules = [
          flake.nixosModules.${device}
          extra
        ];
      };
  in
  assert driver.stdenv.buildPlatform.system == "aarch64-linux";
  assert driver.stdenv.hostPlatform.system == "aarch64-linux";
  assert driver.drvPath == native.androidDevicePackages.libva-v4l2.drvPath;
  {
    package = driver.drvPath;
    devices = lib.genAttrs [ "aurora" "asphalt" "sheng" "polaris" "clover" ] (
      device:
      let
        plain = (make device { }).config;
        enabled =
          (make device {
            androidDevices.video.vaapi.enable = true;
          }).config;
        replaced =
          (make device {
            androidDevices.video.vaapi = {
              enable = true;
              package = replacement;
            };
          }).config;
        recovery =
          (make device {
            androidDevices.video.vaapi.enable = true;
            androidDevices.recovery.enable = true;
          }).config;
      in
      assert !plain.androidDevices.video.vaapi.enable;
      assert !(builtins.elem driver plain.hardware.graphics.extraPackages);
      assert enabled.hardware.graphics.enable;
      assert builtins.elem driver enabled.hardware.graphics.extraPackages;
      assert enabled.androidDevices.video.ffmpegPackage.drvPath == env.pkgs.ffmpeg.drvPath;
      assert !(enabled.environment.variables ? LIBVA_DRIVER_NAME);
      assert !enabled.programs.niri.enable && !enabled.programs.sway.enable;
      assert builtins.elem replacement replaced.hardware.graphics.extraPackages;
      assert !(builtins.elem driver replaced.hardware.graphics.extraPackages);
      assert !(builtins.elem driver recovery.hardware.graphics.extraPackages);
      {
        selected = enabled.androidDevices.video.vaapi.package.drvPath;
        override = replaced.androidDevices.video.vaapi.package.drvPath;
        recoveryExcludesDriver = true;
      }
    );
  }
)
