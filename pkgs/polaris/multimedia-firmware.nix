{ runCommand, fetchFromGitHub }:
let
  firmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-multimedia-firmware" { } ''
  directory=$out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  mkdir -p "$directory" $out/share
  for name in adsp.mbn adspr.jsn adspua.jsn venus.mbn; do
    cp ${firmware}/lib/firmware/qcom/sdm845/polaris/$name "$directory/"
    test -s "$directory/$name"
  done
  cp ${firmware}/lib/firmware/tas2559_uCDSP.bin $out/lib/firmware/
  ln -s ../lib/firmware $out/share/uncompressed-firmware
''
