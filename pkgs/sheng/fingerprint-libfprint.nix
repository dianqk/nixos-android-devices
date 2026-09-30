# ---
# Package: Sheng FPC1553 libfprint
# Description: Native private libfprint backend for Xiaomi Pad 6S Pro
# Scope: Host
# ---

{
  lib,
  libfprint,
  shengFingerprint,
  stdenv,
  buildPackages,
}:

let
  sourcePatch = "${shengFingerprint}/patches/libfprint/0001-libfprint-add-fpc1553.patch";
  fpc1553Patch =
    buildPackages.runCommand "libfprint-fpc1553.patch"
      {
        nativeBuildInputs = [ buildPackages.python3 ];
      }
      ''
        python3 - "${sourcePatch}" "$out" <<'PY'
        import pathlib
        import sys

        source = pathlib.Path(sys.argv[1]).read_text()
        start = source.index("diff --git a/libfprint/meson.build b/libfprint/meson.build")
        second_hunk = source.index("@@ -282", start)
        top_start = source.index("diff --git a/meson.build b/meson.build")
        options_start = source.index("diff --git a/meson_options.txt", top_start)
        libfprint_replacement = """diff --git a/libfprint/meson.build b/libfprint/meson.build
        index 3449481..2a8c4ed 100644
        --- a/libfprint/meson.build
        +++ b/libfprint/meson.build
        @@ -139,0 +140,1 @@
        +    'fpc1553' : files('drivers/fpc1553.c'),
        """
        empty_string = "'" * 2
        meson_replacement = """diff --git a/meson.build b/meson.build
        index 14fb11f..fb9a3ae 100644
        --- a/meson.build
        +++ b/meson.build
        @@ -147,0 +148,1 @@
        +    'fpc1553': {},
        @@ -220,0 +221,17 @@ optional_deps = []
        +if 'fpc1553' in drivers
        +    fpc1553_backend_dir = get_option('fpc1553_backend_dir')
        +    if fpc1553_backend_dir == @empty@
        +        error('fpc1553 requires -Dfpc1553_backend_dir=DIR')
        +    endif
        +    fpc1553_backend = cc.find_library('fpc1553-qtee',
        +        dirs: [fpc1553_backend_dir], required: true)
        +    fpc1553_qcbor_inc = include_directories(
        +        fpc1553_backend_dir / '../vendor/QCBOR-1.6/inc')
        +    optional_deps += declare_dependency(
        +        include_directories: [
        +            include_directories(fpc1553_backend_dir),
        +            fpc1553_qcbor_inc,
        +        ],
        +        dependencies: fpc1553_backend)
        +endif
        +
        """
        meson_replacement = meson_replacement.replace("@empty@", empty_string)
        pathlib.Path(sys.argv[2]).write_text(
            source[:start]
            + libfprint_replacement
            + source[second_hunk:top_start]
            + meson_replacement
            + source[options_start:]
        )
        PY
      '';
  emulationHeader = builtins.toFile "fpi-test-emulation.h" ''
    #define FPI_EMULATION_ENV_VAR "FP_DEVICE_EMULATION"
    #define FPI_EMULATION_HELPER_BUILDDIR ""
    #define FPI_EMULATION_HELPER_INSTALLDIR ""
    #define FPI_EMULATION_HELPER_MODULE ""
  '';
  backend = stdenv.mkDerivation {
    pname = "xiaomi-sheng-fpc1553-backend";
    version = "0.1.4";
    src = shengFingerprint;

    nativeBuildInputs = [ buildPackages.binutils ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      patchShebangs scripts/build-backend.sh
      scripts/build-backend.sh "$PWD/build-output/backend"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm0644 build-output/backend/libfpc1553-qtee.so \
        "$out/backend/libfpc1553-qtee.so"
      install -Dm0644 build-output/backend/*.h -t "$out/backend"
      install -d "$out/vendor/QCBOR-1.6/inc"
      cp -R third_party/QCBOR/inc/. "$out/vendor/QCBOR-1.6/inc/"
      runHook postInstall
    '';
  };
in
(libfprint.override { inherit stdenv; }).overrideAttrs (old: {
  pname = "xiaomi-sheng-libfprint";
  outputs = [ "out" ];

  patches = (old.patches or [ ]) ++ [
    fpc1553Patch
  ];

  nativeBuildInputs = with buildPackages; [
    pkg-config
    meson
    ninja
    glib
  ];

  mesonFlags = [
    "-Ddrivers=fpc1553"
    "-Dfpc1553_backend_dir=${backend}/backend"
    "-Dintrospection=false"
    "-Ddoc=false"
    "-Dinstalled-tests=false"
    "-Dgtk-examples=false"
    "-Dudev_rules=disabled"
    "-Dudev_hwdb=disabled"
  ];

  postPatch = (old.postPatch or "") + ''
    install -Dm0644 ${emulationHeader} tests/fpi-test-emulation.h
    substituteInPlace meson.build \
      --replace-fail "subdir('tests')" "" \
      --replace-fail "subdir('examples')" ""
  '';

  doCheck = false;
  doInstallCheck = false;

  postInstall = (old.postInstall or "") + ''
    install -Dm0644 ${backend}/backend/libfpc1553-qtee.so \
      "$out/lib/libfpc1553-qtee.so"
  '';

  meta = (old.meta or { }) // {
    description = "Private libfprint build with the Xiaomi Sheng FPC1553 backend";
    platforms = [ "aarch64-linux" ];
  };
})
