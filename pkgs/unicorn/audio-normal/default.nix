{ runCommand }:
runCommand "unicorn-normal-audio-config" {} ''
  mkdir -p $out/share/alsa/ucm2/conf.d/sm8475
  mkdir -p $out/share/alsa/ucm2/Xiaomi-12S-Pro $out/share/unicorn-audio
  cp ${./ucm2/conf.d/sm8475/Xiaomi-12S-Pro.conf} \
    $out/share/alsa/ucm2/conf.d/sm8475/Xiaomi-12S-Pro.conf
  # ucm.conf resolves CardLongName, not the short name printed by aplay.
  ln -s Xiaomi-12S-Pro.conf \
    $out/share/alsa/ucm2/conf.d/sm8475/xiaomi-Xiaomi12SPro.conf
  cp ${./ucm2/Xiaomi-12S-Pro/HiFi.conf} \
    $out/share/alsa/ucm2/Xiaomi-12S-Pro/HiFi.conf
  cp ${./unicorn-stereo.conf} $out/share/unicorn-audio/unicorn-stereo.conf
  cp ${./unicorn-mic.conf} $out/share/unicorn-audio/unicorn-mic.conf
  cat > $out/share/alsa/ucm2/Xiaomi-12S-Pro/stereo.conf <<'EOF'
  LibraryConfig.unicorn.Config {
  EOF
  cat ${./unicorn-stereo.conf} >> $out/share/alsa/ucm2/Xiaomi-12S-Pro/stereo.conf
  printf '\n' >> $out/share/alsa/ucm2/Xiaomi-12S-Pro/stereo.conf
  cat ${./unicorn-mic.conf} >> $out/share/alsa/ucm2/Xiaomi-12S-Pro/stereo.conf
  printf '\n}\n' >> $out/share/alsa/ucm2/Xiaomi-12S-Pro/stereo.conf
''
