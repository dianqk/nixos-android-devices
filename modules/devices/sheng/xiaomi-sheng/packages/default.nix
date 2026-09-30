# ---
# Module: Sheng Driver Packages
# Description: Aggregates fingerprint, THP, and pen-status driver packages
# Scope: System
# ---

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./fingerprint.nix
    ./thp.nix
    ./pen-status.nix
  ];
}
