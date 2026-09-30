# Downstream configurations must work without importing examples or internal files.
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  devices = [
    "polaris"
    "asphalt"
    "clover"
    "sheng"
  ];
in
assert builtins.attrNames flake.nixosModules == lib.sort builtins.lessThan devices;
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    make =
      device: modules:
      (flake.lib.mkBuildEnvironment { inherit buildSystem; }).nixosSystem {
        modules = [
          flake.nixosModules.${device}
          {
            androidDevices.usbSerial = "api-${device}";
            androidDevices.persistentImage.rootfs.uuid = "11111111-2222-3333-4444-555555555555";
          }
        ]
        ++ modules;
      };
    valid =
      s:
      assert lib.all (a: a.assertion) s.config.assertions;
      s;
    console = valid (
      make "polaris" [
        ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/minimal.nix") ]; })
        {
          hardware.polaris.radio.enable = false;
          hardware.polaris.audio.enable = false;

          androidDevices.usb.ssh.enable = true;
        }
      ]
    );
    audioOnly = valid (
      make "polaris" [
        {
          hardware.polaris.radio.enable = false;
          hardware.polaris.audio.enable = true;
        }
      ]
    );
  in
  {
    devices = lib.genAttrs devices (
      device:
      let
        s = valid (make device [ ]);
        c = s.config;
        artifacts = flake.lib.mkArtifacts s;
        recovery = valid (make device [ { androidDevices.recovery.enable = true; } ]);
        plain = valid (make device [ { hardware.${device}.systemHostName = "my-${device}"; } ]);
      in
      assert builtins.hasAttr device s.options.hardware;
      assert lib.all (name: !(builtins.hasAttr name s.options.androidDevices)) devices;
      assert lib.all (name: name == device || !(builtins.hasAttr name s.options.hardware)) devices;
      assert !(s.options.hardware ? xiaomi-sheng);
      assert c.androidDevices.enable;
      assert c.androidDevices.deviceName == device;
      assert c.androidDevices.persistentImage.enable;
      assert !(s.options ? mobile);
      assert c.services.getty.autologinUser == null;
      assert !(c.users.users ? demo);
      assert !c.androidDevices.usb.ssh.enable;
      assert !c.services.openssh.enable;
      assert !(s.options.androidDevices ? desktop);
      assert plain.config.networking.hostName == "my-${device}";
      assert plain.config.androidDevices.recovery.targetHostName == "my-${device}";
      assert !plain.config.programs.sway.enable;
      assert !recovery.config.androidDevices.persistentImage.enable;
      assert !recovery.config.programs.sway.enable;
      assert !recovery.config.boot.loader.systemd-boot.enable;
      assert artifacts.system.system == "aarch64-linux";
      {
        system = artifacts.system.drvPath;
        boot = artifacts.boot.drvPath;
        rootfs = artifacts.rootfs.drvPath;
        bootstrap = artifacts.bootstrap-info.drvPath;
        camera = c.androidDevices.camera.package.drvPath;
        recovery = (flake.lib.mkArtifacts recovery).boot.drvPath;
      }
    );
    console =
      let
        c = console.config;
      in
      assert !(c.users.users ? demo);
      assert c.services.getty.autologinUser == null;
      assert !c.programs.sway.enable;
      assert !c.services.openssh.settings.PasswordAuthentication;
      assert !c.services.openssh.settings.PermitEmptyPasswords;
      assert c.services.openssh.settings.PermitRootLogin == "prohibit-password";
      assert c.users.users.root.hashedPassword != "";
      assert !(c.systemd.services ? polaris-rmtfs);
      assert !(c.systemd.services ? polaris-pd-mapper);
      assert builtins.length c.androidDevices.initrdFirmware == 1;
      assert map (a: a.addr) c.services.openssh.listenAddresses == [ "172.16.42.1" ];
      (flake.lib.mkArtifacts console).boot-files.drvPath;
    audioOnly =
      assert audioOnly.config.systemd.services ? polaris-pd-mapper;
      assert !(audioOnly.config.systemd.services ? polaris-rmtfs);
      assert audioOnly.config.systemd.services.polaris-pd-mapper.wantedBy == [ "multi-user.target" ];
      audioOnly.config.system.build.toplevel.drvPath;
  }
)
