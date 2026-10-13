{
  runCommand,
  makeWrapper,
  buildPackages,
  python3,
  coreutils,
  iio-sensor-proxy,
}:
runCommand "mobile-sensor-rotate" { nativeBuildInputs = [ buildPackages.makeWrapper ]; } ''
  mkdir -p "$out/bin" "$out/libexec"
  cp ${./rotate.py} "$out/libexec/rotate.py"
  makeWrapper ${python3}/bin/python3 "$out/bin/mobile-sensor-rotate" \
    --add-flags "$out/libexec/rotate.py" \
    --prefix PATH : ${coreutils}/bin:${iio-sensor-proxy}/bin
''
