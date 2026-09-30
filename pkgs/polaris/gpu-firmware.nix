{
  runCommand,
  fetchFromGitHub,
  linux-firmware,
}:
let
  deviceFirmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-gpu-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  cp ${linux-firmware}/lib/firmware/qcom/a630_sqe.fw $out/lib/firmware/qcom/
  cp ${linux-firmware}/lib/firmware/qcom/a630_gmu.bin $out/lib/firmware/qcom/
  cp ${deviceFirmware}/lib/firmware/qcom/sdm845/polaris/a630_zap.mbn \
    $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  test -s $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/a630_zap.mbn
''
