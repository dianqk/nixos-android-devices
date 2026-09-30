{
  runCommand,
  fetchFromGitHub,
}:
let
  deviceFirmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-ipa-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  cp ${deviceFirmware}/lib/firmware/qcom/sdm845/polaris/ipa_fws.mbn \
    $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  test -s $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/ipa_fws.mbn
''
