{
  androidDevices = {
    recovery.enable = true;
    recovery.minimal = false;
    initrdUsb = {
      enable = true;
      acm.enable = true;
      network.enable = true;
      address = "172.16.46.1/24";
    };
  };
  # Preserve firmware-owned clocks; their handoff is not verified on this board.
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
  ];
}
