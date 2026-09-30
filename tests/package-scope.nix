# The shared package scope must preserve platform selection and consumer overrides.
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
    packages = flake.lib.mkPackageSet { inherit (env) pkgs; };
    hostPackages = flake.lib.mkPackageSet { pkgs = env.buildPackages; };
    overlayEnv = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      overlays = [
        flake.overlays.default
        (_final: prev: {
          androidDevicePackages = prev.androidDevicePackages.overrideScope (
            _self: old: {
              usb-signaller = old.usb-signaller.overrideAttrs (attrs: {
                passthru = (attrs.passthru or { }) // {
                  packageScopeMarker = true;
                };
              });
              devices = old.devices // {
                polaris = old.devices.polaris.overrideScope (
                  _device: previous: {
                    kernel = previous.kernel.overrideAttrs (attrs: {
                      passthru = (attrs.passthru or { }) // {
                        kernelScopeMarker = true;
                      };
                    });
                  }
                );
              };
            }
          );
        })
      ];
    };
    make =
      environment: extra:
      environment.nixosSystem {
        modules = [
          flake.nixosModules.polaris
          {

            hardware.polaris.radio.enable = false;
            hardware.polaris.audio.enable = false;
          }
          extra
        ];
      };
    plain = make env { };
    overlaid = make overlayEnv { };
    replacement = env.pkgs.writeShellScriptBin "usb-signaller" "exit 0";
    overridden = make env { androidDevices.usb.signaller.package = replacement; };
    shengOverride = env.nixosSystem {
      modules = [
        flake.nixosModules.sheng
        {
          hardware.sheng.thp = {
            enable = true;
            package = replacement;
          };
          hardware.sheng.sensors = {
            enable = true;
            devauthPackage = replacement;
          };
        }
      ];
    };
    boardOverride = packages.overrideScope (
      _self: old: {
        devices = old.devices // {
          sheng = old.devices.sheng.overrideScope (
            _device: _previous: {
              firmware = replacement;
            }
          );
        };
      }
    );
    dependencyOverride = packages.overrideScope (
      _self: _old: {
        mkAndroidBootImage = _: replacement;
      }
    );
  in
  assert lib.hasPrefix "${replacement}/"
    shengOverride.config.systemd.services.xiaomi-sheng-thp.serviceConfig.ExecStart;
  assert lib.hasPrefix "${replacement}/"
    shengOverride.config.systemd.services.sheng-devauth.serviceConfig.ExecStart;
  assert packages.devices.sheng.thp.stdenv.hostPlatform.system == "aarch64-linux";
  assert packages.devices.sheng.qrtr.version == "1.2";
  assert lib.hasInfix (builtins.unsafeDiscardStringContext "${replacement}/lib/firmware/qcom") (
    builtins.unsafeDiscardStringContext boardOverride.devices.sheng.initrd-firmware.buildCommand
  );
  assert packages.usb-signaller.stdenv.buildPlatform.system == buildSystem;
  assert packages.usb-signaller.stdenv.hostPlatform.system == "aarch64-linux";
  assert hostPackages.mobile-device.stdenv.hostPlatform.system == buildSystem;
  assert packages.usb-signaller.drvPath == flake.packages.${buildSystem}.usb-signaller.drvPath;
  assert hostPackages.mobile-device.drvPath == flake.packages.${buildSystem}.mobile-device.drvPath;
  assert plain.config.androidDevices.usb.signaller.package.drvPath == packages.usb-signaller.drvPath;
  assert overlaid.config.androidDevices.usb.signaller.package.packageScopeMarker;
  assert
    overlaid.config.androidDevices.usb.signaller.package.stdenv.buildPlatform.system == buildSystem;
  assert overlaid.config.androidDevices.kernelPackage.stdenv.buildPlatform.system == buildSystem;
  assert overlaid.config.androidDevices.kernelPackage.kernelScopeMarker;
  assert plain.config.androidDevices.kernelPackage.drvPath == packages.devices.polaris.kernel.drvPath;
  assert lib.hasPrefix "${replacement}/bin/usb-signaller"
    overridden.config.systemd.services.usb-signaller.serviceConfig.ExecStart;
  assert (dependencyOverride.mkUBoot { device = "polaris"; }).outPath == replacement.outPath;
  {
    target = packages.usb-signaller.stdenv.hostPlatform.system;
    host = hostPackages.mobile-device.stdenv.hostPlatform.system;
    usbSignaller = packages.usb-signaller.drvPath;
    mobileDevice = hostPackages.mobile-device.drvPath;
    camera = packages.libcamera.drvPath;
    initrdCollector = hostPackages.makeInitrdNGTool.drvPath;
    overlayOverride = true;
    moduleOverride = true;
    dependencyOverride = true;
    boardDependencyOverride = true;
  }
)
