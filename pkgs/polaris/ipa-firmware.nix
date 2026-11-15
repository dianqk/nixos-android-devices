{
  runCommand,
  firmware-source,
}:
runCommand "polaris-ipa-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  cp ${firmware-source}/lib/firmware/qcom/sdm845/polaris/ipa_fws.mbn \
    $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  test -s $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/ipa_fws.mbn
''
