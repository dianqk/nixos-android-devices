{ runCommand, fetchFromGitHub }:
let
  firmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-bluetooth-firmware" { } ''
  mkdir -p $out/lib/firmware/qca/Xiaomi/polaris
  cp ${firmware}/lib/firmware/qca/polaris/crnv21.bin \
    $out/lib/firmware/qca/Xiaomi/polaris/crnv21.bin
  cp ${firmware}/lib/firmware/postmarketos/qca/crbtfw21.tlv \
    $out/lib/firmware/qca/crbtfw21.tlv
''
