{ runCommand, alsa-ucm-conf }:
runCommand "polaris-alsa-ucm" { } ''
  mkdir -p $out/share/alsa
  cp -r ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/
  chmod -R u+w $out/share/alsa/ucm2
  mkdir -p $out/share/alsa/ucm2/Polaris $out/share/alsa/ucm2/conf.d/sdm845
  cp ${./ucm2/Polaris.conf} $out/share/alsa/ucm2/Polaris/Polaris.conf
  cp ${./ucm2/HiFi.conf} $out/share/alsa/ucm2/Polaris/HiFi.conf
  ln -s ../../Polaris/Polaris.conf \
    "$out/share/alsa/ucm2/conf.d/sdm845/Xiaomi Mi MIX 2S.conf"
  ln -s ../../Polaris/Polaris.conf \
    "$out/share/alsa/ucm2/conf.d/sdm845/xiaomi-XiaomiMiMIX2S.conf"
''
