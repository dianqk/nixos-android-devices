{
  lib,
  runCommand,
  python3,
  nodejs,
  binutils,
  gnutar,
  gzip,
  boot-choice-native,
  boot-choice-template,
  firmware,
  gnu-efi,
}:
let
  project = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.gitTracked ../..;
  };
  sources =
    runCommand "dodge-boot-choice-corresponding-source.tar.gz"
      {
        nativeBuildInputs = [
          gnutar
          gzip
        ];
      }
      ''
        mkdir source
        cp -r ${project} source/project
        cp -r ${firmware.src} source/u-boot
        cp -r ${gnu-efi.src} source/gnu-efi
        cp -rL ${boot-choice-native.cargoDeps} source/cargo-vendor
        chmod -R u+w source
        tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf $out source
      '';
in
runCommand "dodge-boot-choice-kernelsu-1.1.0"
  {
    nativeBuildInputs = [
      python3
      nodejs
      binutils
    ];
    passthru = { inherit sources; };
    meta = {
      description = "Self-contained opt-in Dodge same-slot boot-choice KernelSU Manager module";
      license = lib.licenses.gpl2Only;
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p $out
    python3 ${./build.py} ${./.} ${boot-choice-native}/bin/boot-choice ${boot-choice-template} $out ${sources} ${../../LICENSES/GPL-2.0}
    python3 ${./test.py} $out/module $out/dodge-boot-choice-kernelsu.zip
    node ${./test-webui.mjs} $out/module/webroot
  ''
