{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/minimal.nix") ];
  # Build on the host; retain Nix and switch-to-configuration for USB updates.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };
  system.tools = {
    nixos-build-vms.enable = false;
    nixos-enter.enable = false;
    nixos-generate-config.enable = false;
    nixos-install.enable = false;
    nixos-option.enable = false;
    nixos-rebuild.enable = false;
  };
}
