{ runCommand, firmware-source }:
runCommand "polaris-bluetooth-firmware" { } ''
  mkdir -p $out/lib/firmware/qca/Xiaomi/polaris
  cp ${firmware-source}/lib/firmware/qca/polaris/crnv21.bin \
    $out/lib/firmware/qca/Xiaomi/polaris/crnv21.bin
  cp ${firmware-source}/lib/firmware/postmarketos/qca/crbtfw21.tlv \
    $out/lib/firmware/qca/crbtfw21.tlv
''
