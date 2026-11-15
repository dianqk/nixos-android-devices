{
  runCommand,
  firmware-source,
  linux-firmware,
  wireless-regdb,
}:
runCommand "polaris-wifi-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  for name in mba.mbn modem.mbn wlanmdsp.mbn modemr.jsn modemuw.jsn; do
    cp ${firmware-source}/lib/firmware/qcom/sdm845/polaris/$name \
      $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  done
  mkdir -p $out/lib/firmware/ath10k/WCN3990/hw1.0
  cp ${firmware-source}/lib/firmware/postmarketos/ath10k/WCN3990/hw1.0/board-2.bin \
    $out/lib/firmware/ath10k/WCN3990/hw1.0/
  cp ${linux-firmware}/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin \
    $out/lib/firmware/ath10k/WCN3990/hw1.0/
  cp ${wireless-regdb}/lib/firmware/regulatory.db* $out/lib/firmware/
  mkdir -p $out/share
  ln -s ../lib/firmware $out/share/uncompressed-firmware

  test -s $out/lib/firmware/regulatory.db
  test -s $out/lib/firmware/regulatory.db.p7s
''
