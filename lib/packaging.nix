# A scope for project packaging, not an overlay on upstream system packages.
# Build tools execute on the initiating computer; references in installed
# scripts and prebuilt binaries still use the native target package set.
{ pkgs, compilationPkgs }:
let
  buildPackages = compilationPkgs.buildPackages;
  builders = buildPackages.callPackage (pkgs.path + "/pkgs/build-support/trivial-builders") {
    inherit (compilationPkgs) stdenv stdenvNoCC;
    inherit (pkgs) runtimeShell;
  };
  packaging =
    pkgs
    // builders
    // {
      inherit buildPackages;
      # Tools that only run during the build and emit target-neutral data.
      # In a cross compilation set, buildPackages is build-host-for-target:
      # target-aware packages (alsa-utils pulls pipewire, bluez and
      # gobject-introspection) then reach for AArch64 cross builds.
      # pkgsBuildBuild keeps them native to the build machine and cached.
      inherit (compilationPkgs) pkgsBuildBuild;
      inherit (compilationPkgs) stdenv stdenvNoCC;
      runtimeStdenv = pkgs.stdenv;
      inherit (buildPackages)
        fetchurl
        fetchFromGitHub
        fetchFromGitLab
        patchelf
        ;
      autoPatchelfHook = buildPackages.autoPatchelfHook.override {
        stdenv = pkgs.stdenv;
        bintools = compilationPkgs.stdenv.cc.bintools.override {
          libc = pkgs.stdenv.cc.libc;
        };
      };
      newScope = extra: pkgs.lib.callPackageWith (packaging // extra);
    };
in
packaging
