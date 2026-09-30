{ runCommand, firmware-source }:
let
  firmwareDirectory = "${firmware-source}/lenovo/tb320fc";
in
runCommand "asphalt-stock-firmware" { } ''
  source=${firmwareDirectory}
  install -Dm0644 "$source/firmware/novatek_ts_fw.bin" \
    "$out/lib/firmware/novatek/lenovo-tb320fc.bin"
  for name in a730_sqe.fw gmu_gen70000.bin; do
    install -Dm0644 "$source/firmware/$name" "$out/lib/firmware/qcom/$name"
  done
  for name in a730_zap.mdt a730_zap.b00 a730_zap.b01 a730_zap.b02 vpu20_4v.mbn; do
    install -Dm0644 "$source/firmware/$name" \
      "$out/lib/firmware/qcom/sm8475/lenovo/tb320fc/$name"
  done
  for file in "$source"/audio/adsp/adsp.*; do
    install -Dm0644 "$file" \
      "$out/lib/firmware/qcom/sm8475/lenovo/tb320fc/''${file##*/}"
  done
  for file in "$source"/audio/cs35l45/*; do
    install -Dm0644 "$file" "$out/lib/firmware/''${file##*/}"
  done
  ln -s spk1-cs35l45-dsp1-spk-prot.wmfw \
    "$out/lib/firmware/spk2-cs35l45-dsp1-spk-prot.wmfw"
''
