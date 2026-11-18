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
    "unicorn"
  ];
  # Experimental boards checked separately (no installed-system baseline).
  experimentalDevices = [
    "t880"
    "marble"
    "dodge"
  ];
  allDevices = devices ++ experimentalDevices;
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
assert
  builtins.attrNames flake.nixosModules == lib.sort builtins.lessThan (allDevices ++ [ "host" ]);
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    make =
      device: modules:
      (flake.lib.mkBuildEnvironment {
        inherit buildSystem;
        # These boards include proprietary OEM firmware even without demo policy.
        config.allowUnfreePredicate =
          package:
          builtins.elem (lib.getName package) [
            "unicorn-firmware"
            "unicorn-firmware-zstd"
            "aurora-firmware"
            "aurora-firmware-zstd"
            "aurora-touch"
            "marble-firmware"
            "marble-firmware-zstd"
            "dodge-firmware"
            "dodge-firmware-zstd"
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
      assert lib.all (name: !(builtins.hasAttr name s.options.androidDevices)) allDevices;
      assert lib.all (name: name == device || !(builtins.hasAttr name s.options.hardware)) allDevices;
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
        .slot_model == (
          if
            builtins.elem device [
              "polaris"
              "clover"
            ]
          then
            "single"
          else
            "ab"
        );
      # The installed system carries the single-slot storage contract.
      assert
        builtins.elem device [
          "polaris"
          "clover"
        ] == lib.hasInfix "mobile-storage-roles.json" c.system.systemBuilderCommands;
      assert !recovery.config.androidDevices.persistentImage.enable;
      assert !recovery.config.programs.sway.enable && !recovery.config.programs.niri.enable;
      assert !recovery.config.boot.loader.systemd-boot.enable;
      # Boards whose PMIC RTC is enabled but read-only restore the clock from a
      # saved offset in the installed system only.
      assert
        c.androidDevices.clock.rtcOffset.enable == builtins.elem device [
          "aurora"
          "clover"
          "polaris"
        ];
      assert c.androidDevices.clock.rtcOffset.enable == (c.systemd.services ? rtc-offset-restore);
      assert !recovery.config.androidDevices.clock.rtcOffset.enable;
      # Reboot arguments survive the pivot into the shutdown ramfs.
      assert c.systemd.shutdownRamfs.enable -> c.systemd.shutdown ? reboot-param;
      # The derivation executes on buildSystem; its configured host stays AArch64.
      assert artifacts.system.system == buildSystem;
      assert artifacts.system.stdenv.hostPlatform.system == "aarch64-linux";
      {
        system = artifacts.system.drvPath;
        boot = artifacts.boot.drvPath;
        rootfs = artifacts.rootfs.drvPath;
        bootstrap = artifacts.bootstrap-info.drvPath;
        camera = c.androidDevices.camera.package.drvPath;
        recovery = (flake.lib.mkArtifacts recovery).boot.drvPath;
      }
    );
    t880 =
      let
        s = valid (make "t880" [ ]);
        c = s.config;
        plain = valid (make "t880" [ { hardware.t880.systemHostName = "my-t880"; } ]);
        recovery = valid (
          make "t880" [
            {
              androidDevices.recovery = {
                enable = true;
                minimal = true;
              };
            }
          ]
        );
        r = recovery.config;
        image = r.system.build.mobileBootImage;
        full = (valid (make "t880" [ { androidDevices.recovery.enable = true; } ])).config;
        fullJson = builtins.fromJSON full.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
      in
      assert builtins.hasAttr "t880" s.options.hardware;
      assert lib.all (name: !(builtins.hasAttr name s.options.androidDevices)) allDevices;
      assert lib.all (name: name == "t880" || !(builtins.hasAttr name s.options.hardware)) allDevices;
      assert c.androidDevices.deviceName == "t880";
      assert c.androidDevices.persistentImage.enable;
      assert !c.androidDevices.usb.ssh.enable && !c.services.openssh.enable;
      assert c.systemd.shutdownRamfs.enable -> c.systemd.shutdown ? reboot-param;
      assert c.boot.loader.systemd-boot.enable;
      assert c.system.build.mobileBootImage.drvPath == c.androidDevices.boot.firmwarePackage.drvPath;
      assert plain.config.networking.hostName == "my-t880";
      assert plain.config.androidDevices.recovery.targetHostName == "my-t880";
      # RAM recovery is a FIT in the ramdisk of the same U-Boot boot image.
      assert r.androidDevices.boot.recoveryLoader == "u-boot-fit";
      assert image.firmware.drvPath == c.androidDevices.boot.firmwarePackage.firmware.drvPath;
      assert lib.hasSuffix ".itb" image.payload.name;
      assert !(r.boot.initrd.systemd.services ? mobile-recovery-screen);
      assert !(r.boot.initrd.systemd.services ? mobile-recovery-daemon);
      assert r.boot.initrd.systemd.services ? mobile-initrd-usb;
      assert !r.boot.loader.systemd-boot.enable;
      # Full recovery: Rust daemon and screen UI with the slot-A userdata split.
      assert !full.androidDevices.recovery.minimal;
      assert full.boot.initrd.systemd.services ? mobile-recovery-screen;
      assert full.boot.initrd.systemd.services ? mobile-recovery-daemon;
      assert c.boot.initrd.kernelModules == [ ];
      assert
        lib.sort builtins.lessThan full.boot.initrd.kernelModules == lib.sort builtins.lessThan [
          "tcpci_mt6375"
          "whs3844"
          "mtk-usb-dp-selector"
          "fsa4480"
        ];
      assert noShellBackendOrPython full;
      assert fullJson.slot_model == "mediatek-a";
      assert fullJson.slot_metadata == "aosp-boot-control";
      assert !(fullJson ? recovery_bytes);
      assert fullJson.serial_prefix == "T880";
      # LK recovery mode hands over to U-Boot USB fastboot for RAM recovery.
      assert fullJson.recovery_reboot_argument == "recovery";
      {
        system = (flake.lib.mkArtifacts s).system.drvPath;
        boot = c.system.build.mobileBootImage.drvPath;
        recovery = image.drvPath;
        payload = image.payload.drvPath;
      };
    dodge =
      let
        recovery = valid (make "dodge" [ { androidDevices.recovery.enable = true; } ]);
        c = recovery.config;
        json = builtins.fromJSON c.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
      in
      assert builtins.hasAttr "dodge" recovery.options.hardware;
      assert !c.androidDevices.recovery.minimal;
      assert !c.androidDevices.recovery.screen.enable;
      assert !(c.boot.initrd.systemd.services ? mobile-recovery-screen);
      assert c.boot.initrd.systemd.services ? mobile-recovery-daemon;
      # Nixpkgs only supports systemd initrd; its former enable toggle is removed.
      assert c.boot.initrd.enable;
      assert c.boot.initrd.systemd.services ? mobile-initrd-usb;
      assert c.boot.initrd.systemd.services ? mobile-recovery-sshd;
      assert !c.androidDevices.initrdUsb.ssh.hostKeyStorage.enable;
      assert noShellBackendOrPython c;
      assert builtins.elem "ab-partitions" c.androidDevices.recovery.screenPackage.buildFeatures;
      assert json.slot_model == "ab" && json.slot_metadata == "qcom-gpt";
      assert json.compatible == "oneplus,dodge";
      assert json.controller == "1d84000.ufs" && json.misc_bytes == 1048576;
      assert c.androidDevices.usbController == "a600000.usb";
      assert c.androidDevices.boot.recoveryLoader == "fit";
      assert c.androidDevices.boot.recoveryFitMaximumBytes == 67108864;
      assert c.system.build.mobileBootImage.drvPath == c.system.build.mobileRecoveryFit.drvPath;
      {
        recovery = c.system.build.mobileRecoveryFit.drvPath;
        initrd = c.system.build.initialRamdisk.drvPath;
        daemon = c.androidDevices.recovery.screenPackage.drvPath;
      };
    marble =
      let
        s = valid (make "marble" [ ]);
        c = s.config;
        plain = valid (make "marble" [ { hardware.marble.systemHostName = "my-marble"; } ]);
        audio = valid (make "marble" [ { hardware.marble.audio.enable = true; } ]);
        sensors = (valid (make "marble" [ { hardware.marble.sensors.enable = true; } ])).config;
        r = (valid (make "marble" [ { androidDevices.recovery.enable = true; } ])).config;
        image = r.system.build.mobileBootImage;
        json = builtins.fromJSON r.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
      in
      assert builtins.hasAttr "marble" s.options.hardware;
      assert lib.all (name: !(builtins.hasAttr name s.options.androidDevices)) allDevices;
      assert lib.all (name: name == "marble" || !(builtins.hasAttr name s.options.hardware)) allDevices;
      assert c.androidDevices.deviceName == "marble";
      # Stock firmware: out (early boot, installed initrd only) and dsp; no modem.
      assert
        let
          firmware = c.hardware.marble.firmwarePackage;
          installed = map (p: p.outPath) (lib.flatten s.options.hardware.firmware.definitions);
        in
        builtins.elem firmware.outPath installed
        && builtins.elem firmware.dsp.outPath installed
        && !builtins.elem firmware.modem.outPath installed
        && !builtins.elem firmware.audio.outPath installed;
      # Audio (off by default): speaker ACF, AudioReach topology and UCM.
      assert
        let
          a = audio.config;
          installed = map (p: p.outPath) (lib.flatten audio.options.hardware.firmware.definitions);
        in
        builtins.elem a.hardware.marble.firmwarePackage.audio.outPath installed
        && builtins.any (lib.hasInfix "marble-audioreach-topology") installed
        && lib.hasInfix "marble-alsa-ucm" a.environment.variables.ALSA_CONFIG_UCM2
        &&
          a.systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2
          == a.environment.variables.ALSA_CONFIG_UCM2;
      # Sensors (off by default): sdsp listener on the firmware's sensors
      # output, which carries the SSC registry.
      assert !c.androidDevices.sensors.enable && !(c.systemd.services ? android-ssc-sensors);
      assert
        sensors.androidDevices.sensors.rpcDomain == "sdsp"
        &&
          sensors.androidDevices.sensors.dataPackage.outPath
          == sensors.hardware.marble.firmwarePackage.sensors.outPath
        && sensors.hardware.marble.firmwarePackage.hasSensorRegistry
        && sensors.systemd.services ? android-ssc-sensors;
      # Suspend (unverified): wakeup sources declared, policy off, kernel's
      # mem_sleep default unless memSleep is set.
      assert
        lib.all (n: c.androidDevices.power.wakeup.sources ? ${n}) [
          "powerKey"
          "rtc"
          "battery"
          "modem"
          "mobileData"
          "adsp"
          "sensors"
          "thermal"
          "wifi"
        ]
        && !c.androidDevices.power.wakeup.enable
        && !(c.systemd.tmpfiles.settings ? "10-marble-ufs-spm")
        && !lib.any (lib.hasPrefix "mem_sleep_default=") c.androidDevices.hardwareKernelParams;
      assert builtins.elem "mem_sleep_default=s2idle"
        (valid (make "marble" [ { hardware.marble.suspend.memSleep = "s2idle"; } ]))
        .config.androidDevices.hardwareKernelParams;
      assert
        (valid (make "marble" [ { hardware.marble.suspend.ufsSpmLevel = 3; } ]))
        .config.systemd.tmpfiles.settings."10-marble-ufs-spm"."/sys/devices/platform/soc@0/1d84000.ufshc/spm_lvl".w.argument
        == "3";
      assert !builtins.elem "regulator_ignore_unused" c.boot.kernelParams;
      assert builtins.elem "regulator_ignore_unused" r.boot.kernelParams;
      assert builtins.elem "regulator_ignore_unused"
        (valid (make "marble" [ { hardware.marble.ignoreUnusedRegulators = true; } ]))
        .config.boot.kernelParams;
      assert !builtins.elem "clk_ignore_unused" c.boot.kernelParams;
      assert !builtins.elem "pd_ignore_unused" c.boot.kernelParams;
      assert builtins.elem "clk_ignore_unused" r.boot.kernelParams;
      assert builtins.elem "pd_ignore_unused" r.boot.kernelParams;
      assert builtins.elem "pd_ignore_unused"
        (valid (make "marble" [ { hardware.marble.ignoreUnusedClocksAndDomains = true; } ]))
        .config.boot.kernelParams;
      assert
        !builtins.elem "regulator_ignore_unused"
          (valid (make "marble" [ { hardware.marble.ignoreUnusedRegulators = false; } ]))
          .config.boot.kernelParams;
      assert c.androidDevices.initrdFirmware == [ c.hardware.marble.firmwarePackage ];
      assert r.androidDevices.initrdFirmware == [ ];
      assert c.boot.loader.systemd-boot.enable;
      assert c.system.build.mobileBootImage.drvPath == c.androidDevices.boot.firmwarePackage.drvPath;
      # The board's U-Boot has no boot-action protocol: no slot/BCB/PON actions.
      assert
        !c.androidDevices.boot.actions.bootloader
        && !c.androidDevices.boot.actions.recovery
        && !c.androidDevices.boot.actions.android;
      assert plain.config.networking.hostName == "my-marble";
      assert plain.config.androidDevices.recovery.targetHostName == "my-marble";
      # RAM recovery is a FIT in the ramdisk of the same U-Boot boot image.
      assert r.androidDevices.boot.recoveryLoader == "u-boot-fit";
      assert image.firmware.drvPath == c.androidDevices.boot.firmwarePackage.firmware.drvPath;
      assert lib.hasSuffix ".itb" image.payload.name;
      assert r.boot.initrd.systemd.services ? mobile-recovery-screen;
      assert r.boot.initrd.systemd.services ? mobile-recovery-daemon;
      assert noShellBackendOrPython r;
      assert builtins.elem "ab-partitions" r.androidDevices.recovery.screenPackage.buildFeatures;
      assert json.slot_model == "ab";
      assert json.slot_metadata == "qcom-gpt";
      assert json.compatible == "xiaomi,marble" && json.firmware_compatible == "xiaomi,marble";
      assert json.controller == "1d84000.ufshc";
      {
        system = (flake.lib.mkArtifacts s).system.drvPath;
        boot = c.system.build.mobileBootImage.drvPath;
        recovery = image.drvPath;
        payload = image.payload.drvPath;
      };
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
        thermalLimit =
          (valid (make "aurora" [ { androidDevices.charging.thermalLimit.enable = true; } ]))
          .config.systemd.services.charge-thermal-limit;
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
      assert lib.hasInfix "sched_util_clamp_min_rt_default = 0"
        installed.environment.etc."sysctl.d/60-android-rt-util-clamp.conf".text;
      # Charge current cap inputs are set, writes stay a consumer choice.
      assert !installed.androidDevices.charging.thermalLimit.enable;
      assert !(installed.systemd.services ? charge-thermal-limit);
      assert lib.hasSuffix "/qcom-battmgr-bat/constant_charge_current"
        thermalLimit.environment.CHARGE_THERMAL_CURRENT_FILE;
      assert thermalLimit.environment.CHARGE_THERMAL_DEFAULT == "22000000";
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
      # The clock wait also accepts a clock restored from the RTC offset.
      assert builtins.elem "rtc-offset-restore.service" mpss.after;
      assert lib.all (u: builtins.elem u modem.systemd.services.rtc-offset-restore.before) [
        "time-set.target"
        "systemd-timesyncd.service"
      ];
      assert
        modem.systemd.paths.rtc-offset-save.pathConfig.PathChanged == "/run/systemd/timesync/synchronized";
      assert lib.hasSuffix "save rtc0" modem.systemd.services.rtc-offset-shutdown.serviceConfig.ExecStop;
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
