{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  system:
  let
    make =
      settings:
      lib.nixosSystem {
        inherit system;
        modules = [
          flake.nixosModules.host
          {
            system.stateVersion = "26.11";
            networking.hostName = "development-host-test";
            users.users.developer.isNormalUser = true;
          }
          settings
        ];
      };
    disabled = (make { }).config;
    enabled = make {
      androidDevices.host = {
        enable = true;
        users = [ "developer" ];
        adb.extraDeviceIds = [ "18d1:d00d" ];
        usb = {
          consoleSerials = [ "test-console" ];
          disableAutosuspend = [ "18d1:d00d" ];
          networks = {
            test-usb = {
              mac = "02:00:00:00:00:01";
              uuid = "11111111-2222-3333-4444-555555555555";
            };
            static-usb = {
              mac = "02:00:00:00:00:02";
              uuid = "11111111-2222-3333-4444-666666666666";
              address = "192.0.2.2/24";
            };
          };
        };
      };
      networking.networkmanager.enable = true;
    };
    c = enabled.config;
    packages = map lib.getName c.environment.systemPackages;
    profiles = c.networking.networkmanager.ensureProfiles.profiles;
    connectionOnly = (make { androidDevices.host.usb.enable = true; }).config;
    noNetworkManager =
      (make {
        androidDevices.host.usb = {
          enable = true;
          networks.test = {
            mac = "02:00:00:00:00:01";
            uuid = "11111111-2222-3333-4444-555555555555";
          };
        };
      }).config;
  in
  assert !(enabled.options.androidDevices ? deviceName);
  assert !(disabled.users.groups ? adbusers);
  assert disabled.networking.networkmanager.ensureProfiles.profiles == { };
  assert !lib.elem "mobile-device" (map lib.getName disabled.environment.systemPackages);
  assert !lib.elem "mobile-device" (map lib.getName connectionOnly.environment.systemPackages);
  assert !connectionOnly.networking.networkmanager.enable;
  assert lib.all (name: lib.elem name packages) [
    "mobile-device"
    "android-tools"
    "dtc"
    "picocom"
    "iperf"
  ];
  assert lib.all (group: lib.elem group c.users.users.developer.extraGroups) [
    "adbusers"
    "dialout"
  ];
  assert profiles.test-usb.ipv4.method == "auto";
  assert profiles.static-usb.ipv4.method == "manual";
  assert profiles.static-usb.ipv4.address1 == "192.0.2.2/24";
  assert lib.all (
    p:
    p.ipv4.never-default
    && p.ipv4.ignore-auto-dns
    && p.ipv4.ignore-auto-routes
    && !(p.connection ? interface-name)
  ) (builtins.attrValues profiles);
  assert lib.hasInfix ''ATTR{serial}=="test-console", ENV{ID_MM_DEVICE_IGNORE}="1"''
    c.services.udev.extraRules;
  assert lib.hasInfix ''GROUP="adbusers"'' c.services.udev.extraRules;
  assert lib.elem "usbcore.quirks=18d1:d00d:k" c.boot.kernelParams;
  assert c.services.tlp.settings.USB_DENYLIST == "18d1:d00d";
  assert !c.services.tlp.enable;
  assert lib.any (
    a: !a.assertion && lib.hasPrefix "androidDevices.host.usb.networks requires" a.message
  ) noNetworkManager.assertions;
  assert lib.all
    (p: p.stdenv.buildPlatform.system == system && p.stdenv.hostPlatform.system == system)
    (
      lib.filter (
        p:
        lib.elem (lib.getName p) [
          "mobile-device"
          "android-tools"
          "dtc"
          "picocom"
        ]
      ) c.environment.systemPackages
    );
  {
    inherit packages;
    independentModule = true;
    profiles = builtins.attrNames profiles;
    nativeTools = true;
    disabledIsInert = true;
  }
)
