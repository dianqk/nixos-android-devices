{
  lib,
  runCommand,
  python3,
  mkSSCRegistry,
  firmware-source,
  # WCN6855 board data. Marble's WCN6855 is a GlobalFoundries part (Bluetooth
  # SoC ID 0x400c1211); bd_m16tgf.elf is the GF board data of the China
  # hardware, bd_m16tgfgl.elf that of the global hardware.
  wifiBoardFile ? "${firmware-source}/wlan/bd_m16tgf.elf",
  # SHA-256 of the speaker ACF derived from the stock file; null skips the
  # check (another firmware release).
  speakerAcfSha256 ? "25713acabfebce4bfcbf50e942b13c208ef636fad7c860f46a80709efef47237",
}:
let
  # Stock /vendor/etc/sensors/config, selected for this board's soc0 values
  # (soc_id 591, hw_platform MTP, platform_subtype_id 0; the stock
  # sns_reg_config version 12, one registry file per group). Generic
  # defaults only: this handset's factory calibration lives in its persist
  # partition and is not part of any package.
  sensorConfigs = runCommand "marble-ssc-configs" { nativeBuildInputs = [ python3 ]; } ''
    (cd ${firmware-source}/sensors && sha256sum -c --quiet SHA256SUMS)
    grep -qx 'version=12' ${firmware-source}/sensors/sns_reg_config
    python3 -I ${./ssc-configs.py} ${firmware-source}/sensors/config "$out" \
      --platform-subtype-id 0 --exclude lightSensorConfig.json
  '';
  sensorRegistry = mkSSCRegistry {
    name = "marble-ssc-registry";
    configDirectory = sensorConfigs;
    hwPlatform = "MTP";
    socId = "591";
    registryVersion = "12";
  };
in
# Outputs:
# - out: GPU, video, Wi-Fi and Bluetooth. Their drivers are built into the
#   kernel and request firmware while the initrd runs.
# - dsp: ADSP (audio, battery and charger through pmic_glink) and SLPI
#   (sensors), loaded by the remoteproc modules in stage 2.
# - modem: modem, its carrier configurations (modem_pr) and IPA; not
#   installed by the Marble module.
# - sensors: SSC sensor data for androidDevices.sensors (hardware.marble.
#   sensors): the SSC registry defaults (etc/sensors, seed) generated from
#   the stock sensor configuration (sensors/config of the firmware source)
#   and the SLPI FastRPC libraries (dsp/sdsp: fastrpc_shell_2 and the
#   sensor/sysmon skeletons) under dsp/.
# - audio: AW88263S speaker amplifier ACF, installed by
#   hardware.marble.audio. The stock aw882xx_acf.bin without its two
#   ACF_SEC_TYPE_MONITOR sections (vendor HAL battery/temperature monitor,
#   not implemented by the mainline aw88261 driver); register profiles are
#   unchanged. Byte-identical to the community aw88261_acf.bin
#   (github.com/iLtanaka/firmware-xiaomi-marble e76b7ce).
runCommand "marble-firmware"
  {
    outputs = [
      "out"
      "dsp"
      "modem"
      "audio"
      "sensors"
    ];
    nativeBuildInputs = [ python3 ];
    passthru.hasSensorRegistry = true;
    meta = {
      description = "Xiaomi Redmi Note 12 Turbo / POCO F5 OEM GPU, video, radio, DSP and modem firmware";
      priority = 4; # Board firmware must precede generic linux-firmware.
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
      platforms = lib.platforms.linux;
    };
  }
  ''
    source=${firmware-source}
    board=lib/firmware/qcom/sm8475/xiaomi/marble
    for component in adsp audio bluetooth dsp gpu modem sensors slpi video wlan; do
      (cd "$source/$component" && sha256sum -c --quiet SHA256SUMS)
    done

    install -D -m0444 -t "$out/lib/firmware/qcom" \
      "$source/gpu/a730_sqe.fw" "$source/gpu/gmu_gen70000.bin"
    install -D -m0444 -t "$out/$board" "$source/gpu/a730_zap.mbn"
    install -D -m0444 -t "$out/lib/firmware/qcom/vpu" "$source/video/vpu20_4v.mbn"

    # Android's CNSS loads amss20.bin on WCN6855 v2 (Marble: hw2.1).
    wlan="$out/lib/firmware/ath11k/WCN6855/hw2.1"
    install -D -m0444 "$source/wlan/amss20.bin" "$wlan/amss.bin"
    install -D -m0444 -t "$wlan" "$source/wlan/m3.bin" "$source/wlan/regdb.bin"
    install -D -m0444 ${wifiBoardFile} "$wlan/board.bin"

    # btqca asks for the wcn-prefixed WCN6855 names first, then the
    # Android ones; the links keep generic linux-firmware files from
    # taking precedence over these.
    mkdir -p "$out/lib/firmware/qca"
    for file in "$source"/bluetooth/hp*; do
      name=$(basename "$file")
      install -m0444 "$file" "$out/lib/firmware/qca/$name"
      ln -s "$name" "$out/lib/firmware/qca/wcn$name"
    done

    for component in adsp slpi; do
      while read -r checksum filename; do
        install -D -m0444 "$source/$component/$filename" "$dsp/$board/$filename"
      done < "$source/$component/SHA256SUMS"
    done

    mkdir -p "$audio/$board"
    python3 -I ${./acf-without-monitor.py} "$source/audio/aw882xx_acf.bin" \
      "$audio/$board/aw88261_acf.bin"
    ${lib.optionalString (speakerAcfSha256 != null) ''
      echo "${speakerAcfSha256}  $audio/$board/aw88261_acf.bin" | sha256sum -c --quiet
    ''}
    chmod 0444 "$audio/$board/aw88261_acf.bin"

    cp -r ${sensorRegistry}/. "$sensors/"
    chmod -R u+w "$sensors"
    # The SLPI sensor PD loads these through sdsprpcd (ADSP_LIBRARY_PATH
    # /vendor/dsp, mapped to $sensors/dsp by androidDevices.sensors).
    grep ' sdsp/' "$source/dsp/SHA256SUMS" | while read -r checksum filename; do
      install -D -m0444 "$source/dsp/$filename" "$sensors/dsp/''${filename#sdsp/}"
    done
    mkdir -p "$sensors/lib/firmware"

    # tqftpserv resolves /readonly/firmware/image/ next to modem.mdt.
    while read -r checksum filename; do
      install -D -m0444 "$source/modem/$filename" "$modem/$board/$filename"
    done < "$source/modem/SHA256SUMS"
  ''
