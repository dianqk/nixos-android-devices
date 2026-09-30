{
  fetchFromGitHub,
  linux-firmware,
  python3,
  runCommand,
  wireless-regdb,
}:
let
  cloverBoard = fetchFromGitHub {
    owner = "setotau";
    repo = "firmware-xiaomi-clover";
    rev = "c850ad5d11315e690df8244670241e3d5a8436dc";
    hash = "sha256-SaxbtTOV/r3Sm2al3qg9Iue0iaCK/p9pn6TVHCTGEnY=";
  };
  qcaSwissArmyKnife = fetchFromGitHub {
    owner = "qca";
    repo = "qca-swiss-army-knife";
    rev = "6df4dae3e2f5e4c2903f3cafd40996fc1b3639ce";
    hash = "sha256-FFoV58YVK7KGBw/JPFWcvGkJOONrfKCvACprYCzIKeg=";
  };
in
runCommand "clover-public-firmware" { nativeBuildInputs = [ python3 ]; } ''
  ath10k=$out/lib/firmware/ath10k/WCN3990/hw1.0
  mkdir -p "$ath10k" $out/lib/firmware/qca $out/lib/firmware/qcom $out/share

  cp ${cloverBoard}/board-2.bin "$ath10k/board-2.bin"
  cp ${linux-firmware}/lib/firmware/ath10k/WCN3990/hw1.0/wlanmdsp.mbn "$ath10k/"
  cd "$ath10k"
  python3 ${qcaSwissArmyKnife}/tools/scripts/ath10k/ath10k-fwencoder \
    --create --timestamp=1 --set-fw-api=5 \
    --features=wowlan,no-nwifi-decap-4addr-padding,allows-mesh-bcast,mgmt-tx-by-ref,non-bmi,single-chan-info-per-channel \
    --set-wmi-op-version=tlv --set-htt-op-version=tlv
  cd - >/dev/null
  for name in crbtfw21.tlv crnv21.bin; do
    cp ${linux-firmware}/lib/firmware/qca/$name $out/lib/firmware/qca/
  done
  for name in a530_pm4.fw a530_pfp.fw; do
    cp ${linux-firmware}/lib/firmware/qcom/$name $out/lib/firmware/qcom/
  done
  cp ${wireless-regdb}/lib/firmware/regulatory.db* $out/lib/firmware/

  test -s "$ath10k/board-2.bin"
  test -s $out/lib/firmware/qca/crbtfw21.tlv
  ln -s ../lib/firmware $out/share/uncompressed-firmware
''
