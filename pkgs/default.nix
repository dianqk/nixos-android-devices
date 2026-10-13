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
    inherit (packaging) buildPackages;

    usb-signaller = compile ./usb-signaller { };
    mobile-boot-action = compile ./mobile-boot-action { };
    mobile-charger = compile ./mobile-charger { };
    mobile-device = self.callPackage ./mobile-device { };
    libcamera = compile ./libcamera { inherit (compilationPkgs) libcamera; };
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
    fastrpc = compile ./mobile/fastrpc { };
    mkSSCRegistry = args: self.callPackage ./mobile/ssc-registry args;
    sensor-rotate = self.callPackage ./mobile/sensor-rotate { };
    umtp-responder = compile ./mobile/umtp-responder.nix { };
    makeInitrdNGTool = self.callPackage ./make-initrd-ng {
      inherit (packaging.buildPackages) makeInitrdNGTool;
    };

    mkAndroidBootImage = self.callPackage ./mobile/android-boot-image.nix { };
    mkRootfsImage = self.callPackage ./mobile/rootfs-image.nix { pkgs = packaging; };
    mkKernel = compile ./linux-kernel { };
    mkUBoot = compile ./u-boot {
      inherit (packaging) runCommand;
      packagingTools = packaging.buildPackages;
    };
    mkRecoveryScreen = args: compile ./mobile-recovery-screen args;
    mkRecoveryUtils = args: self.callPackage ./mobile-recovery-utils.nix args;
    mkCrossEfl = args: self.callPackage ./mobile/cross-efl.nix args;
    mobile-tqftpserv = compile ./mobile/tqftpserv.nix { };

    devices = {
      aurora = pkgs.lib.makeScope self.newScope (device: {
        kernel = self.mkKernel { device = "aurora"; };
        firmware-source = device.callPackage ./aurora/firmware-source.nix { };
        firmware = device.callPackage ./aurora/firmware.nix {
          inherit (packaging.buildPackages) python3 alsa-utils alsa-ucm-conf m4;
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
          alsa-ucm = device.callPackage ./sheng/alsa-ucm.nix {
            inherit (packaging.buildPackages) alsa-ucm-conf;
          };
          fastrpc = self.fastrpc;
          qrtr = compile ./sheng/qrtr.nix { };
          sensors-file = device.callPackage ./sheng/sheng-sensors-file.nix { };
          devauth = device.callPackage ./sheng/devauth.nix { };
          thp = compile ./sheng/thp.nix { };
          fingerprint-source = device.callPackage ./sheng/fingerprint-source.nix { };
          fingerprint-ta = device.callPackage ./sheng/fingerprint-ta.nix { };
          pen-status = compilationPkgs.libsForQt5.callPackage ./sheng/pen-status.nix { };
          fingerprint = device.callPackage ./sheng/fingerprint-runtime.nix {
            shengFingerprint = device.fingerprint-source;
          };
          mkLibfprint =
            args:
            compile ./sheng/fingerprint-libfprint.nix (
              {
                inherit (compilationPkgs) libfprint;
                shengFingerprint = device.fingerprint-source;
              }
              // args
            );
          libfprint = device.mkLibfprint { };
          fprintd = compilationPkgs.fprintd.override { libfprint = device.libfprint; };
        }
      );
    };
  }
)
