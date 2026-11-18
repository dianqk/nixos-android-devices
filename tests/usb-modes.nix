{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  let
    lib = flake.inputs.nixpkgs.lib;
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    };
    make =
      extra:
      (env.nixosSystem {
        modules = [
          flake.nixosModules.unicorn
          (flake.outPath + "/examples/unicorn/system.nix")
        ]
        ++ extra;
      }).config;
    base = make [ ];
    enabled = make [
      {
        users.users.alice.isNormalUser = true;
        androidDevices.usb.signaller = {
          mtp = {
            enable = true;
            user = "alice";
            directories = [ "/home/alice/USB-Share" ];
          };
          tethering.enable = true;
          hidTouch.enable = true;
          massStorage = {
            enable = true;
            image = "/var/lib/usb/disk.img";
          };
          uvc.enable = true;
        };
      }
    ];
    invalid = make [ { androidDevices.usb.signaller.mtp.enable = true; } ];
    invalidExtras = map (options: make [ { androidDevices.usb.signaller = options; } ]) [
      { massStorage.enable = true; }
      {
        massStorage = {
          enable = true;
          image = "relative.img";
        };
      }
      {
        uvc = {
          enable = true;
          source.type = "v4l2";
        };
      }
      {
        uvc = {
          enable = true;
          source.type = "libcamera";
        };
      }
    ];
    missingQueues = make [
      {
        users.users.alice.isNormalUser = true;
        androidDevices.usb.signaller.mtp = {
          enable = true;
          user = "alice";
          directories = [ "/home/alice/USB-Share" ];
        };
        androidDevices.kernelPackage = lib.mkForce (
          base.androidDevices.kernelPackage
          // {
            config = base.androidDevices.kernelPackage.config // {
              isYes = name: name != "POSIX_MQUEUE" && base.androidDevices.kernelPackage.config.isYes name;
            };
          }
        );
      }
    ];
    invalidDirectory =
      dir:
      make [
        {
          users.users.alice.isNormalUser = true;
          androidDevices.usb.signaller.mtp = {
            enable = true;
            user = "alice";
            directories = [ dir ];
          };
        }
      ];
    legacy = (env.nixosSystem { modules = [ flake.nixosModules.polaris ]; }).config;
  in
  assert base.androidDevices.usb.signaller.followRole;
  assert !legacy.androidDevices.usb.signaller.followRole;
  assert
    base.systemd.services.usb-signaller.environment.USB_SIGNALLER_MODES
    == "developer_mode,charging_only,host_mode";
  assert
    enabled.systemd.services.usb-signaller.environment.USB_SIGNALLER_MODES
    == "developer_mode,charging_only,host_mode,mtp_ffs_mode,tethering_mode,hid_touch_mode,mass_storage_mode,uvc_mode";
  assert !base.androidDevices.usb.signaller.massStorage.enable;
  assert !legacy.androidDevices.usb.signaller.hidTouch.enable;
  assert enabled.systemd.services.usb-signaller-touch-mode.serviceConfig.Type == "notify";
  assert enabled.systemd.services.usb-signaller-uvc-mode.wantedBy == [ ];
  assert
    (builtins.fromJSON enabled.environment.etc."usb-signaller/gadgets.json".text).storage.readOnly;
  assert enabled.systemd.services.usb-signaller.environment.USB_SIGNALLER_FOLLOW_ROLE == "1";
  assert builtins.elem (
    "mac:" + enabled.systemd.services.usb-signaller.environment.USB_SIGNALLER_DEV_ADDR
  ) enabled.networking.networkmanager.unmanaged;
  assert
    enabled.systemd.network.networks."10-mobile-usb".matchConfig.MACAddress
    == enabled.systemd.services.usb-signaller.environment.USB_SIGNALLER_DEV_ADDR;
  assert enabled.systemd.services.usb-signaller-mtp-mode.serviceConfig.User == "alice";
  assert enabled.systemd.services.usb-signaller-mtp-mode.serviceConfig.ProtectHome == "tmpfs";
  assert
    enabled.systemd.services.usb-signaller-mtp-mode.serviceConfig.BindPaths
    == [ "/home/alice/USB-Share" ];
  assert enabled.systemd.services.usb-signaller-mtp-mode.wantedBy == [ ];
  assert enabled.systemd.services.usb-signaller-tethering-mode.wantedBy == [ ];
  assert enabled.systemd.services.usb-signaller-mtp-mount.wantedBy == [ ];
  assert lib.hasInfix "USB-Share" enabled.environment.etc."usb-signaller/umtprd.conf".text;
  assert !(lib.hasInfix ''storage "/home"'' enabled.environment.etc."usb-signaller/umtprd.conf".text);
  assert !enabled.systemd.network.networks."10-mobile-usb".dhcpServerConfig.EmitRouter;
  assert !enabled.systemd.network.networks."10-mobile-usb".dhcpServerConfig.EmitDNS;
  assert lib.all (a: a.assertion) enabled.assertions;
  assert builtins.any (
    a: !a.assertion && lib.hasInfix "POSIX_MQUEUE" a.message
  ) missingQueues.assertions;
  assert !(lib.all (a: a.assertion) invalid.assertions);
  assert lib.all (cfg: !(lib.all (a: a.assertion) cfg.assertions)) invalidExtras;
  assert lib.all (dir: !(lib.all (a: a.assertion) (invalidDirectory dir).assertions)) [
    "/"
    "//"
    "/home/alice"
    "/home/alice/"
    "/home//alice"
    "/etc"
    "/home/alice/../private"
  ];
  {
    system = enabled.system.build.toplevel.drvPath;
    rules = enabled.networking.nftables.tables.mobile_usb.content;
    mtp = enabled.environment.etc."usb-signaller/umtprd.conf".text;
  }
)
