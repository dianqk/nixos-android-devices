{
  runCommand,
  lib,
  linux-firmware,
  firmware-source,
  wifiBoardFile ? "${firmware-source}/lenovo/tb320fc/wifi/board-2.bin",
}:
let
  wifiDirectory = "${firmware-source}/oneplus/negroni/WCN6855/hw2.1";
in
runCommand "asphalt-wifi-firmware" { } ''
  ${lib.optionalString (wifiBoardFile != null) ''
    install -Dm0644 ${wifiBoardFile} \
      "$out/lib/firmware/ath11k/WCN6855/hw2.1/board-2.bin"
  ''}
  for name in amss.bin m3.bin regdb.bin; do
    install -Dm0644 ${wifiDirectory}/"$name" \
      "$out/lib/firmware/ath11k/WCN6855/hw2.1/$name"
  done
  for name in wcnhpbtfw21.tlv wcnhpnv21g.bin; do
    install -Dm0644 ${linux-firmware}/lib/firmware/qca/"$name" \
      "$out/lib/firmware/qca/$name"
  done
''
