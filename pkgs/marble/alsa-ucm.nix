{ runCommand, alsa-ucm-conf }:
# alsa-ucm-conf plus the Marble card ("SM8475-Xiaomi-Marble", driver sm8450).
# ucm.conf looks up conf.d/<driver>/<long name>.conf; with SMBIOS the ASoC
# long name is the DMI name "xiaomi-XiaomiPocoF5marble", so link that too.
runCommand "marble-alsa-ucm" { } ''
  mkdir -p $out/share/alsa
  cp -r ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/
  chmod -R u+w $out/share/alsa/ucm2
  install -Dm0644 ${./ucm/HiFi.conf} \
    $out/share/alsa/ucm2/Qualcomm/sm8450/xiaomi-marble/HiFi.conf
  install -Dm0644 ${./ucm/SM8475-Xiaomi-Marble.conf} \
    $out/share/alsa/ucm2/conf.d/sm8450/SM8475-Xiaomi-Marble.conf
  ln -s SM8475-Xiaomi-Marble.conf \
    $out/share/alsa/ucm2/conf.d/sm8450/xiaomi-XiaomiPocoF5marble.conf
''
