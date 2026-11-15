{ lib }:
# SM7475 (Snapdragon 7+ Gen 2) is an SM8475 derivative: the kernel uses the
# SM8475 pin controller and the SM8450 clock, interconnect and display drivers.
import ../sm8475/config.nix { inherit lib; }
