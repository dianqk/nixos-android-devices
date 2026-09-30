{
  callPackage,
  buildPackages,
  fetchFromGitHub,
  lib,
  linuxPackages_testing,
}:
{ device, variant ? null }:
let
  devices = import ./devices.nix;
  board = devices.${device} or (throw "Unsupported mobile kernel device: ${device}");
  mainline = (device == "sheng" && (variant == null || variant == "mainline"))
    || (device == "clover" && variant == "mainline");
  testingSheng = device == "sheng" && variant == "testing";
  socConfig = import (board + "/../config.nix") { inherit lib; };
  baseKernel = linuxPackages_testing.kernel;
  expectedVersion = "7.3-rc5";
  specification = import (if mainline then board + "/mainline.nix" else board) (
    {
      inherit lib;
      llvmPackages_23 = buildPackages.llvmPackages_23;
      openssl = buildPackages.openssl;
    }
    // (if mainline then { inherit fetchFromGitHub; } else { inherit baseKernel; })
  );
in
assert lib.assertMsg (variant == null || mainline || testingSheng)
  "Unsupported ${device} kernel variant: ${toString variant}";
assert lib.assertMsg (mainline || baseKernel.version == expectedVersion)
  "${device} patch queue requires Linux ${expectedVersion}; pinned nixpkgs now provides ${baseKernel.version}. Port the queue before changing kernel versions.";
(callPackage ./kernel-compat.nix { }) (
  specification
  // {
    # Baseline -> common reductions -> SoC requirements -> board exceptions.
    configOverrides =
      import ./config/common.nix {
        inherit lib;
        inherit (specification) configfile;
      }
      // socConfig
      // (specification.configOverrides or { });
  }
)
