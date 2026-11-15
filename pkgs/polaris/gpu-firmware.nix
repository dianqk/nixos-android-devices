{
  runCommand,
  firmware-source,
  linux-firmware,
}:
runCommand "polaris-gpu-firmware" { } ''
  mkdir -p $out/lib/firmware/qcom/sdm845/Xiaomi/polaris
  cp ${linux-firmware}/lib/firmware/qcom/a630_sqe.fw $out/lib/firmware/qcom/
  cp ${linux-firmware}/lib/firmware/qcom/a630_gmu.bin $out/lib/firmware/qcom/
  cp ${firmware-source}/lib/firmware/qcom/sdm845/polaris/a630_zap.mbn \
    $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/
  test -s $out/lib/firmware/qcom/sdm845/Xiaomi/polaris/a630_zap.mbn
''
