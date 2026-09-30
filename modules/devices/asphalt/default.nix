{
  imports = [
    ../../mobile
    ./boot.nix
    ./radio.nix
    ./video.nix
    ./hardware.nix
    ./firmware.nix
    ./audio
    ./recovery.nix
  ];
  androidDevices = {
    enable = true;
    deviceName = "asphalt";
    usbController = "a600000.usb";
    earlyKernelParams = [
      "console=ttyMSM0,115200n8"
      "loglevel=8"
    ];
    hardwareKernelParams = [
      "androidboot.usbcontroller=a600000.usb"
      "androidboot.boot_devices=soc/1d84000.ufshc"
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];
  };
}
