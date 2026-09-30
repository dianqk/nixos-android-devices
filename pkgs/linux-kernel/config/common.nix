{ lib, configfile }:
let
  socDrivers = import ./qcom-soc-drivers.nix;
  # Start from the supplied baseline, including disabled symbols, so upstream
  # defaults cannot silently re-enable a driver already covered by the policy.
  pinctrlSymbols = lib.unique (
    lib.concatMap (
      line:
      let
        enabled = builtins.match "CONFIG_(PINCTRL_[A-Z0-9_]+)=.*" line;
        disabled = builtins.match "# CONFIG_(PINCTRL_[A-Z0-9_]+) is not set" line;
      in
      if enabled != null then
        enabled
      else if disabled != null then
        disabled
      else
        [ ]
    ) (lib.splitString "\n" (builtins.readFile configfile))
  );
in
lib.genAttrs (
  pinctrlSymbols
  ++ socDrivers.clocks
  ++ socDrivers.interconnects
  ++ [
    # Present in the pinned kernels but missing from Sheng's older baseline.
    # Kconfig defaults these to ARCH_QCOM, so omission does not disable them.
    "PINCTRL_ELIZA"
    "PINCTRL_HAWI"
    "PINCTRL_IPQ5210"
    "PINCTRL_IPQ9650"
    "PINCTRL_NORD"
    "PINCTRL_SHIKRA"
  ]
) (_: lib.kernel.no)
// {
  # All supported devices use Qualcomm TLMM and SPMI PMIC GPIO/MPP. Generic
  # pinmux/pinconf helpers are selected by these drivers and remain untouched.
  PINCTRL = lib.kernel.yes;
  PINCTRL_MSM = lib.kernel.yes;
  PINCTRL_QCOM_SPMI_PMIC = lib.kernel.yes;
}
