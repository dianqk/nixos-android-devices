{ runCommand, firmware-source }:
runCommand "polaris-multimedia-firmware" { } ''
  directory=$out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  mkdir -p "$directory" $out/share
  for name in adsp.mbn adspr.jsn adspua.jsn venus.mbn; do
    cp ${firmware-source}/lib/firmware/qcom/sdm845/polaris/$name "$directory/"
    test -s "$directory/$name"
  done
  cp ${firmware-source}/lib/firmware/tas2559_uCDSP.bin $out/lib/firmware/
  ln -s ../lib/firmware $out/share/uncompressed-firmware
''
