{
  lib,
  firmware-source,
  runCommand,
  python3,
  linux-firmware,
  wireless-regdb,
}:
runCommand "unicorn-firmware"
  {
    nativeBuildInputs = [
      python3
    ];
    passthru = {
      inherit firmware-source;
      linuxFirmwareVersion = linux-firmware.version;
      wirelessRegdbVersion = wireless-regdb.version;
      manifest = ./manifest.json;
    };
    meta = {
      description = "Hash-checked Xiaomi 12S Pro GPU, DSP, WLAN and Bluetooth firmware";
      license = lib.licenses.unfree;
      platforms = lib.platforms.linux;
    };
  }
  ''
    cmp ${firmware-source}/share/unicorn-firmware/manifest.json ${./manifest.json}
    mkdir "$out"
    cp -r --no-preserve=mode ${firmware-source}/lib ${firmware-source}/share "$out/"
    for name in wcnhpbtfw21.tlv wcnhpnv21g.bin; do
      install -Dm0644 ${linux-firmware.src}/qca/"$name" \
        "$out/lib/firmware/qca/$name"
    done
    for name in regulatory.db regulatory.db.p7s; do
      install -Dm0644 ${wireless-regdb}/lib/firmware/"$name" \
        "$out/lib/firmware/$name"
    done
    mkdir -p "$out/share/licenses/unicorn-firmware"
    install -m0644 ${linux-firmware.src}/LICENSES/LICENSE.QualcommAtheros_ath10k \
      "$out/share/licenses/unicorn-firmware/"
    install -m0644 ${linux-firmware.src}/LICENSES/NOTICE.qca \
      "$out/share/licenses/unicorn-firmware/NOTICE.qca.txt"
    python3 - "$out" <<'PYMANIFEST'
    import hashlib, json, struct, sys
    from pathlib import Path
    root = Path(sys.argv[1])
    # Measured WCN6855 product/ROM: 0x13/0x0201. The kernel tries the legacy
    # hpbtfw filename after transfer failures too, so keep the canonical
    # WCN685x image and validate its embedded target before accepting it.
    patch = root / "lib/firmware/qca/wcnhpbtfw21.tlv"
    patch_data = patch.read_bytes()
    if len(patch_data) < 28:
        raise ValueError("truncated WCN6855 patch header")
    type_len, = struct.unpack_from("<I", patch_data)
    header = struct.unpack_from("<IIBBBBHHHHI", patch_data, 4)
    if type_len & 0xff != 1 or (type_len >> 8) + 4 != len(patch_data):
        raise ValueError("invalid WCN6855 patch TLV type or length")
    if (header[6], header[7]) != (0x13, 0x0201):
        raise ValueError("Bluetooth patch target differs from measured Unicorn product/ROM")
    bluetooth = {"compatible": "qcom,wcn6855-bt", "patch": patch.name,
                 "nvm": "wcnhpnv21g.bin", "product_id": header[6],
                 "rom_build": header[7], "patch_version": header[8]}
    files = []
    for path in sorted((root / "lib/firmware").rglob("*")):
        if path.is_file():
            data = path.read_bytes()
            files.append({"path": str(path.relative_to(root)), "bytes": len(data),
                          "sha256": hashlib.sha256(data).hexdigest()})
    result = {"bluetooth": bluetooth,
              "linux_firmware_version": "${linux-firmware.version}",
              "wireless_regdb_version": "${wireless-regdb.version}", "files": files}
    (root / "share/unicorn-firmware/installed-files.json").write_text(
        json.dumps(result, indent=2) + "\n")
    PYMANIFEST
  ''
