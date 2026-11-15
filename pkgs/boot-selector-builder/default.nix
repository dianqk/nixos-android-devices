{ lib, stdenv, runCommand, python3, makeWrapper, android-tools }:
assert stdenv.hostPlatform.isAarch64;
let
  source = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection (lib.fileset.gitTracked ../..) ../../tools;
  };
in runCommand "boot-selector-builder-0.1.0" {
  nativeBuildInputs = [ makeWrapper ];
  meta = {
    description = "Host-only source-bound AArch64 early boot selector builder";
    license = lib.licenses.gpl2Only;
    mainProgram = "boot-selector-builder";
  };
} ''
  mkdir -p $out/bin $out/libexec
  cp -r ${source}/tools $out/libexec/tools
  makeWrapper ${python3}/bin/python3 $out/bin/boot-selector-builder \
    --add-flags $out/libexec/tools/build-boot-selector.py \
    --set CC ${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc \
    --set LD ${stdenv.cc.bintools}/bin/${stdenv.cc.targetPrefix}ld \
    --set OBJCOPY ${stdenv.cc.bintools}/bin/${stdenv.cc.targetPrefix}objcopy
  makeWrapper ${python3}/bin/python3 $out/bin/boot-image-experiment \
    --add-flags $out/libexec/tools/boot-image-experiment.py \
    --prefix PATH : ${lib.makeBinPath [ android-tools ]}
''
