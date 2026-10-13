{
  callPackage,
  buildPackages,
  lib,
  linuxPackages_testing,
}:
{ device }:
let
  devices = import ./devices.nix;
  board = devices.${device} or (throw "Unsupported mobile kernel device: ${device}");
  socConfig = import (board + "/../config.nix") { inherit lib; };
  # Each device has exactly one kernel: the nixpkgs-provided release plus its queue.
  baseKernel = linuxPackages_testing.kernel;
  # The release every board queue is ported to. When nixpkgs moves, port all
  # queues to the new release and update this value; never pin a second kernel.
  expectedVersion = "7.3-rc6";
  boardFunction = import board;
  # Pass each board specification only the build inputs it declares.
  specification = boardFunction (
    builtins.intersectAttrs (builtins.functionArgs boardFunction) {
      inherit lib baseKernel;
      inherit (buildPackages)
        llvmPackages_23
        openssl
        elfutils
        zlib
        ;
    }
  );
in
assert lib.assertMsg (baseKernel.version == expectedVersion)
  "${device} patch queue targets Linux ${expectedVersion}, but the nixpkgs input provides ${baseKernel.version}. Port every device queue to the nixpkgs kernel and update expectedVersion in pkgs/linux-kernel/default.nix.";
((callPackage ./kernel-compat.nix { }) (
  specification
  // {
    patches = [
      ./patches/dpu-sm8650-dsc-full-ich-precision.patch
      ./patches/dsi-dsc-12-rc-model.patch
      ./patches/dsi-dsc-12-first-line.patch
      ./patches/usb-ncm-retry-busy-timer.patch
      ./patches/qcom-battmgr-default-charge-unit.patch
      ./patches/qcom-battmgr-serialize-notification-request.patch
    ]
    ++ (specification.patches or [ ]);
    # Baseline -> common reductions -> SoC requirements -> board exceptions.
    configOverrides =
      import ./config/common.nix {
        inherit lib;
        inherit (specification) configfile;
      }
      // socConfig
      // (specification.configOverrides or { });
  }
)).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      patchQueueStatus = {
        inherit expectedVersion;
        evaluatedVersion = baseKernel.version;
      };
    };
  })
