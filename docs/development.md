# Build and validate changes

[Configuration guide](configuration.md) · [Kernel sources](../pkgs/linux-kernel/README.md)

The public API, platform, native-userspace, module-boundary, direct-boot and release-configuration
evaluations are registered in `checks` for both build platforms. `nix flake check` also runs
host-only image/fastboot and storage regression tests; it never contacts a device.

Run evaluation before building images. It checks configuration and derivation
construction without claiming hardware validation:

```sh
nix flake check --no-build --all-systems --option allow-import-from-derivation false
nix eval --impure --json --option allow-import-from-derivation false --expr '
  let f = builtins.getFlake ("git+file://" + toString ./.);
  in import (f.outPath + "/tests/public-api.nix") { flake = f; }
'
nix eval --impure --json --option allow-import-from-derivation false --expr '
  let f = builtins.getFlake ("git+file://" + toString ./.);
  in import (f.outPath + "/tests/eval-platforms.nix") { flake = f; }
'
```

The [package integration guide](packages.md) describes the shared scope and
consumer overrides. Evaluate `tests/package-scope.nix` with the same expression
above to check host/target selection, scope dependencies, optional overlays and
module package replacements.

The [module boundary guide](modules.md) describes where device policy belongs
and which explicit inputs the shared NixOS modules consume.

`public-api.nix` exercises independent downstream configurations. The platform
suite checks the packaged examples, recovery, optional hardware and native/cross
outputs. The UEFI and USB tests in `tests/` check their specific configuration
contracts. Evaluate one platform at a time on a memory-constrained computer by
selecting `.aarch64-linux` or `.x86_64-linux` from the returned attribute set.
For the full flake check, replace `--all-systems` with `--system aarch64-linux`
and then `--system x86_64-linux` in separate invocations to bound evaluation memory.

Enter `nix develop .#kernel` for native kernel tools and configured `ARCH=arm64`,
`LLVM=1`, and target compiler prefix. Kernels use LLVM 23; other
packages retain their Nixpkgs compiler. Use `environment.compilationPkgs` for
project device compilation and `environment.buildPackages` for initiating-host
tools. The package registry's `packaging` scope supplies host builders with
native target runtime references for scripts and prebuilt programs. Do not
replace upstream `pkgs` builders globally: their cache identities must remain
unchanged. The [build requirements](configuration.md#build-platforms-and-remote-builders)
cover QEMU fallback for uncached native ARM jobs.

`tests/native-userspace.nix` checks upstream derivation identities against plain
native Nixpkgs, host firmware/script/image assembly, target script interpreters,
selected compiler platforms, and all four devices' module selections.

Run [basic hardware tests](../tests/basic/README.md) explicitly on the intended
device. Evaluation, actual compilation, booting, and physical input/display
validation are separate results; test the configuration you intend to deploy.

Implementation references: [U-Boot](../pkgs/u-boot/README.md),
[USB package changes](../pkgs/usb-signaller/README.md), and device firmware sources:
[Asphalt](asphalt/README.md#firmware-sources),
[Clover](clover/README.md#firmware-sources),
[Polaris](polaris/README.md#firmware-sources),
[Sheng](sheng/README.md#firmware-sources).

## Recovery on a new board

First establish kernel/DTB and USB controller/PHY/device-role support, then
ACM shell (`androidDevices.initrdUsb.enable = true;` and
`androidDevices.initrdUsb.network.enable = false;`). Add
NCM/SSH after that. Both need working USB hardware; ACM cannot capture faults
before its gadget exists. The same module can be explicitly enabled in a
normal boot initrd. `androidDevices.initrdUsb.roleSwitch` reuses the board role-switch setting
and can be overridden for a new controller. Before switch-root it stops sessions and removes its
gadget functions, allowing stage 2 to take ownership. Normal systems should
use usb-signaller/SSH. Installed systems use NCM by default and can add an ACM login console.

Validate each board separately: evaluation, real image build, RAM boot, ACM,
NCM/DHCP/SSH, read-only mounts, offline generation update and reboot. Polaris
hardware validation does not establish the other boards' behavior.
