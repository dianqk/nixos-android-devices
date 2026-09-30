{ lib, runCommand, firmware-source }:
let
  source = firmware-source;
  files = [
    "ath12k/WCN7850/hw2.0/amss.bin"
    "ath12k/WCN7850/hw2.0/board-2.bin"
    "ath12k/WCN7850/hw2.0/m3.bin"
    "novatek/novatek_nt36532e_fw.bin"
    "qca/hmtbtfw20.tlv"
    "qca/hmtnv20.bin"
    "qcom/a740_sqe.fw"
    "qcom/gmu_gen70200.bin"
    "qcom/sm8550/Xiaomi-Pad6SPro-tplg.bin"
    "qcom/sm8550/sheng/a740_zap.mbn"
    "qcom/sm8550/sheng/adsp.mbn"
    "qcom/sm8550/sheng/adsp_dtb.mbn"
    "qcom/sm8550/sheng/adspr.jsn"
    "qcom/sm8550/sheng/adsps.jsn"
    "qcom/sm8550/sheng/adspua.jsn"
    "qcom/sm8550/sheng/battmgr.jsn"
    "qcom/sm8550/sheng/cdsp.mbn"
    "qcom/sm8550/sheng/cdsp_dtb.mbn"
    "qcom/sm8550/sheng/cdspr.jsn"
    "qcom/sm8550/sheng/devauth.mbn"
    "qcom/sm8550/sheng/ipa_fws.mbn"
    "qcom/sm8550/sheng/vpu30_4v.mbn"
    "firmware/rfsa/adsp/capi_cirrus_sp.so"
  ];
in
runCommand "sheng-device-firmware" { } ''
  ${lib.concatMapStringsSep "\n" (file: ''
    install -Dm0644 ${source}/${file} "$out/lib/firmware/${
      if lib.hasPrefix "firmware/" file then lib.removePrefix "firmware/" file else file
    }"
  '') files}
  ln -s novatek_nt36532e_fw.bin \
    "$out/lib/firmware/novatek/novatek_nt36532_n81a_fw_csot.bin"
''
