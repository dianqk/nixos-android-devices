{ runCommand, alsa-ucm-conf }:
runCommand "asphalt-alsa-ucm" { } ''
  mkdir -p $out/share/alsa
  cp -r ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/
  chmod -R u+w $out/share/alsa/ucm2
  mkdir -p $out/share/alsa/ucm2/Lenovo-Y700 \
    $out/share/alsa/ucm2/conf.d/sm8475
  cp ${./Lenovo-Y700.conf} $out/share/alsa/ucm2/Lenovo-Y700/Lenovo-Y700.conf
  cp ${./HiFi.conf} $out/share/alsa/ucm2/Lenovo-Y700/HiFi.conf
  ln -s ../../Lenovo-Y700/Lenovo-Y700.conf \
    $out/share/alsa/ucm2/conf.d/sm8475/Lenovo-Y700.conf
''
