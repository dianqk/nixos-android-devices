{
  lib,
  runCommand,
  python3,
  alsa-utils,
  alsa-ucm-conf,
  runtimeAlsaUtils,
  runtimeCoreutils,
  runtimeShell,
  m4,
  fetchFromGitHub,
  mkSSCRegistry,
  firmware-source,
  firmwareVariant ? "android14",
  bluetoothNvm ? null,
  speakerCalibration ? null,
}:
assert lib.assertMsg (builtins.elem firmwareVariant [
  "android14"
  "android16"
]) "Aurora firmware must match an android14 or android16 base";
assert lib.assertMsg (speakerCalibration == null || (
  builtins.all (side: builtins.isInt (speakerCalibration.${side} or null)
    && speakerCalibration.${side} > 0 && speakerCalibration.${side} <= 16777215)
    [ "top" "bottom" ]
)) "Aurora speakerCalibration needs top and bottom factory CAL_R_SEL integers";
let
  calibrationBytes = value: lib.concatStringsSep "," (map toString [
    0
    (builtins.div value 65536)
    (builtins.div value 256 - builtins.div value 65536 * 256)
    (value - builtins.div value 256 * 256)
  ]);
  calibrationSequence = lib.optionalString (speakerCalibration != null) ''
    cset "name='B DSP1 Protection 5f210 CAL_R_SEL' ${calibrationBytes speakerCalibration.bottom}"
    cset "name='T DSP1 Protection 5f210 CAL_R_SEL' ${calibrationBytes speakerCalibration.top}"
  '';
  # Select one coherent OEM release; calibrated Bluetooth data remains explicit.
  source = "${firmware-source}/${firmwareVariant}";
  selectedBluetoothNvm =
    if bluetoothNvm == null then source + "/bluetooth/hmtnv20.b2e" else bluetoothNvm;
  audioSource = "${firmware-source}/android14/audio";
  topologySource = fetchFromGitHub {
    owner = "linux-msm";
    repo = "audioreach-topology";
    rev = "993a17dcb672357998a463a73f120064d6c74f4f";
    hash = "sha256-L2qem2uUvV/AgQRZCl/LOmAdaWyc13pDTlNjEXDtgVc=";
  };
  sensorSource = "${firmware-source}/android14/sensors";
  sensorRegistry = mkSSCRegistry {
    name = "aurora-ssc-registry";
    configDirectory = sensorSource + "/config";
    hwPlatform = "MTP";
    socId = "557";
    registryVersion = "4";
    registryLayout = "file-group";
  };
in
runCommand "aurora-firmware"
  {
    nativeBuildInputs = [ python3 alsa-utils m4 ];
    outputs = [
      "out"
      "sensors"
      "audio"
      "modem"
    ];
    meta = {
      description = "Xiaomi 14 Ultra OEM GPU, video, ADSP, modem and radio firmware";
      priority = 4; # Board firmware must precede generic linux-firmware.
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
      platforms = lib.platforms.linux;
    };
  }
  ''
    cd ${source + "/adsp"}
    sha256sum -c SHA256SUMS
    mkdir -p $out/lib/firmware/qcom/sm8650/xiaomi/aurora
    # Install only the checksummed payloads, not repository metadata.
    while read -r checksum filename; do
      cp -- "$filename" $out/lib/firmware/qcom/sm8650/xiaomi/aurora/
    done < SHA256SUMS
    cd ${source + "/gpu"}
    sha256sum -c SHA256SUMS
    cp gen70900_sqe.fw gmu_gen70900.bin $out/lib/firmware/qcom/
    cp gen70900_zap.mbn $out/lib/firmware/qcom/sm8650/xiaomi/aurora/
    cd ${source + "/video"}
    sha256sum -c SHA256SUMS
    cp vpu33_4v.mbn $out/lib/firmware/qcom/sm8650/xiaomi/aurora/
    cd ${source + "/wlan"}
    sha256sum -c SHA256SUMS
    mkdir -p $out/lib/firmware/ath12k/WCN7850/hw2.0
    cp amss20.bin $out/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin
    cp phy_ucode20.elf $out/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin
    python3 ${./radio-firmware.py} board regdb_xiaomi.bin --bdf bd_n1.elf \
      $out/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
    cd ${source + "/bluetooth"}
    sha256sum -c SHA256SUMS
    python3 ${./radio-firmware.py} nvm ${selectedBluetoothNvm}
    mkdir -p $out/lib/firmware/qca/xiaomi/aurora
    cp hmtbtfw20.tlv $out/lib/firmware/qca/xiaomi/aurora/
    cp ${selectedBluetoothNvm} $out/lib/firmware/qca/xiaomi/aurora/hmtnv20.b2e

    mkdir -p "$audio/lib/firmware/qcom/sm8650"
    ${lib.optionalString (firmwareVariant == "android14") ''
      cd "$TMPDIR"
      # Reuse the pinned upstream I2S graph structure for the legacy TDM endpoint.
      # Only the module ID and ALSA DAI stream name differ in the topology.
      substitute ${topologySource}/audioreach/subgraph-device-i2s-playback.m4 aurora-tdm-playback.m4 \
        --replace-fail 'audioreach/module_i2s.m4' 'aurora-module-tdm.m4' \
        --replace-fail 'MI2S Playback' 'TDM0 Playback'
      substitute ${topologySource}/audioreach/module_i2s.m4 aurora-module-tdm.m4 \
        --replace-fail 'MODULE_ID_I2S_SINK' '0x0700100E' \
        --replace-fail 'MI2S Playback' 'TDM0 Playback'
      m4 -I . -I ${topologySource} ${./audio/Xiaomi-Aurora.m4} > Xiaomi-Aurora.conf
      alsatplg -c Xiaomi-Aurora.conf -o "$audio/lib/firmware/qcom/sm8650/Xiaomi-Aurora-tplg.bin"
      mkdir -p "$audio/share/alsa"
      cp -r ${alsa-ucm-conf}/share/alsa/ucm2 "$audio/share/alsa/"
      chmod -R u+w "$audio/share/alsa/ucm2"
      mkdir -p "$audio/share/alsa/ucm2/Xiaomi/aurora" "$audio/share/alsa/ucm2/conf.d/sm8650"
      cp ${./audio/ucm2}/*.conf "$audio/share/alsa/ucm2/Xiaomi/aurora/"
      mkdir -p "$audio/libexec"
      cat > "$audio/libexec/aurora-wait-speaker-controls" <<'SCRIPT'
#!${runtimeShell}
# wm_adsp registers firmware controls asynchronously after preload returns.
set -eu
attempt=0
while [ "$attempt" -lt 100 ]; do
  if ${runtimeAlsaUtils}/bin/amixer -c "$1" cget "name=B DSP1 Protection 5f210 CAL_R_SEL" >/dev/null 2>&1 &&
     ${runtimeAlsaUtils}/bin/amixer -c "$1" cget "name=T DSP1 Protection 5f210 CAL_R_SEL" >/dev/null 2>&1; then
    exit 0
  fi
  attempt=$((attempt + 1))
  ${runtimeCoreutils}/bin/sleep 0.05
done
printf '%s\n' 'Aurora speaker DSP controls did not become ready' >&2
exit 1
SCRIPT
      chmod +x "$audio/libexec/aurora-wait-speaker-controls"
      substituteInPlace "$audio/share/alsa/ucm2/Xiaomi/aurora/HiFi.conf" \
        --replace-fail '@WAIT_SPEAKER_CONTROLS@' "$audio/libexec/aurora-wait-speaker-controls" \
        --replace-fail "# AURORA_SPEAKER_CALIBRATION" ${lib.escapeShellArg calibrationSequence}
      ln -s ../../Xiaomi/aurora/Xiaomi-Aurora.conf "$audio/share/alsa/ucm2/conf.d/sm8650/Xiaomi-Aurora.conf"
      ln -s ../../Xiaomi/aurora/Xiaomi-Aurora.conf "$audio/share/alsa/ucm2/conf.d/sm8650/xiaomi-Xiaomi14Ultra.conf"
      cd ${audioSource}
      sha256sum -c SHA256SUMS
      cp cs35l43-dsp1-spk-prot.wmfw "$audio/lib/firmware/aurora-cs35l43-dsp1-spk-prot.wmfw"
      for side in B T; do
        lowerSide=$(printf %s "$side" | tr BT bt)
        ln -s aurora-cs35l43-dsp1-spk-prot.wmfw "$audio/lib/firmware/aurora-$lowerSide-cs35l43-dsp1-spk-prot.wmfw"
        cp "$side-cs35l43-dsp1-spk-prot-tt.bin" "$audio/lib/firmware/aurora-$lowerSide-cs35l43-dsp1-spk-prot.bin"
      done
    ''}

    # Modem, IPA and the modem's TFTP read-only tree stay out of the recovery
    # closure. tqftpserv resolves /readonly/firmware/image/ next to modem.mdt.
    mkdir -p "$modem/lib/firmware/qcom/sm8650/xiaomi/aurora"
    ${lib.optionalString (firmwareVariant == "android14") ''
      cd ${source + "/modem"}
      sha256sum -c --quiet SHA256SUMS
      while read -r checksum filename; do
        install -D -m 0444 -- "$filename" "$modem/lib/firmware/qcom/sm8650/xiaomi/aurora/$filename"
      done < SHA256SUMS
    ''}

    # Keep sensor userspace data out of the firmware-only recovery closure.
    mkdir -p "$sensors/lib/firmware"
    ${lib.optionalString (firmwareVariant == "android14") ''
      cd ${sensorSource}
      sha256sum -c SHA256SUMS
      cp -r ${sensorRegistry}/. "$sensors/"
      cp -r dsp "$sensors/dsp"
    ''}
  ''
