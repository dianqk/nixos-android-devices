# Stock T880 connsys files, installed as lib/firmware/<name> for the MediaTek
# drivers: conninfra.cfg/connfem.cfg (wifi/) and the BGF MCU patches and BT
# RAM code for the Bluetooth driver (bluetooth/). The payload comes from the
# per-device release archive in firmware-source.nix.
{
  lib,
  runCommand,
  firmware-source,
}:
let
  source = firmware-source;
in
runCommand "t880-firmware" { meta.license = lib.licenses.unfree; } ''
  # Every component directory (wifi/, bluetooth/),
  # checked against its SHA256SUMS, flattened into lib/firmware.
  for component in wifi bluetooth; do
    src=${source}/$component
    [ -d "$src" ] || continue
    (cd "$src" && sha256sum -c SHA256SUMS)
    for f in "$src"/*; do
      name=$(basename "$f")
      [ "$name" = SHA256SUMS ] && continue
      install -Dm0644 "$f" "$out/lib/firmware/$name"
    done
  done
  test -e "$out/lib/firmware/conninfra.cfg"
''
