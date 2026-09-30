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
    mobile-device = self.callPackage ./mobile-device { };
    libcamera = compile ./libcamera { inherit (compilationPkgs) libcamera; };
    pd-mapper = compile ./mobile/pd-mapper.nix { };
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
      polaris = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "polaris"; };
          mkRecoveryTools = device.callPackage ./polaris/recovery-tools.nix { };
          mkSystemUpdater = device.callPackage ./polaris/system-updater.nix { };
          mkBootInstaller = device.callPackage ./polaris/boot-installer.nix { };
          wifi-firmware = device.callPackage ./polaris/wifi-firmware.nix { };
          gpu-firmware = device.callPackage ./polaris/gpu-firmware.nix { };
          ipa-firmware = device.callPackage ./polaris/ipa-firmware.nix { };
          bluetooth-firmware = device.callPackage ./polaris/bluetooth-firmware.nix { };
          multimedia-firmware = device.callPackage ./polaris/multimedia-firmware.nix { };
          alsa-ucm = device.callPackage ./polaris/alsa-ucm.nix { };
          ffmpeg = compile ./polaris/ffmpeg.nix { inherit (compilationPkgs) ffmpeg; };
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
          mkRecoveryTools = device.callPackage ./asphalt/recovery-tools.nix { };
          firmware-source = device.callPackage ./asphalt/firmware-source.nix { };
          firmware = device.callPackage ./asphalt/firmware.nix { };
          disabled-dtbo = device.callPackage ./asphalt/disabled-dtbo.nix { };
          wifi-firmware = device.callPackage ./asphalt/wifi-firmware.nix { };
          audio-topology = device.callPackage ./asphalt/audio-topology.nix { };
          alsa-ucm = device.callPackage ./asphalt/alsa-ucm.nix { };
          ffmpeg = compile ./asphalt/ffmpeg.nix { inherit (compilationPkgs) ffmpeg; };
        }
      );
      clover = pkgs.lib.makeScope self.newScope (
        device:
        let
          compile = compiledCall (self // device);
        in
        {
          kernel = self.mkKernel { device = "clover"; };
          kernel-mainline = self.mkKernel {
            device = "clover";
            variant = "mainline";
          };
          mkRecoveryTools = device.callPackage ./clover/recovery-tools.nix { };
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
          kernel-mainline = self.mkKernel {
            device = "sheng";
            variant = "mainline";
          };
          kernel-testing = self.mkKernel {
            device = "sheng";
            variant = "testing";
          };
          firmware-source = device.callPackage ./sheng/firmware-source.nix { };
          mipps-auth = device.callPackage ./sheng/xiaomi-mipps-auth.nix { };
          mkRecoveryTools = device.callPackage ./sheng/recovery-tools.nix { };
          firmware = device.callPackage ./sheng/firmware.nix { };
          initrd-firmware = device.callPackage ./sheng/initrd-firmware.nix {
            sheng-firmware = device.firmware;
          };
          alsa-ucm = device.callPackage ./sheng/alsa-ucm.nix {
            inherit (packaging.buildPackages) alsa-ucm-conf;
          };
          fastrpc = compile ./sheng/fastrpc.nix { };
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
