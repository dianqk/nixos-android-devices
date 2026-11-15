# Keep upstream userspace native, while project compilation and packaging
# use the initiating host. Packaging preserves native target runtime references.
{
  pkgs,
  compilationPkgs ? pkgs.androidDevicePackages.compilationPkgs or pkgs,
}:
let
  packaging = import ../lib/packaging.nix { inherit pkgs compilationPkgs; };
  compiledCall =
    scope:
    compilationPkgs.newScope (
      builtins.removeAttrs scope [
        "callPackage"
        "callPackages"
        "newScope"
        "overrideScope"
        "packages"
      ]
    );
in
pkgs.lib.makeScope packaging.newScope (
  self:
  let
    compile = compiledCall self;
  in
  {
    inherit compilationPkgs packaging;
    inherit (packaging) buildPackages pkgsBuildBuild;

    usb-signaller = compile ./usb-signaller {
      # Compile project code with the selected toolchain, but retain native
      # target cache paths for libsystemd and the installed command references.
      inherit (pkgs) systemd util-linux;
    };
    mobile-boot-action = compile ./mobile-boot-action { };
    # Android executes the statically linked Linux ABI without Bionic or Nix.
    boot-choice-native = compilationPkgs.pkgsStatic.callPackage ./boot-choice-native { };
    boot-selector-builder = compile ./boot-selector-builder {
      inherit (packaging) runCommand;
      inherit (packaging.buildPackages) python3 makeWrapper android-tools;
    };
    boot-choice-template = compile ./boot-choice-template {
      inherit (packaging) runCommand;
      inherit (self) boot-selector-builder boot-choice-efi;
      firmware = self.mkUBoot { device = "dodge"; };
    };
    boot-choice-template-diagnostic = self.boot-choice-template.override { diagnosticStages = true; };
    boot-choice-kernelsu-diagnostic = self.boot-choice-kernelsu.override {
      boot-choice-template = self.boot-choice-template-diagnostic;
    };
    boot-choice-kernelsu = compile ./boot-choice-kernelsu {
      inherit (packaging) runCommand;
      inherit (packaging.pkgsBuildBuild)
        python3
        nodejs
        binutils
        gnutar
        gzip
        ;
      inherit (self) boot-choice-native boot-choice-template;
      firmware = self.mkUBoot { device = "dodge"; };
      inherit (pkgs) gnu-efi;
    };
    boot-choice-efi = compile ./boot-choice-efi {
      # Target static firmware CRT/libraries are architecture-only; reuse native
      # AArch64 GNU-EFI instead of rebuilding it in the cross scope.
      inherit (pkgs) gnu-efi;
    };
    mobile-charger = compile ./mobile-charger { };
    mobile-device = self.callPackage ./mobile-device { };
    # Patched upstream camera runtime, like VA: keep target GStreamer/library
    # cache identities rather than rebuilding their cross dependency closure.
    libcamera = pkgs.callPackage ./libcamera { };
    # Keep the VA driver and its graphics dependencies native to the target,
    # including in mixed native-userspace / cross-kernel build environments.
    libva-v4l2 = pkgs.callPackage ./libva-v4l2 { };
    # QTEE userspace (minkipc) and the modem's IMinkModemOpener bridge; native
    # to the target like other upstream system software.
    qcbor = pkgs.callPackage ./qcom-tee/qcbor.nix { };
    qcomtee = pkgs.callPackage ./qcom-tee/qcomtee.nix { inherit (self) qcbor; };
    mink-idl-compiler = pkgs.callPackage ./qcom-tee/mink-idl-compiler.nix { };
    minkipc = pkgs.callPackage ./qcom-tee/minkipc.nix {
      inherit (self) qcbor qcomtee mink-idl-compiler;
    };
    mink-modem-opener = pkgs.callPackage ./qcom-tee/mink-modem-opener {
      inherit (self) minkipc mink-idl-compiler;
    };
    qmi-framework = pkgs.callPackage ./qcom-tee/qmi-framework.nix { };
    # Unfree Qualcomm prebuilt; not exported as a flake package.
    qwesd = pkgs.callPackage ./qcom-tee/qwesd.nix {
      inherit (self) minkipc qcbor qmi-framework;
    };
    ffmpeg = compile ./mobile/ffmpeg.nix { inherit (compilationPkgs) ffmpeg; };
    pd-mapper = compile ./mobile/pd-mapper.nix { };
    fastrpc = compile ./mobile/fastrpc { inherit (pkgs) systemdLibs libbsd libyaml; };
    mkSSCRegistry = args: self.callPackage ./mobile/ssc-registry args;
    mkFirmwareArchive = self.callPackage ./mobile/firmware-archive.nix { };
    sensor-rotate = self.callPackage ./mobile/sensor-rotate { };
    audio-orientation = self.callPackage ./mobile/audio-orientation { };
    umtp-responder = compile ./mobile/umtp-responder.nix { };
    # Upstream handles dlopen SONAME alternatives; use the unmodified host tool.
    inherit (packaging.buildPackages) makeInitrdNGTool;

    mkAndroidBootImage = self.callPackage ./mobile/android-boot-image.nix { };
    mkRecoveryFit = self.callPackage ./mobile/recovery-fit.nix { };
    mkRootfsImage = self.callPackage ./mobile/rootfs-image.nix { pkgs = packaging; };
    mkKernel = compile ./linux-kernel { };
    mkUBoot = compile ./u-boot {
      inherit (packaging) runCommand;
      packagingTools = packaging.buildPackages;
    };
    mkRecoveryScreen = args: compile ./mobile-recovery-screen args;
    mkRecoveryUtils = args: self.callPackage ./mobile-recovery-utils.nix args;
    mkCrossEfl = args: self.callPackage ./mobile/cross-efl.nix args;
    mobile-tqftpserv = compile ./mobile/tqftpserv.nix {
      # Cross-compile the daemon while retaining native target cache identities.
      inherit (pkgs) qrtr zstd systemdLibs;
    };
    # MediaTek CCCI modem userspace, native to the target like other system
    # software: the modem owner and ModemManager with the MediaTek SoC plugin.
    mtk-ccci-userspace = pkgs.callPackage ./mtk-ccci-userspace { };
    modemmanager-mtk-soc = pkgs.callPackage ./modemmanager/mtk-soc.nix { };

    devices = {
      dodge = pkgs.lib.makeScope self.newScope (device: {
        kernel = self.mkKernel { device = "dodge"; };
        firmware-source = device.callPackage ./dodge/firmware-source.nix { };
        firmware = device.callPackage ./dodge/firmware.nix { };
      });
      aurora = pkgs.lib.makeScope self.newScope (device: {
        kernel = self.mkKernel { device = "aurora"; };
        firmware-source = device.callPackage ./aurora/firmware-source.nix { };
        firmware = device.callPackage ./aurora/firmware.nix {
          inherit (packaging.pkgsBuildBuild) python3 alsa-utils m4;
          # Copied UCM files exec target coreutils: take them from the target set.
          inherit (pkgs) alsa-ucm-conf;
          runtimeAlsaUtils = pkgs.alsa-utils;
          runtimeCoreutils = pkgs.coreutils;
          inherit (pkgs) runtimeShell;
        };
        touch = compile ./aurora/touch { inherit (device) firmware-source; };
      });
      polaris = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "polaris"; };
          firmware-source = device.callPackage ./polaris/firmware-source.nix { };
          wifi-firmware = device.callPackage ./polaris/wifi-firmware.nix { };
          gpu-firmware = device.callPackage ./polaris/gpu-firmware.nix { };
          ipa-firmware = device.callPackage ./polaris/ipa-firmware.nix { };
          bluetooth-firmware = device.callPackage ./polaris/bluetooth-firmware.nix { };
          multimedia-firmware = device.callPackage ./polaris/multimedia-firmware.nix { };
          sensors = device.callPackage ./polaris/sensors { };
          alsa-ucm = device.callPackage ./polaris/alsa-ucm.nix { };
          ffmpeg = compile ./polaris/ffmpeg.nix { inherit (self) ffmpeg; };
          rmtfs = compile ./polaris/rmtfs.nix { inherit (compilationPkgs) rmtfs; };
        }
      );
      asphalt = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "asphalt"; };
          firmware-source = device.callPackage ./asphalt/firmware-source.nix { };
          firmware = device.callPackage ./asphalt/firmware.nix { };
          sensors = device.callPackage ./asphalt/sensors { };
          wifi-firmware = device.callPackage ./asphalt/wifi-firmware.nix { };
          audio-topology = device.callPackage ./asphalt/audio-topology.nix { };
          alsa-ucm = device.callPackage ./asphalt/alsa-ucm.nix { };
          ffmpeg = compile ./asphalt/ffmpeg.nix { inherit (self) ffmpeg; };
        }
      );
      clover = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "clover"; };
          firmware-source = device.callPackage ./clover/firmware-source.nix { };
          firmware = device.callPackage ./clover/firmware.nix { inherit (packaging.buildPackages) python3; };
          msm-firmware-loader = device.callPackage ./clover/msm-firmware-loader.nix {
            python3 = packaging.buildPackages.python3;
            runtimeShell = pkgs.runtimeShell;
          };
          alsa-ucm = device.callPackage ./clover/alsa-ucm.nix { };
          pd-mapper = compile ./clover/pd-mapper.nix { pd-mapper = self.pd-mapper; };
          tqftpserv = compile ./clover/tqftpserv.nix { };
        }
      );
      marble = pkgs.lib.makeScope self.newScope (device: {
        kernel = self.mkKernel { device = "marble"; };
        firmware-source = device.callPackage ./marble/firmware-source.nix { };
        firmware = device.callPackage ./marble/firmware.nix {
          inherit (packaging.pkgsBuildBuild) python3;
        };
        audio-topology = device.callPackage ./marble/audio-topology.nix { };
        alsa-ucm = device.callPackage ./marble/alsa-ucm.nix { };
      });
      t880 = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "t880"; };
          gpu-firmware = device.callPackage ./t880/gpu-firmware.nix { };
          firmware-source = device.callPackage ./t880/firmware-source.nix { };
          firmware = device.callPackage ./t880/firmware.nix { };
          # Out-of-tree connsys modules, built with the kernel's toolchain.
          connectivity-modules = compile ./t880/connectivity { inherit (device) kernel; };
        }
      );
      sheng = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "sheng"; };
          firmware-source = device.callPackage ./sheng/firmware-source.nix { };
          mipps-auth = device.callPackage ./sheng/xiaomi-mipps-auth.nix { };
          firmware = device.callPackage ./sheng/firmware.nix { };
          initrd-firmware = device.callPackage ./sheng/initrd-firmware.nix {
            sheng-firmware = device.firmware;
          };
          # Copied UCM files exec target coreutils: take them from the target set.
          alsa-ucm = device.callPackage ./sheng/alsa-ucm.nix {
            inherit (pkgs) alsa-ucm-conf;
          };
          fastrpc = self.fastrpc;
          qrtr = compile ./sheng/qrtr.nix { };
          sensors-file = device.callPackage ./sheng/sheng-sensors-file.nix { };
          devauth = device.callPackage ./sheng/devauth.nix { };
          thp = compile ./sheng/thp.nix {
            inherit (pkgs) glib libssc;
          };
          fingerprint-source = device.callPackage ./sheng/fingerprint-source.nix { };
          fingerprint-ta = device.callPackage ./sheng/fingerprint-ta.nix { };
          pen-status = compilationPkgs.libsForQt5.callPackage ./sheng/pen-status.nix (
            pkgs.lib.optionalAttrs (compilationPkgs.stdenv.buildPlatform != compilationPkgs.stdenv.hostPlatform)
              {
                inherit (pkgs.libsForQt5)
                  qtbase
                  qtsvg
                  qtwebsockets
                  qtx11extras
                  ;
                buildQtbase = compilationPkgs.pkgsBuildBuild.libsForQt5.qtbase;
                mkDerivation = compilationPkgs.stdenv.mkDerivation;
                wrapQtAppsHook = compilationPkgs.libsForQt5.wrapQtAppsHook.override {
                  inherit (pkgs.libsForQt5) qtbase qtwayland;
                  makeBinaryWrapper = compilationPkgs.makeBinaryWrapper.override {
                    cc = compilationPkgs.stdenv.cc;
                  };
                };
              }
          );
          fingerprint = device.callPackage ./sheng/fingerprint-runtime.nix {
            shengFingerprint = device.fingerprint-source;
          };
          mkLibfprint =
            args:
            compile ./sheng/fingerprint-libfprint.nix (
              {
                libfprint = compilationPkgs.libfprint.override {
                  inherit (pkgs)
                    gusb
                    pixman
                    glib
                    cairo
                    libgudev
                    openssl
                    ;
                };
                shengFingerprint = device.fingerprint-source;
              }
              // args
            );
          libfprint = device.mkLibfprint { };
          fprintd =
            (compilationPkgs.fprintd.override {
              libfprint = device.libfprint;
              inherit (pkgs)
                glib
                polkit
                nss
                pam
                systemdLibs
                ;
            }).overrideAttrs
              (
                old:
                pkgs.lib.optionalAttrs (compilationPkgs.stdenv.buildPlatform != compilationPkgs.stdenv.hostPlatform)
                  {
                    # Meson's gnome.gdbus_codegen must execute on the build machine.
                    nativeBuildInputs = old.nativeBuildInputs ++ [ compilationPkgs.pkgsBuildBuild.glib ];
                    # The upstream PAM-test helper is target code and is unused
                    # when the cross build cannot execute its test suite.
                    env = builtins.removeAttrs old.env [ "LIBRARY_PATH" ];
                  }
              );
        }
      );
    };
  }
)
