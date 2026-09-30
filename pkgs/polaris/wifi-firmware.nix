{
  runCommand,
  fetchFromGitHub,
  linux-firmware,
  wireless-regdb,
}:
let
  firmware = fetchFromGitHub {
    owner = "MollySophia";
    repo = "firmware-xiaomi-polaris";
    rev = "d88ffb2ee182d07567bf280fc4a8493f975ae977";
    hash = "sha256-aYGuZWrXzo3N6jgs5LcRiafJf3yQOKQxXEa0vsAkzIg=";
  };
in
runCommand "polaris-wifi-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  for name in mba.mbn modem.mbn wlanmdsp.mbn modemr.jsn modemuw.jsn; do
    cp ${firmware}/lib/firmware/qcom/sdm845/polaris/$name \
      $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  done
  mkdir -p $out/lib/firmware/ath10k/WCN3990/hw1.0
  cp ${firmware}/lib/firmware/postmarketos/ath10k/WCN3990/hw1.0/board-2.bin \
    $out/lib/firmware/ath10k/WCN3990/hw1.0/
  cp ${linux-firmware}/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin \
    $out/lib/firmware/ath10k/WCN3990/hw1.0/
  cp ${wireless-regdb}/lib/firmware/regulatory.db* $out/lib/firmware/
  mkdir -p $out/share
  ln -s ../lib/firmware $out/share/uncompressed-firmware

  test -s $out/lib/firmware/regulatory.db
  test -s $out/lib/firmware/regulatory.db.p7s
''
