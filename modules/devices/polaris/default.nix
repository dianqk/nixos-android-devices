{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
{
  imports = [
    ../../mobile
    ./boot.nix
    ./video.nix
    ./hardware.nix
    ./radio.nix
    ./dsp.nix
    ./storage.nix
    ./audio.nix
    ./recovery.nix
  ];
  androidDevices = {
    enable = true;
    deviceName = "polaris";
    usbController = "a600000.usb";
    # Only the optional rootfs image consumes this UUID. First installation
    # formats userdata independently and mounts it by GPT partition name.
    persistentImage.rootfs.uuid = lib.mkOptionDefault (
      let
        hash = builtins.hashString "sha256" config.androidDevices.usbSerial;
        part = builtins.substring;
      in
      "${part 0 8 hash}-${part 8 4 hash}-4${part 13 3 hash}-8${part 17 3 hash}-${part 20 12 hash}"
    );
    # Built-in drivers request these before switching to the installed system.
    initrdFirmware = [
      androidPackages.devices.polaris.gpu-firmware
    ]
    ++ lib.optionals config.hardware.polaris.radio.enable [
      pkgs.wireless-regdb
      androidPackages.devices.polaris.bluetooth-firmware
      androidPackages.devices.polaris.ipa-firmware
    ];
    earlyKernelParams = [
      "earlycon=msm_geni_serial,0xA84000"
      "console=ttyMSM0,115200n8"
      "loglevel=8"
    ];
    hardwareKernelParams = [
      "androidboot.usbcontroller=a600000.dwc3"
      "androidboot.boot_devices=soc/1d84000.ufshc"
    ];
  };
  hardware.firmware = [
    androidPackages.devices.polaris.gpu-firmware
  ]
  ++ lib.optionals config.hardware.polaris.radio.enable [
    androidPackages.devices.polaris.bluetooth-firmware
    androidPackages.devices.polaris.wifi-firmware
    androidPackages.devices.polaris.ipa-firmware
  ]
  ++ lib.optional config.hardware.polaris.audio.enable (
    androidPackages.devices.polaris.multimedia-firmware
  );
}
