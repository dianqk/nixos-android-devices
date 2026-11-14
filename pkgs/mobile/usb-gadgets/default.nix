{
  runCommand,
  makeWrapper,
  python3,
  util-linux,
  dosfstools,
  lib,
}:
runCommand "mobile-usb-gadgets"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.platforms = lib.platforms.linux;
  }
  ''
    mkdir -p "$out/lib/mobile-usb-gadgets" "$out/bin"
    cp ${./backend.py} "$out/lib/mobile-usb-gadgets/backend.py"
    cp ${./touch.py} "$out/lib/mobile-usb-gadgets/touch.py"
    cp ${./storage.py} "$out/lib/mobile-usb-gadgets/storage.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/usb-gadget-backend" \
      --add-flags "$out/lib/mobile-usb-gadgets/backend.py" \
      --prefix PATH : ${lib.makeBinPath [ util-linux ]}
    makeWrapper ${python3}/bin/python3 "$out/bin/usb-touch" \
      --add-flags "$out/lib/mobile-usb-gadgets/touch.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/usb-storage-image" \
      --add-flags "$out/lib/mobile-usb-gadgets/storage.py" \
      --prefix PATH : ${lib.makeBinPath [ dosfstools ]}
  ''
