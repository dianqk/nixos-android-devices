{ lib, ... }:
let
  battery = "/sys/class/power_supply/qcom-battmgr-bat";
  # m°C, m°C, µA
  step = trip: clear: current: { inherit trip clear current; };
in
{
  # Inputs only; the cap writes stay disabled until verified on hardware.
  # Steps follow the stock HyperOS thermal-chg-only.conf battery stage
  # (CHG-ONLY-SIC-BAT), whose 33.5-41.5 °C PI range (10-5 A) is stepped
  # here. Stock controls a weighted skin estimate in which the battery
  # dominates; only the battery temperature is available here. The default is
  # the stock thermal_fcc_override default.
  androidDevices.charging.thermalLimit = {
    currentFile = lib.mkDefault "${battery}/constant_charge_current";
    sensors = lib.mkDefault [
      {
        path = "${battery}/temp";
        multiplier = 100;
      }
    ];
    steps = lib.mkDefault [
      (step 15000 14000 15600000)
      (step 33500 33000 10000000)
      (step 35000 34500 7500000)
      (step 36500 36000 5000000)
      (step 41500 41000 3000000)
      (step 44500 44000 1500000)
      (step 45000 44500 500000)
    ];
    defaultCurrent = lib.mkDefault 22000000;
  };
}
