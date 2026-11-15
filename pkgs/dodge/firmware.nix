{
  lib,
  runCommand,
  firmware-source,
  includeADSP ? true,
  includeVideo ? true,
}:
let
  firmware = runCommand "dodge-firmware"
    {
      meta = {
        description = "OnePlus 13 firmware, audio profiles and sensor runtime data";
        priority = 4;
        license = lib.licenses.unfree;
        sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
        platforms = lib.platforms.linux;
      };
    }
    ''
      mkdir "$out"
      cp -r ${firmware-source}/. "$out/"
      chmod -R u+w "$out"
      # Keep the shipped profile aligned with the maintained device profile.
      cp ${./audio/ucm2/OnePlus-dodge.conf} "$out/share/alsa/ucm2/OnePlus/dodge/OnePlus-dodge.conf"
      cp ${./audio/ucm2/HiFi.conf} "$out/share/alsa/ucm2/OnePlus/dodge/HiFi.conf"
      ${lib.optionalString (!includeADSP) ''
        rm -f "$out"/lib/firmware/qcom/sm8750/oneplus/dodge/adsp*
      ''}
      ${lib.optionalString (!includeVideo) ''
        rm -f "$out/lib/firmware/qcom/sm8750/oneplus/dodge/vpu35_4v.mbn"
      ''}
      (cd "$out" && find . -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 sha256sum > SHA256SUMS)
    '';
in
firmware // {
  audio = firmware;
  modem = firmware;
  sensors = firmware;
}
