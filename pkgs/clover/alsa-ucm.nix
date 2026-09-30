{
  fetchzip,
  runCommand,
  alsa-ucm-conf,
}:
let
  ucmSource = fetchzip {
    url = "https://github.com/sdm660-mainline/alsa-ucm-conf/archive/8cfa1a20c94eede091596a293163fa5f9b4e3c12.tar.gz";
    hash = "sha256-Wl5ThXFvZw43zwngqcwDHgaP5HhjBjrPOXtvxRAt9Kg=";
  };
in
runCommand "clover-alsa-ucm" { } ''
  mkdir -p $out/share/alsa
  cp -r ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/
  chmod -R u+w $out/share/alsa/ucm2
  mkdir -p $out/share/alsa/ucm2/Xiaomi/clover \
    $out/share/alsa/ucm2/conf.d/sdm660-internal
  cp ${ucmSource}/ucm2/Xiaomi/clover/*.conf \
    $out/share/alsa/ucm2/Xiaomi/clover/
  ln -sfn ../../Xiaomi/clover/clover.conf \
    "$out/share/alsa/ucm2/conf.d/sdm660-internal/Xiaomi Mi Pad 4.conf"
''
