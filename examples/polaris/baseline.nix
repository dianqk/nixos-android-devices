{ lib, ... }:
{
  # Example only. Choose a unique serial for each physical phone.
  androidDevices.usbSerial = lib.mkDefault "polaris-example";
}
