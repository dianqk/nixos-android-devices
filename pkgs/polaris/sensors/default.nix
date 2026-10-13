{
  lib,
  runCommand,
  fetchFromGitHub,
  mkSSCRegistry,
}:
let
  registry = mkSSCRegistry {
    name = "polaris-ssc-registry";
    configDirectory = ./config;
    hwPlatform = "POLARIS";
    socId = "321";
    registryVersion = "2";
  };
  firmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-sensors" { meta.license = lib.licenses.unfree; } ''
  cp -r ${registry} "$out"
  chmod -R u+w "$out"
  mkdir -p "$out/lib/firmware/qcom/sdm845/Xiaomi/polaris" "$out/share" "$out/dsp"
  for name in slpi.mbn slpir.jsn slpius.jsn; do
    cp ${firmware}/lib/firmware/qcom/sdm845/polaris/$name \
      "$out/lib/firmware/qcom/sdm845/Xiaomi/polaris/"
  done
  ln -s ../lib/firmware "$out/share/uncompressed-firmware"
''
