{ pkgs, ... }:
{
  # Public device modules instantiate this scope from the consumer's pkgs.
  # An optional overlay can supply an overridden scope; no overlay is required.
  _module.args.androidPackages = pkgs.androidDevicePackages or (import ../../pkgs { inherit pkgs; });
}
