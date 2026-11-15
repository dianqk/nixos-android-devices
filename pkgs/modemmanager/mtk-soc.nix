# ModemManager 1.24.2 with the MediaTek SoC (CCCI/MIPC) plugin of the MT6895
# mainline project: AT control over the CCCI tty, SIM, registration, SMS and
# MIPC direct-IP data on ccmni. For MediaTek CCCI devices only; other devices
# keep nixpkgs' ModemManager.
{
  lib,
  modemmanager,
  fetchurl,
}:
assert lib.versions.majorMinor modemmanager.version == "1.24";
modemmanager.overrideAttrs (old: {
  pname = "modemmanager-mtk-soc";
  patches = (old.patches or [ ]) ++ [
    # "plugins: add MediaTek SoC CCCI and MIPC integration" (Furruka,
    # 2026-10-02), the one plugin commit of the mtk-soc-1.24.2 branch on top
    # of the 1.24.2 release; fetched verbatim with its author and message.
    (fetchurl {
      url = "https://github.com/MT6895-Mainline/modemmanager-mtk-soc/commit/53661270e68567c4a929be8befdd1699671304d9.patch";
      hash = "sha256-AlH5giMKZHstLNW0Il8kMETiNJs0yI4z2JUzUp+Jaf0=";
    })
    # Local: access technology from +COPS (NR was reported as GSM).
    ./mtk-soc-access-technology-from-cops.patch
    # Local: MT6897 data-call confirmations carry empty type-0 filler TLVs.
    ./mtk-soc-mipc-empty-type0-filler.patch
    # Local: allowed modes and the initial attach APN through MIPC (the
    # modem does not register on LTE without an attach APN).
    ./mtk-soc-modes-initial-attach-apn.patch
    # Local: AT+CFUN=4 radio power-down (for the attach APN update) and a
    # bounded AT+CMGF=0 retry while the SMS service starts.
    ./mtk-soc-power-down-cmgf-retry.patch
    # Local: report the attach APN that was set until the modem lists it.
    ./mtk-soc-initial-attach-apn-reload.patch
    # Local: enable the modem's own IMS for SMS on 5G SA (AT+EIMSCFG).
    ./mtk-soc-modem-ims-sms.patch
  ];
  mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dplugin_mtk_soc=enabled" ];
  meta = old.meta // {
    description = "${old.meta.description} (with the MediaTek SoC CCCI plugin)";
  };
})
