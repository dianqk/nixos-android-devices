{
  buildPackages,
  lib,
  linuxManualConfig,
  stdenv,
}:

{
  pname,
  version,
  modDirVersion ? version,
  src,
  configfile,
  patches ? [ ],
  postConfigure ? "",
  extraMakeFlags ? [ ],
  buildInputs ? [ ],
  nativeBuildInputs ? [ ],
  preBuild ? "",
  dtbs ? [ ],
  configOverrides ? { },
}:
let
  llvmPackages_23 = buildPackages.llvmPackages_23;
  clangLib = lib.getLib llvmPackages_23.clang-unwrapped;
  clangVersion = lib.versions.major llvmPackages_23.clang-unwrapped.version;
  # Render all layers in evaluation so Nixpkgs sees the same MODULES/RUST/etc.
  # metadata as Kconfig. A generated configfile alone is not parsed by
  # linuxManualConfig without IFD and would silently lose its modules output.
  baseLines = lib.splitString "\n" (builtins.readFile configfile);
  keepBaseLine =
    line:
    let
      enabled = builtins.match "CONFIG_([A-Za-z0-9_]+)=.*" line;
      disabled = builtins.match "# CONFIG_([A-Za-z0-9_]+) is not set" line;
      match = if enabled != null then enabled else disabled;
    in
    match == null || !(builtins.hasAttr (builtins.head match) configOverrides);
  overrideLines = lib.mapAttrsToList (
    name: value:
    assert builtins.elem value.tristate [
      "y"
      "m"
      "n"
    ];
    if value.tristate == "n" then "# CONFIG_${name} is not set" else "CONFIG_${name}=${value.tristate}"
  ) configOverrides;
  effectiveLines = builtins.filter keepBaseLine baseLines ++ overrideLines;
  effectiveConfigfile = buildPackages.writeText "${pname}-configured.config" (
    lib.concatStringsSep "\n" effectiveLines + "\n"
  );
  effectiveConfig = builtins.listToAttrs (
    lib.concatMap (
      line:
      let
        match = builtins.match "(CONFIG_[A-Za-z0-9_]+)=([ym])" line;
      in
      lib.optional (match != null) {
        name = builtins.elemAt match 0;
        value = builtins.elemAt match 1;
      }
    ) effectiveLines
  );
  expectedOverridesFile = buildPackages.writeText "${pname}-expected-overrides.config" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "CONFIG_${name}=${value.tristate}") configOverrides
    )
    + "\n"
  );
  expectedPinctrl = lib.filterAttrs (
    name: value: (name == "PINCTRL" || lib.hasPrefix "PINCTRL_" name) && value.tristate != "n"
  ) configOverrides;
  expectedPinctrlFile = buildPackages.writeText "${pname}-pinctrl.config" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "CONFIG_${name}=${value.tristate}") expectedPinctrl
    )
    + "\n"
  );
  kernel = linuxManualConfig {
    inherit
      pname
      version
      modDirVersion
      src
      ;
    configfile = effectiveConfigfile;
    config = effectiveConfig;
    # linuxManualConfig does not infer the NixOS bootloader feature metadata.
    features = lib.optionalAttrs ((effectiveConfig.CONFIG_EFI_STUB or "n") == "y") {
      efiBootStub = true;
    };
    # Use the cross stdenv to retain the AArch64 output platform. LLVM itself
    # comes from buildPackages so Clang and its tools run on the build host.
    stdenv = stdenv;
    target = "Image";
    buildDTBs = dtbs == [ ];
    kernelPatches = lib.imap0 (index: patch: {
      name = "${pname}-${toString index}";
      inherit patch;
    }) patches;
    extraMakeFlags = [
      "ARCH=arm64"
      "LLVM=1"
      "CC=${llvmPackages_23.clang-unwrapped}/bin/clang"
      "LD=${llvmPackages_23.lld}/bin/ld.lld"
      "AR=${llvmPackages_23.llvm}/bin/llvm-ar"
      "NM=${llvmPackages_23.llvm}/bin/llvm-nm"
      "OBJCOPY=${llvmPackages_23.llvm}/bin/llvm-objcopy"
      "OBJDUMP=${llvmPackages_23.llvm}/bin/llvm-objdump"
      "READELF=${llvmPackages_23.llvm}/bin/llvm-readelf"
      "STRIP=${llvmPackages_23.llvm}/bin/llvm-strip"
      "CFLAGS_MODULE=-I${clangLib}/lib/clang/${clangVersion}/include"
      "CFLAGS_KERNEL=-I${clangLib}/lib/clang/${clangVersion}/include"
    ]
    ++ extraMakeFlags;
  };
in
kernel.overrideAttrs (old: {
  # These device trees regularly add new Kconfig symbols. Never leave an
  # interactive oldconfig prompt in an unattended local build.
  configurePhase = builtins.replaceStrings [ "oldconfig" ] [ "olddefconfig" ] old.configurePhase;
  postPatch = (old.postPatch or "") + ''
    find . -type f \( -name Makefile -o -name Kbuild \) -print0 \
      | xargs -0 sed -i -e 's/[[:space:]]-Werror\([[:space:]]\|$\)/ /g'
  '';
  inherit preBuild;
  postConfigure = postConfigure + ''
    # Check resolved Kconfig, not just the input fragment. Catch dependencies or
    # new defaults that resurrect unrelated drivers, and missing boot drivers.
    grep -E '^CONFIG_PINCTRL(_[A-Za-z0-9_]+)?=[ym]$' "$buildRoot"/.config | sort > "$buildRoot"/pinctrl.config
    sort ${expectedPinctrlFile} > "$buildRoot"/pinctrl-expected.config
    diff -u "$buildRoot"/pinctrl-expected.config "$buildRoot"/pinctrl.config
    # A dependency may select a driver back on, or make a retained driver
    # unavailable. Verify every layered override after olddefconfig.
    awk -F= '
      NR == FNR { expected[$1] = $2; next }
      /^CONFIG_/ { actual[$1] = $2 }
      END {
        for (symbol in expected) {
          value = (symbol in actual) ? actual[symbol] : "n"
          if (value != expected[symbol]) {
            print symbol ": expected " expected[symbol] ", got " value
            failed = 1
          }
        }
        exit failed
      }
    ' ${expectedOverridesFile} "$buildRoot"/.config
  '';
  buildInputs = (old.buildInputs or [ ]) ++ buildInputs;
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ nativeBuildInputs;
  dontStrip = true;
  # Linux 7.x gives arm64 zinstall an EFI-specific meaning. Keep nixpkgs'
  # ordinary install lifecycle (install, modules_install into the separate
  # `modules` output, dtbs_install when building all DTBs) and add the proven
  # Android Image.gz ourselves.
  installTargets = map (target: if target == "zinstall" then "install" else target) old.installTargets;
  buildFlags = (old.buildFlags or [ ]) ++ dtbs;
  # Nixpkgs signs modules with per-module kmodigest certificates and then
  # concatenates them into modules.cer. Our configs either leave MODULE_SIG
  # unset (no certificates are produced, so the concatenation fails) or sign
  # with the kernel's own build key (Clover); keep Kbuild's own signing rule.
  makeFlags = builtins.filter (flag: !(lib.hasPrefix "cmd_sign=" flag)) old.makeFlags;
  postInstall =
    # Before the inherited postInstall: it runs `make clean` on the build tree
    # and repoints $buildRoot at the retained $dev tree.
    ''
      gzip -n -c "$buildRoot/arch/arm64/boot/Image" > "$out/Image.gz"
      cp "$buildRoot/.config" "$out/build.config"
      ${lib.concatMapStringsSep "\n" (dtb: ''
        install -Dm0644 "$buildRoot/arch/arm64/boot/dts/${dtb}" "$out/dtbs/${dtb}"
      '') dtbs}
    ''
    + (
      let
        concatenation = [
          "sed 's/$/\\.cer/' modules.order | xargs -d'\\n' cat > modules.cer"
          "sed 's/$/\\.cer/' modules.order | xargs -d'\\n' rm"
        ];
        inherited = old.postInstall or "";
        stripped = builtins.replaceStrings concatenation [
          ":"
          ":"
        ] inherited;
      in
      assert lib.assertMsg (
        !(lib.hasInfix "modules.cer" inherited) || stripped != inherited
      ) "kernel-compat: the nixpkgs modules.cer concatenation changed; update kernel-compat.nix";
      stripped
    )
    + lib.optionalString (builtins.elem "modules" (old.outputs or [ "out" ])) ''
      test -d "$modules/lib/modules/${modDirVersion}"
      test ! -L "$modules/lib/modules/${modDirVersion}/build"
    ''
    + ''
      test -s "$out/Image.gz"
      test -s "$out/System.map"
      test -d "$out/dtbs"
    '';
})
