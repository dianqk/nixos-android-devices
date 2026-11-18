# Build and validate changes

[Configuration guide](configuration.md) · [Kernel sources](../pkgs/linux-kernel/README.md) · [中文](development.zh.md)

## just commands

Run `just` to list the [justfile](../justfile) commands. They require Bash,
enable Nix's `nix-command` / `flakes` features without replacing other settings,
and keep `flake.lock` unchanged. `queue` also needs the tools listed below.

```sh
just devices
just artifacts unicorn          # Available outputs
just plan unicorn kernel        # Preview builds and downloads
just drv unicorn kernel         # Evaluate the derivation path only
just build unicorn kernel       # result-unicorn-kernel
just build unicorn recovery     # result-unicorn-recovery
just build unicorn              # Defaults to system
just log unicorn kernel         # Read an available build log
just size result-unicorn-system # Closure size of an existing build
just eval --all-systems          # Evaluate both platforms without building
just check-one public-api       # One host check
just dev                        # Kernel development shell
just tools                      # Android, deployment and kernel tools
just queue --help
```

Replace `unicorn` and `kernel` with the intended device and artifact; nested
names such as `minimal.system` work too. Output links use
`result-<device>-<artifact>`. Append Nix options where needed, for example
`just build unicorn kernel --max-jobs 1 --cores 8`. `just` also lists commands
for logs, closure sizes and tools; `mobile` forwards arguments to
[mobile-device](../pkgs/mobile-device/README.md).

## Build iteration

Keep locked inputs and useful outputs to reuse caches. Build only the artifact
needed: system and recovery reuse the device kernel on the same build platform.
Avoid frequent garbage collection of outputs needed for subsequent builds.
Tune concurrent derivations (`--max-jobs`) and threads per build (`--cores`)
together; see [Nix parallelism](https://nix.dev/manual/nix/stable/advanced-topics/cores-vs-jobs.html).
For a kernel, start with `--max-jobs 1 --cores 8` and adjust for available
memory and CPU capacity; setting both values to the CPU count oversubscribes it.
Uncached native ARM jobs can use an [ARM remote builder](https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds.html)
to avoid QEMU compilation; native and cross-built project outputs have different caches.

For kernel iteration, use `just dev` with prepared sources, the effective Nix
kernel configuration and a separate persistent output directory per device:
`make O=/absolute/build-dir CC='ccache clang' -j8 Image dtbs`. Check hits with
`ccache -s`. Normal Nix builds cache complete outputs, not incremental object
files; entering the shell does not enable ccache for them. Validate final
checked-in inputs with the normal artifact build.

## Evaluation and tests

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
selected compiler platforms, and all supported devices' module selections (including
experimental Aurora).

Run [basic hardware tests](../tests/basic/README.md) and [host tests](../tests/README.md) explicitly on the intended
device. Evaluation, actual compilation, booting, and physical input/display
validation are separate results; test the configuration you intend to deploy.

Implementation references: [U-Boot](../pkgs/u-boot/README.md),
[USB package changes](../pkgs/usb-signaller/README.md), and device firmware sources:
[Asphalt](asphalt/README.md#firmware-sources),
[Clover](clover/README.md#firmware-sources),
[Polaris](polaris/README.md#firmware-sources),
[Sheng](sheng/README.md#firmware-sources),
[Aurora](aurora/firmware.md).

## Device support status

Each device documents its support in `docs/<device>/status.toml`, which gives
every item of [`docs/status/items.toml`](status/items.toml) one status: Works,
Partial, Broken, Untested, or N/A when the device lacks the hardware. Write
notes in English (`note`) and Chinese (`note_zh`); Partial and Broken need a
short note. An item may also record the date of its last real-device check,
`verified = "YYYY-MM-DD"`, shown as "(Verified on DATE.)", and a Geekbench
result, `benchmark = "https://browser.geekbench.com/…"`, shown as a link.
Regenerate the pages after editing and check them:

```sh
tools/status-pages.py
tools/status-pages.py --check
```

The generator refuses missing or unknown items, unknown statuses or fields,
notes in only one language, Partial or Broken items without a note, and
malformed `verified` dates or `benchmark` URLs; the `status-pages` flake check
fails on stale pages. Add a new item to `items.toml` first, then to every
device file.

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
git -C linux remote add upstream https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
git -C linux fetch --depth=1 --no-tags upstream tag v7.3.4
git -C linux show v7.3.4
```

Check the tag identity against the selected Nix source before importing. The
`v7.3.4` tag object is `8310b43a724c54668eeaa6860234078a7886915a`, commit
`7595a62d45ee1a2297eafa5f2ef5d0a45142d84d`; Nixpkgs fetches
`linux-7.3.4.tar.xz` with SHA256 `sha256-sRtt+Clejpkf8EC3GqpJlKi1XKojtrCSkH8ZW1hA/R8=`. Fetching a signed
tag alone does not establish signature trust; verify it with a trusted
maintainer key when available.

Import a device queue as the branch `android/<release>/<device>` and verify it:

```sh
python3 tools/kernel-queue.py import --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4
python3 tools/kernel-queue.py verify --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4
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

Edit the branch with ordinary Git (for example `git rebase -i v7.3.4`).
Preserve authors, upstream links and review/sign-off trailers, and describe
local adaptations separately. Then export to a new directory:

```sh
python3 tools/kernel-queue.py export --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4 --output ../export-aurora
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
