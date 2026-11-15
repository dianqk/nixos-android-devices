{
  lib,
  rustPlatform,
  buildPackages,
}:
rustPlatform.buildRustPackage {
  pname = "boot-choice-native";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection (lib.fileset.gitTracked ../..) (
      lib.fileset.unions [
        ../../tools/boot-choice
        ../../modules/mobile/install-boot-choice.py
        ../../tools/early-entry/runtime-template.h
        ../../pkgs/boot-choice-efi/authority.rs
        ../../pkgs/boot-choice-efi/transaction.rs
      ]
    );
  };
  cargoRoot = "tools/boot-choice";
  buildAndTestSubdir = "tools/boot-choice";
  nativeCheckInputs = [ buildPackages.python3 ];
  cargoLock.lockFile = ../../tools/boot-choice/Cargo.lock;
  postInstall = ''
    ln -s boot-choice-native $out/bin/boot-choice
  '';
  meta = {
    description = "Guarded native same-slot boot preference and owned-image operation owner";
    license = lib.licenses.gpl2Only;
    mainProgram = "boot-choice";
    platforms = lib.platforms.linux;
  };
}
