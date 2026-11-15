{
  lib,
  runCommand,
  mkSSCRegistry,
  firmware-source,
}:
let
  registry = mkSSCRegistry {
    name = "polaris-ssc-registry";
    configDirectory = ./config;
    hwPlatform = "POLARIS";
    socId = "321";
    registryVersion = "2";
  };
in
runCommand "polaris-sensors" { meta.license = lib.licenses.unfree; } ''
  cp -r ${registry} "$out"
  chmod -R u+w "$out"
  mkdir -p "$out/lib/firmware/qcom/sdm845/Xiaomi/polaris" "$out/share" "$out/dsp"
  for name in slpi.mbn slpir.jsn slpius.jsn; do
    cp ${firmware-source}/lib/firmware/qcom/sdm845/polaris/$name \
      "$out/lib/firmware/qcom/sdm845/Xiaomi/polaris/"
  done
  ln -s ../lib/firmware "$out/share/uncompressed-firmware"
''
