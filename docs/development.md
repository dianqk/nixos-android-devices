# Build and validate changes

[Configuration guide](configuration.md) · [Kernel sources](../pkgs/linux-kernel/README.md) · [中文](development.zh.md)

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
consumer overrides. The `package-scope` check (`tests/package-scope.nix`)
covers host/target selection, scope dependencies, optional overlays and module
package replacements.

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
selected compiler platforms, and all five devices' module selections (including
experimental Aurora).

Run [basic hardware tests](../tests/basic/README.md) explicitly on the intended
device. Evaluation, actual compilation, booting, and physical input/display
validation are separate results; test the configuration you intend to deploy.

Implementation references: [U-Boot](../pkgs/u-boot/README.md),
[USB package changes](../pkgs/usb-signaller/README.md), and device firmware sources:
[Asphalt](asphalt/README.md#firmware-sources),
[Clover](clover/README.md#firmware-sources),
[Polaris](polaris/README.md#firmware-sources),
[Sheng](sheng/README.md#firmware-sources),
[Aurora](aurora/firmware.md).

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

## Kernel patch queues

Each device kernel is an upstream Linux tag plus an ordered patch queue
checked in under `pkgs/linux-kernel/`. The checked-in queue is the build input;
`tools/kernel-queue.py` converts it to and from Git branches for editing. It
requires Git, Nix, Python 3, GNU patch and tar.

Fetch the upstream release tag into any kernel Git repository:

```sh
git init linux
git -C linux remote add upstream https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
git -C linux fetch --depth=1 upstream tag v7.3-rc6
git -C linux show v7.3-rc6
```

Check the tag identity against the selected Nix source before importing. The
`v7.3-rc6` tag object is `4eeccbed21e50c19f97be9d325511f3de6343f2d`, commit
`a90ee4305c4a5df72c11b31dacfdc76e00fcf78a`; the extracted source has recursive
SHA256 `sha256-310GZztrJw+mkRFQ3IQ1pvTafElqHVKU0HMcZDk1x2c=`. Fetching a signed
tag alone does not establish signature trust; verify it with a trusted
maintainer key when available.

Import a device queue as the branch `android/<release>/<device>` and verify it:

```sh
python3 tools/kernel-queue.py import --repo ../linux --device aurora \
  --version 7.3-rc6 --base v7.3-rc6
python3 tools/kernel-queue.py verify --repo ../linux --device aurora \
  --version 7.3-rc6 --base v7.3-rc6
```

Use the release that `pkgs/linux-kernel/default.nix` expects for the device;
see the [kernel status](../pkgs/linux-kernel/README.md). The helper evaluates
the derivation's ordered queue, imports one commit per patch and replays the
queue independently to compare Git trees. It refuses an existing branch, an
incompatible base or a queue whose expected version differs. Mail patches keep
their author, date, message and trailers; a bare diff is attributed to the
importing user. Import manifests live in `.git/android-queues/`. If an import
fails, inspect the partial branch before removing it; the helper does not reset
existing work.

Edit the branch with ordinary Git (for example `git rebase -i v7.3-rc6`).
Preserve authors, upstream links and review/sign-off trailers, and describe
local adaptations separately. Then export to a new directory:

```sh
python3 tools/kernel-queue.py export --repo ../linux --device aurora \
  --version 7.3-rc6 --base v7.3-rc6 --output ../export-aurora
```

Review the exported patches, copy each to its existing shared or board-owned
path under `pkgs/linux-kernel/`, and update the Nix patch list when order or
membership changes. Do not duplicate shared patches into board folders. Run
`verify` again; it must match the edited branch.

For incremental out-of-tree builds, `prepare --source-identity <nix-source-path>`
creates a separate `android-prepared/<release>/<device>` branch that adds the
Nixpkgs source preparation. Never export preparation commits into a queue.
Git-tree verification does not compile the kernel or establish hardware
behavior; release builds always use the checked-in queue through Nix.
