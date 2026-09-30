# Reuse and override packages

[中文](packages.zh.md) · [Configuration](configuration.md)

Device modules use your Nixpkgs package set. Nixpkgs packages such as `libssc`
remain available as `pkgs.libssc`; this project only defines its own packages
and device adaptations. No overlay is required to import a device module.

## Select a service package

Use the module's package option to replace a single service implementation:

```nix
{ pkgs, ... }:
{
  androidDevices.usb.signaller.package = pkgs.usb-signaller;
}
```

A replacement must provide the features required by your configuration. The
project's usb-signaller includes integration and optional ACM patches; an
upstream package without them is not equivalent. Other entry points include
`androidDevices.camera.package` and
each recovery's `screenPackage` option.

## Use the package set directly

The public `lib.mkPackageSet` function accepts an existing `pkgs`. Use the build
environment to select a compiler while retaining native AArch64 userspace:

```nix
let
  environment = androidDevices.lib.mkBuildEnvironment {
    buildSystem = "x86_64-linux";
  };
  devicePackages = androidDevices.lib.mkPackageSet { inherit (environment) pkgs; };
  hostPackages = androidDevices.lib.mkPackageSet { pkgs = environment.buildPackages; };
in {
  usb-signaller = devicePackages.usb-signaller;
  mobile-device = hostPackages.mobile-device;
}
```

`environment.pkgs` is native AArch64. `environment.compilationPkgs` selects
AArch64-native or x86_64-to-AArch64 compilation; `environment.buildPackages`
contains programs that run on the initiating computer. In this environment,
`environment.pkgs.buildPackages` is also AArch64, so use the environment's
explicit `buildPackages` for host tools.

`mkPackageSet` also accepts an explicit `compilationPkgs`. By default it inherits
the environment's selection, or uses the supplied `pkgs` when no selection exists.
Compiled project packages use this compiler scope; firmware, prebuilt binaries,
scripts and image assembly use the registry’s `packaging` scope: builders and
checks execute on the selected host, while runtime references use native target
`pkgs`. Use `packaging.buildPackages` for explicit assembly tools. This scope is
for project recipes, not an overlay on upstream Nixpkgs. Ordinary upstream packages remain
unchanged. Cross toolchain/library dependencies can still need separate builds;
this does not turn their cross outputs into upstream native cache entries.
A caller that explicitly supplies a fully cross `pkgs` retains that behavior.
See [build requirements](configuration.md#build-platforms-and-remote-builders).

Device kernels are available directly as
`devicePackages.devices.<device>.kernel`; board modules use these packages by
default. The set also provides factories such as `mkKernel`,
`mkUBoot`, `mkAndroidBootImage`, `mkRootfsImage` and `mkRecoveryScreen`.

Sheng defaults to its pinned 7.2.6 kernel; `kernel-mainline` is an alias for it.
The 7.3-rc5 port remains available as `kernel-testing`. Clover defaults to 7.3
and offers a pinned 7.2.3 `kernel-mainline` fallback. To test Sheng's 7.3 port
in a separate system configuration, select it explicitly:

```nix
# Inside your flake's modules list, with inputs in scope:
({ lib, pkgs, ... }: {
  androidDevices.kernelPackage = lib.mkForce (
    inputs.androidDevices.lib.mkPackageSet { inherit pkgs; }
  ).devices.sheng.kernel-testing;
})
```

For Clover's 7.2.3 fallback, use `devices.clover.kernel-mainline`. Recovery has
its own system configuration and can select a kernel independently.
Flake `packages.<system>` exports generic tools. Device artifacts are nested
under `legacyPackages.<system>.devices`; both support `nix build .#<attribute>`.
The full package scope also contains factories and is accessed through `lib.mkPackageSet`.

## Optional overlay

`overlays.default` exposes the same set as `pkgs.androidDevicePackages`.
Apply it when constructing Nixpkgs, then override the scope when needed:

```nix
[
  androidDevices.overlays.default
  (final: prev: {
    androidDevicePackages = prev.androidDevicePackages.overrideScope (self: old: {
      usb-signaller = old.usb-signaller.overrideAttrs (attrs: {
        patches = (attrs.patches or [ ]) ++ [ ./my-usb-signaller.patch ];
      });
    });
  })
]
```

Pass this list to `lib.mkSystem`'s `overlays` argument, or to your own Nixpkgs
import. Device modules pick up the overlaid scope automatically. Without the
overlay, they instantiate the same scope from the supplied `pkgs`.

Package recipes and their dependency wiring live under `pkgs/`; NixOS modules
own configuration, service ordering and runtime policy. A recipe receives its
dependencies through `callPackage` rather than importing another Nixpkgs.

Board-specific recipes are in `pkgs/asphalt`, `pkgs/polaris`, `pkgs/sheng` and
`pkgs/clover`. The same scope supplies firmware, ALSA UCM, radio adaptations,
recovery tools and optional Sheng services. Recovery tool factories receive
storage identity and host-name arguments from the module; they do not perform
storage operations at evaluation or service startup.

Sheng's `hardware.sheng.{thp,pen-status}` options provide `package`.
For fingerprint support, use ordinary `services.fprintd.enable = true`.
On Sheng the default `services.fprintd.package` is `devices.sheng.fprintd` from
this package scope, built against `devices.sheng.libfprint`. Override it through
`services.fprintd.package`; there are no separate fingerprint package options.
The board module supplies the required QTEE services, device permissions and
runtime paths. NixOS owns PAM configuration; choose login, greetd and keyring
policy with normal NixOS options. Low-level QTEE/TA replacements use scope overrides.
`hardware.sheng.sensors` offers `fastrpcPackage`, `registryPackage`,
`qrtrPackage` and `devauthPackage`. Polaris radio offers `rmtfsPackage` and
`tqftpservPackage`. A scope override can replace firmware and other shared
packages without duplicating a module.

## Device namespaces

`asphalt`, `polaris`, `sheng` and `clover` are device codenames used as stable
identifiers, rather than processor names or output roles:

| Codename | Device |
| --- | --- |
| `asphalt` | Lenovo Y700 2023 |
| `polaris` | Xiaomi Mi MIX 2S |
| `sheng` | Xiaomi Pad 6S Pro |
| `clover` | Xiaomi Mi Pad 4 LTE (the supported variant) |

Board packages live under `devicePackages.devices.<codename>`, for example
`devices.asphalt.firmware` and `devices.sheng.thp`. Shared packages such as
`usb-signaller` remain at the top level. Each device is a scope with its own
`overrideScope`; override it inside the parent scope to propagate changes to
its dependent packages:

```nix
packages.overrideScope (self: old: {
  devices = old.devices // {
    sheng = old.devices.sheng.overrideScope (device: prev: {
      firmware = myShengFirmware;
    });
  };
})
```

Example image builds use the same device namespace:

```sh
nix build .#devices.asphalt.system
nix build .#devices.asphalt.u-boot
nix build .#devices.polaris.recovery
nix build .#devices.polaris.minimal.system
```

For flake consumers, use
`androidDevices.legacyPackages.${buildSystem}.devices.asphalt.u-boot`.
Device modules use `nixosModules.<codename>`. Device-specific options use
`hardware.<codename>.*`; shared capabilities use `androidDevices.*`.
The nested output follows the [Nix flake schema](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake-check.html):
`packages.<system>.<name>` must be a derivation; `legacyPackages` supports nested sets.
