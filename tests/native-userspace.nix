# Upstream userspace stays native; repository compilation and packaging follow
# the selected builder. Test actual module selections as well as the registry.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];
  environments = lib.genAttrs systems (
    buildSystem:
    flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    }
  );
  native = environments.aarch64-linux.pkgs;
  upstream = import flake.inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
  };
  check =
    expected: package:
    assert package.stdenv.buildPlatform.system == expected;
    assert package.stdenv.hostPlatform.system == "aarch64-linux";
    package.drvPath;
in
lib.genAttrs systems (
  buildSystem:
  let
    env = environments.${buildSystem};
    p = env.pkgs.androidDevicePackages;
  in
  {
    upstream =
      lib.genAttrs
        [
          "bash"
          "coreutils"
          "systemd"
          "glibc"
          "niri"
          "foot"
          "ffmpeg"
          "mpv-unwrapped"
          "celluloid"
        ]
        (
          name:
          assert env.pkgs.${name}.drvPath == upstream.${name}.drvPath;
          check "aarch64-linux" env.pkgs.${name}
        );
    compiled = lib.genAttrs [
      "usb-signaller"
      "mobile-boot-action"
      "libcamera"
      "pd-mapper"
      "umtp-responder"
      "mobile-tqftpserv"
    ] (name: check buildSystem p.${name});
    devices = lib.genAttrs [ "polaris" "asphalt" "clover" "sheng" "aurora" ] (
      device:
      let
        n = env.nixosSystem {
          modules = [
            flake.nixosModules.${device}
            (flake.outPath + "/examples/${device}/system.nix")
          ];
        };
        c = n.config;
        boot = c.system.build.mobileBootImage;
        recovery = env.nixosSystem {
          modules = [
            flake.nixosModules.${device}
            (flake.outPath + "/examples/${device}/recovery.nix")
          ];
        };
      in
      {
        kernel = check buildSystem c.androidDevices.kernelPackage;
        uboot = check buildSystem boot.firmware;
        image = check buildSystem boot;
        screen = check buildSystem recovery.config.androidDevices.recovery.screenPackage;
        tools = check buildSystem recovery.config.system.build.mobileRecoveryUtils;
        bash =
          assert n.pkgs.bash.drvPath == native.bash.drvPath;
          check "aarch64-linux" n.pkgs.bash;
      }
    );
    data = {
      firmware = check buildSystem p.devices.sheng.firmware;
      devauth = check buildSystem p.devices.sheng.devauth;
      sensorConfig = check buildSystem p.devices.sheng.sensors-file;
      ucm = check buildSystem p.devices.asphalt.alsa-ucm;
      script =
        let
          script = p.packaging.writeShellScript "target-script" "true";
        in
        assert script.system == buildSystem;
        assert lib.hasPrefix "#!${upstream.runtimeShell}\n" script.text;
        assert p.buildPackages.bash.system == buildSystem;
        script.drvPath;
    };
    deviceCompilation = {
      ffmpeg = check buildSystem p.devices.asphalt.ffmpeg;
      rmtfs = check buildSystem p.devices.polaris.rmtfs;
      thp = check buildSystem p.devices.sheng.thp;
      fastrpc = check buildSystem p.devices.sheng.fastrpc;
      qrtr = check buildSystem p.devices.sheng.qrtr;
      pen = check buildSystem p.devices.sheng.pen-status;
      libfprint = check buildSystem p.devices.sheng.libfprint;
      fprintd = check buildSystem p.devices.sheng.fprintd;
    };
    hostTools =
      assert env.buildPackages.stdenv.hostPlatform.system == buildSystem;
      env.buildPackages.android-tools.drvPath;
  }
)
