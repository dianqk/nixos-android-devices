# Build this on either initiating platform. The native ARM probe deliberately
# has no upstream substitute, exercising binfmt fallback on an x86_64 builder.
{
  flake,
  buildSystem,
  includeNativeProbe ? true,
}:
let
  env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
  target = env.pkgs;
  host = env.buildPackages;
  packaging = target.androidDevicePackages.packaging;
  script = packaging.writeShellApplication {
    name = "target-packaging-probe";
    runtimeInputs = [ target.coreutils ];
    text = "uname -m";
  };
  binary = packaging.stdenvNoCC.mkDerivation {
    name = "target-elf-packaging-probe";
    dontUnpack = true;
    dontStrip = true;
    nativeBuildInputs = [ packaging.autoPatchelfHook ];
    buildInputs = [ target.stdenv.cc.libc ];
    installPhase = ''
      mkdir -p $out/bin
      cp ${target.hello}/bin/hello $out/bin/hello
      chmod u+w $out/bin/hello
    '';
  };
  nativeProbe = target.runCommand "uncached-native-arm-probe" { } ''
    uname -m > "$out"
  '';
in
assert script.system == buildSystem;
assert binary.system == buildSystem;
assert nativeProbe.system == "aarch64-linux";
host.runCommand "android-packaging-platforms" { nativeBuildInputs = [ host.patchelf ]; } ''
  test "$(head -n1 ${script}/bin/target-packaging-probe)" = '#!${target.runtimeShell}'
  grep -F '${target.coreutils}/bin' ${script}/bin/target-packaging-probe
  test "$(patchelf --print-interpreter ${binary}/bin/hello)" = '${target.stdenv.cc.bintools.dynamicLinker}'
  ${target.lib.optionalString includeNativeProbe ''
    test "$(cat ${nativeProbe})" = aarch64
  ''}
  touch "$out"
''
