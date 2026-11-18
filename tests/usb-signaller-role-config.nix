{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
    make =
      device: extra:
      (env.nixosSystem {
        modules = [
          flake.nixosModules.${device}
          extra
        ];
      }).config;
    t880 = make "t880" { };
    managed = make "t880" {
      androidDevices.usb.signaller.manageRole = true;
      androidDevices.usb.signaller.hostMode = true;
    };
    unmanaged = make "clover" {
      androidDevices.usb.signaller.manageRole = false;
      androidDevices.usb.signaller.hostMode = false;
    };
    defaults = make "clover" { };
    invalid = make "clover" { androidDevices.usb.signaller.manageRole = false; };
    legacy = lib.genAttrs [
      "polaris"
      "asphalt"
      "clover"
      "sheng"
      "aurora"
      "marble"
      "t880"
      "dodge"
    ] (device: make device { });
    stockPackage = env.pkgs.androidDevicePackages.usb-signaller;
    invalidExtended = make "t880" { androidDevices.usb.signaller.tethering.enable = true; };
    role = cfg: cfg.systemd.services.usb-signaller.environment.USB_SIGNALLER_MANAGE_ROLE;
  in
  # Existing boards must retain the stock upstream daemon unless they opt in.
  assert lib.all (c: c.androidDevices.usb.signaller.package.drvPath == stockPackage.drvPath) (
    builtins.attrValues legacy
  );
  assert !(lib.all (a: a.assertion) invalidExtended.assertions);
  assert defaults.systemd.services.usb-signaller.serviceConfig.Restart == "always";
  assert !(defaults.systemd.services.usb-signaller.serviceConfig ? ExecStopPost);
  assert role t880 == "0";
  assert
    t880.systemd.services.usb-signaller.environment.USB_SIGNALLER_MODES
    == "developer_mode,charging_only";
  assert role managed == "1";
  assert role unmanaged == "0";
  assert role defaults == "1";
  assert lib.all (a: a.assertion) t880.assertions;
  assert lib.all (a: a.assertion) unmanaged.assertions;
  assert !(lib.all (a: a.assertion) invalid.assertions);
  {
    inherit (t880.androidDevices.usb.signaller) manageRole hostMode;
    package = t880.androidDevices.usb.signaller.package.drvPath;
  }
)
