{
  lib,
  runCommand,
  mkSSCRegistry,
}:
let
  registry = mkSSCRegistry {
    name = "asphalt-ssc-registry";
    configDirectory = ./config;
    hwPlatform = "MTP";
    socId = "531";
    registryVersion = "7";
  };
in
runCommand "asphalt-sensors" { meta.license = lib.licenses.unfree; } ''
  cp -r ${registry} "$out"
  chmod -R u+w "$out"
  mkdir -p "$out/lib/firmware/qcom/sm8475/lenovo/tb320fc" "$out/share"
  cp ${./firmware}/* "$out/lib/firmware/qcom/sm8475/lenovo/tb320fc/"
  cp -r ${./dsp} "$out/dsp"
  ln -s ../lib/firmware "$out/share/uncompressed-firmware"
''
