{ config, lib, ... }:
let
  cfg = config.hardware.unicorn.display;
  rates = [ 60 120 90 40 30 24 ];
  mask = lib.foldl' (acc: rate:
    acc + (if builtins.elem rate cfg.seamless.refreshRates then
      builtins.elemAt [ 1 2 4 8 16 32 ] (lib.lists.findFirstIndex (r: r == rate) 0 rates)
    else 0)) 0 rates;
  # Avoid implicit changes to the installed configuration and RAM recovery.
  active = !config.androidDevices.recovery.enable;
in
{
  options.hardware.unicorn.display = {
    seamless.enable = lib.mkEnableOption "experimental active panel refresh switching";
    seamless.refreshRates = lib.mkOption {
      type = lib.types.listOf (lib.types.enum rates);
      default = [ 60 120 ];
      description = "Rates allowed on the experimental fast path; expand after device verification.";
    };
    idleRefreshRate = lib.mkOption {
      type = lib.types.enum [ 0 10 1 ];
      default = 0;
      description = "Experimental panel idle refresh at 120 Hz logical mode; zero disables it.";
    };
  };
  config = lib.mkMerge [
    {
      assertions = [{
        assertion = !cfg.seamless.enable ||
          (builtins.length (lib.unique cfg.seamless.refreshRates) >= 2 &&
           builtins.length cfg.seamless.refreshRates == builtins.length (lib.unique cfg.seamless.refreshRates));
        message = "Unicorn seamless switching requires at least two distinct refresh rates.";
      }];
    }
    (lib.mkIf active {
      boot.kernelParams =
        lib.optionals cfg.seamless.enable [
          "panel_xiaomi_l2s_380c0a.seamless=1"
          "panel_xiaomi_l2s_380c0a.seamless_mask=${toString mask}"
        ] ++ lib.optional (cfg.idleRefreshRate != 0)
          "panel_xiaomi_l2s_380c0a.idle_hz=${toString cfg.idleRefreshRate}";
    })
  ];
}
