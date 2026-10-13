# Downstream configurations must work without importing examples or internal files.
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  devices = [
    "polaris"
    "asphalt"
    "clover"
    "sheng"
    "aurora"
  ];
  noShellBackendOrPython =
    c:
    let
      initrd = c.boot.initrd.systemd;
      utils = c.system.build.mobileRecoveryUtils;
      inputs =
        map toString initrd.initrdBin
        ++ map (p: toString (p.source or p)) initrd.storePaths
        ++ map toString (builtins.attrValues initrd.extraBin)
        ++ map toString initrd.packages;
    in
    lib.all (name: !(initrd.contents ? ${name})) [
      "/etc/mobile-initial-install-adapter"
      "/etc/mobile-recovery-target"
      "/etc/recovery-help"
    ]
    && !(initrd.services ? mobile-recovery-store)
    && lib.all (word: !(lib.hasInfix word utils.buildCommand)) [
      "mobile-recovery-deploy"
      "recovery-tools"
      "recovery-impl"
      "mobile-install-initial"
    ]
    && lib.all (p: !(lib.hasInfix "python" p)) inputs
    && builtins.elem "recovery-daemon" c.androidDevices.recovery.screenPackage.buildFeatures;
in
assert builtins.attrNames flake.nixosModules == lib.sort builtins.lessThan (devices ++ [ "host" ]);
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    make =
      device: modules:
      (flake.lib.mkBuildEnvironment {
        inherit buildSystem;
        # Aurora includes proprietary OEM firmware even without demo policy.
        config.allowUnfreePredicate =
          package:
          builtins.elem (lib.getName package) [
            "aurora-firmware"
            "aurora-firmware-zstd"
            "aurora-touch"
            "qwesd"
          ];
      }).nixosSystem
        {
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
      assert !plain.config.programs.sway.enable && !plain.config.programs.niri.enable;
      assert !recovery.config.androidDevices.recovery.minimal;
      assert recovery.config.boot.initrd.systemd.services ? mobile-recovery-screen;
      # Every full recovery is a client of the Rust daemon: no project shell
      # backend, store socket service or Python in its initrd.
      assert recovery.config.boot.initrd.systemd.services ? mobile-recovery-daemon;
      assert noShellBackendOrPython recovery.config;
      assert
        (builtins.fromJSON recovery.config.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text)
        .slot_model == (if builtins.elem device [ "polaris" "clover" ] then "single" else "ab");
      # The installed system carries the single-slot storage contract.
      assert
        builtins.elem device [ "polaris" "clover" ]
        == lib.hasInfix "mobile-storage-roles.json" c.system.systemBuilderCommands;
      assert !recovery.config.androidDevices.persistentImage.enable;
      assert !recovery.config.programs.sway.enable && !recovery.config.programs.niri.enable;
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
    aurora =
      let
        s = valid (
          make "aurora" [
            {
              androidDevices.recovery = {
                enable = true;
                minimal = true;
              };
              androidDevices.initrdUsb = {
                enable = true;
                acm.enable = true;
                network.enable = false;
              };
            }
          ]
        );
        c = s.config;
        initrd = c.boot.initrd.systemd;
        full = (valid (make "aurora" [ { androidDevices.recovery.enable = true; } ])).config;
        installed = (valid (make "aurora" [ ])).config;
        modemSystem = valid (make "aurora" [ { hardware.aurora.modem.enable = true; } ]);
        modem = modemSystem.config;
        # hardware.firmware applies to a merged environment; inspect its definitions.
        firmwareInputs = s: lib.flatten s.options.hardware.firmware.definitions;
        fullSystem = valid (make "aurora" [ { androidDevices.recovery.enable = true; } ]);
        rmtfs = modem.systemd.services.modem-rmtfs;
        mpss = modem.systemd.services.modem-mpss;
        supplicant = modem.systemd.services.qtee-supplicant;
        qwesdModem =
          (valid (
            make "aurora" [
              {
                hardware.aurora.modem = {
                  enable = true;
                  license.qwesd = true;
                };
              }
            ]
          )).config;
        tracedModem =
          (valid (
            make "aurora" [
              {
                hardware.aurora.modem.enable = true;
                androidDevices.qtee = {
                  supplicant.debug = true;
                  modemOpener.trace = true;
                  modemOpener.transportTrace = true;
                };
              }
            ]
          )).config;
        modemFirmware = modem.hardware.aurora.firmwarePackage.modem;
        recoveryModem = make "aurora" [
          {
            androidDevices.recovery.enable = true;
            hardware.aurora.modem.enable = true;
          }
        ];
      in
      # Modem support is opt-in, read-only for NV data and absent from recovery.
      assert !(installed.systemd.services ? modem-rmtfs);
      assert builtins.elem "ipa" installed.boot.blacklistedKernelModules;
      assert !(builtins.elem "ipa" modem.boot.blacklistedKernelModules);
      assert builtins.elem modemFirmware (firmwareInputs modemSystem);
      assert !(builtins.elem modemFirmware full.androidDevices.initrdFirmware);
      assert !(builtins.elem modemFirmware (firmwareInputs fullSystem));
      assert modem.networking.modemmanager.enable;
      # Aurora supplies its device data to the shared modem module.
      assert modem.androidDevices.modem.enable;
      assert modem.androidDevices.modem.remoteproc == "4080000.remoteproc";
      assert
        modem.androidDevices.modem.nvPartitions == [
          "modemst1"
          "modemst2"
          "fsg"
          "fsc"
        ];
      assert !installed.androidDevices.modem.enable;
      # The modem module's ModemManager carries the netlink use-after-free fix.
      assert lib.any (lib.hasSuffix "netlink-transaction-use-after-free.patch") (
        map toString modem.networking.modemmanager.package.patches
      );
      assert
        (valid (
          make "aurora" [
            {
              hardware.aurora.modem.enable = true;
              androidDevices.modem.startAtBoot = true;
            }
          ]
        )).config.systemd.services.modem-mpss.wantedBy == [ "multi-user.target" ];
      # rmtfs never starts or stops MPSS; modem-mpss does, after the license services.
      assert lib.hasSuffix " -P -v -r" rmtfs.serviceConfig.ExecStart;
      assert rmtfs.serviceConfig.Restart == "no";
      assert rmtfs.wantedBy == [ ];
      assert mpss.wantedBy == [ ];
      assert builtins.elem "modem-rmtfs.service" mpss.requires;
      assert lib.hasSuffix " stop" mpss.serviceConfig.ExecStop;
      assert builtins.elem "mink-modem-opener.service" mpss.after;
      assert builtins.elem "mink-modem-opener.service" modem.systemd.services.modem-tqftpserv.after;
      # Restarting the supplicant must not restart the bridge; switches restart neither.
      assert builtins.elem "qtee-supplicant.service" modem.systemd.services.mink-modem-opener.wants;
      assert !(builtins.elem "qtee-supplicant.service" modem.systemd.services.mink-modem-opener.requires);
      assert lib.all (u: !modem.systemd.services.${u}.restartIfChanged) [
        "modem-mpss"
        "modem-rmtfs"
        "modem-tqftpserv"
        "qtee-supplicant"
        "mink-modem-opener"
      ];
      # MPSS waits for the clock, then pulls in SIM provisioning and ModemManager.
      assert mpss.serviceConfig ? ExecStartPre;
      assert builtins.elem "ModemManager.service" mpss.wants;
      assert builtins.elem "modem-sim-provision.service" mpss.wants;
      assert builtins.elem "ModemManager.service" modem.systemd.services.modem-sim-provision.before;
      # QTEE reads Android's persist path: bind only persist/data there.
      assert modem.fileSystems."/mnt/vendor/persist/data".device == "/persist/data";
      assert builtins.elem "bind" modem.fileSystems."/mnt/vendor/persist/data".options;
      assert !(modem.fileSystems ? "/mnt/vendor/persist");
      # QTEE may write only its license store on persist.
      assert modem.fileSystems."/persist".device == "/dev/disk/by-partlabel/persist";
      assert lib.all (o: builtins.elem o modem.fileSystems."/persist".options) [
        "nodev"
        "nosuid"
        "noexec"
      ];
      assert
        supplicant.serviceConfig.ReadWritePaths == [
          "/persist/data/pfm"
          "/mnt/vendor/persist/data/pfm"
        ];
      # The unfree qwesd is opt-in; when enabled it runs offline before MPSS.
      assert !(modem.systemd.services ? qwesd);
      assert builtins.elem "qwesd.service" qwesdModem.systemd.services.modem-mpss.after;
      assert !qwesdModem.systemd.services.qwesd.restartIfChanged;
      assert qwesdModem.systemd.services.qwesd.serviceConfig.Restart == "no";
      assert
        qwesdModem.systemd.services.qwesd.serviceConfig.RestrictAddressFamilies == [
          "AF_UNIX"
          "AF_QIPCRTR"
        ];
      # Tracing and listener debug logs are opt-in.
      assert !(lib.hasInfix "--trace" modem.systemd.services.mink-modem-opener.serviceConfig.ExecStart);
      assert lib.hasInfix "--trace --transport-trace"
        tracedModem.systemd.services.mink-modem-opener.serviceConfig.ExecStart;
      assert
        tracedModem.systemd.services.qtee-supplicant.serviceConfig.ExecStart
        != supplicant.serviceConfig.ExecStart;
      assert
        supplicant.serviceConfig.ReadOnlyPaths == [
          "/persist"
          "/mnt/vendor/persist/data"
        ];
      assert !(installed.fileSystems ? "/persist");
      assert !(full.systemd.services ? qtee-supplicant);
      assert builtins.elem "/dev/disk/by-partlabel/modemst1 r" rmtfs.serviceConfig.DeviceAllow;
      assert builtins.elem "modem-tqftpserv.service" rmtfs.requires;
      assert modem.systemd.services.modem-tqftpserv.serviceConfig.StateDirectory == "tqftpserv";
      assert lib.any (a: !a.assertion) recoveryModem.config.assertions;
      assert full.boot.initrd.systemd.contents ? "/etc/mobile-recovery.json";
      assert !(full.boot.initrd.systemd.services ? mobile-recovery-store);
      assert !(full.boot.initrd.systemd.contents ? "/etc/mobile-initial-install-adapter");
      assert
        full.boot.initrd.systemd.services.mobile-recovery-daemon.serviceConfig.KillMode == "control-group";
      assert full.boot.initrd.systemd.services ? mobile-recovery-screen;
      assert installed.boot.loader.systemd-boot.enable;
      assert installed.fileSystems."/".device == "/dev/disk/by-partlabel/linux";
      assert installed.fileSystems."/boot".device == "/dev/disk/by-partlabel/linux-boot";
      assert !c.androidDevices.persistentImage.enable;
      assert !(initrd.services ? mobile-recovery-screen);
      assert !(initrd.services ? mobile-recovery-store);
      assert !(initrd.services ? mobile-recovery-sshd);
      assert initrd.services ? mobile-recovery-console;
      assert initrd.services ? mobile-recovery-ready;
      assert !(initrd.contents ? "/etc/mobile-initial-install-adapter");
      assert lib.all (p: !(lib.hasInfix "recovery-utils" (lib.getName p))) initrd.initrdBin;
      assert c.androidDevices.kernelPackage.stdenv.buildPlatform.system == buildSystem;
      assert c.androidDevices.kernelPackage.stdenv.hostPlatform.system == "aarch64-linux";
      (flake.lib.mkArtifacts s).boot.drvPath;
    console =
      let
        c = console.config;
      in
      assert !(c.users.users ? demo);
      assert c.services.getty.autologinUser == null;
      assert !c.programs.sway.enable && !c.programs.niri.enable;
      assert !c.services.openssh.settings.PasswordAuthentication;
      assert !c.services.openssh.settings.PermitEmptyPasswords;
      assert c.services.openssh.settings.PermitRootLogin == "prohibit-password";
      assert c.users.users.root.hashedPassword != "";
      assert !(c.systemd.services ? modem-rmtfs);
      assert !(c.systemd.services ? polaris-pd-mapper);
      assert builtins.length c.androidDevices.initrdFirmware == 1;
      assert map (a: a.addr) c.services.openssh.listenAddresses == [ "172.16.42.1" ];
      (flake.lib.mkArtifacts console).boot-files.drvPath;
    polarisRadio =
      let
        c =
          (valid (
            make "polaris" [
              {
                hardware.polaris.radio.snapshotDirectory = "/var/lib/polaris-radio-snapshot";
              }
            ]
          )).config;
        rmtfs = c.systemd.services.modem-rmtfs;
      in
      # Polaris keeps rmtfs -s on its read-only snapshot through the shared module.
      assert lib.hasSuffix " -s -r -o /var/lib/polaris-radio-snapshot" rmtfs.serviceConfig.ExecStart;
      assert rmtfs.wantedBy == [ "multi-user.target" ];
      assert rmtfs.serviceConfig.ReadOnlyPaths == [ "/var/lib/polaris-radio-snapshot" ];
      assert builtins.elem "polaris-diag-router.service" rmtfs.requires;
      assert !(c.systemd.services ? modem-mpss);
      assert !(c.systemd.services ? modem-sim-provision);
      assert !c.networking.modemmanager.enable;
      c.system.build.toplevel.drvPath;
    audioOnly =
      assert audioOnly.config.systemd.services ? polaris-pd-mapper;
      assert !(audioOnly.config.systemd.services ? modem-rmtfs);
      assert audioOnly.config.systemd.services.polaris-pd-mapper.wantedBy == [ "multi-user.target" ];
      audioOnly.config.system.build.toplevel.drvPath;
  }
)
