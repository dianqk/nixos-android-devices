{
  baseKernel,
  elfutils,
  lib,
  llvmPackages_23,
  openssl,
  zlib,
}:
{
  pname = "linux-aurora";
  inherit (baseKernel) version modDirVersion src;
  # Broad peripheral baseline; common reductions and SM8650 overrides replace
  # its SoC selections. No Sheng board wiring or clock constraint is inherited.
  configfile = ../../sm8550/sheng/config.aarch64;
  patches = [
    ./board.patch
    ./n1-board.patch
    ./keys.patch
    ./touch.patch
    ./gpu.patch
    ../../patches/gmu-sync-state/0001.patch
    ../../patches/gmu-sync-state/0002.patch
    ../../patches/gmu-sync-state/0003.patch
    ../../patches/gmu-sync-state/0004.patch
    ../../patches/gmu-sync-state/0005.patch
    ./battmgr-property-ids.patch
    ../../patches/power-supply-firmware-readiness.patch
    ./power.patch
    ../../patches/q6apm-probe-readiness.patch
    ../../patches/cs35l43-codec.patch
    ../../patches/cs35l43-dai-clock.patch
    ../../patches/audioreach-legacy-tdm.patch
    ./video.patch
    ../../patches/iris-hfi-gen2-decode-order.patch
    ../../patches/iris-hfi-gen2-capture-pool.patch
    ./radio.patch
    ./audio.patch
    ./audio-codec-clock.patch
    ./optional-supplies.patch
    ./unused-crypto.patch
    ./usb-dp.patch
    ./wifi-qmi-mlo.patch
    ../../patches/ath12k-single-pdev-reg.patch
    ../../patches/pcie-qcom-iommu-cells.patch
    ./n1-panel.patch
    ./n1-transfer.patch
    ./n1-120hz.patch
    ./n1-30hz.patch
    ./cmd-disabled-flush.patch
    ./cmd-multirect.patch
    ./cmd-tearcheck.patch
    ./ufs-mcq.patch
    ./sm8650-mdss-identity.patch
    # Preserve the bootloader-enabled display PLLs during Linux takeover.
    ./lucid-ole-preserve-enabled-pll.patch
    # Upstream linux-next: tie GCC GDSCs to the RPMh CX domain.
    ./gcc-cx-binding.patch
    ./gcc-cx-runtime-pm.patch
    ./gcc-cx-domain.patch
    # MPSS, IPA and rmtfs memory with the stock modem carve-outs.
    ./modem.patch
    # Upstream RFC: IPA v5.5 endpoint IDs and QSB limits as the stock driver
    # (modem downlink went to an endpoint nobody drained).
    ../../patches/ipa-v5.5-config.patch
    # The name server replies HELLO before announcing services, HELLOs are
    # coalesced, and a failed announcement no longer hides the remaining
    # services (the modem then stalled waiting for rmtfs/TFTP).
    ../../patches/qrtr-hello/0021-qrtr-hello-before-services.patch
    ../../patches/qrtr-hello/0022-qrtr-coalesce-hello.patch
    ../../patches/qrtr-hello/qrtr-ns-announce-retry.patch
    # Reassign the exclusive MPSS DSM regions on every start and reclaim them
    # after a successful stop (a restart otherwise hard-reset the phone).
    ../../patches/pas-reassign-exclusive-regions.patch
  ];
  configOverrides = {
    DRM_PANEL_XIAOMI_N1 = lib.kernel.yes;
    TOUCHSCREEN_AURORA_TCM = lib.kernel.module;
    SND_SOC_CS35L43_I2C = lib.kernel.module;
    # The shared RAM recovery intentionally contains no kernel modules.
    TYPEC_MUX_WCD939X_USBSS = lib.kernel.yes;
    # BPF LSM CO-RE programs need kernel type information. Reduced DWARF
    # disables BTF in Kconfig even when the base fragment requests it.
    DEBUG_INFO_REDUCED = lib.kernel.no;
    DEBUG_INFO_BTF = lib.kernel.yes;
    DEBUG_INFO_BTF_MODULES = lib.kernel.yes;
    FONTS = lib.kernel.yes;
    FONT_TER16x32 = lib.kernel.yes;
  };
  dtbs = [ "qcom/sm8650-xiaomi-aurora.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${
      lib.makeLibraryPath [
        openssl
        elfutils
        zlib
      ]
    }"
    # ABL applies hypervisor overlays even when the slot's DTBO is empty.
    "DTC_FLAGS=-@"
  ];
  # Nixpkgs builds resolve_btfids during configuration. Exercise its loader
  # before compiling the kernel so missing host libraries fail immediately.
  preBuild = ''
    btfToolStatus=0
    "$buildRoot/tools/bpf/resolve_btfids/resolve_btfids" --help \
      > "$TMPDIR/resolve-btfids-help" 2>&1 || btfToolStatus=$?
    if test "$btfToolStatus" -ne 129; then
      cat "$TMPDIR/resolve-btfids-help"
      exit 1
    fi
    grep -qi 'usage:.*resolve_btfids' "$TMPDIR/resolve-btfids-help"
  '';
  postConfigure = ''
    for symbol in BLK_DEV_INITRD RD_ZSTD DEVTMPFS USB_DWC3 USB_DWC3_QCOM \
      PHY_SNPS_EUSB2 PHY_QCOM_EUSB2_REPEATER PHY_QCOM_QMP_COMBO \
      USB_CONFIGFS USB_CONFIGFS_ACM USB_DWC3_DUAL_ROLE USB_ROLE_SWITCH \
      USB_XHCI_HCD USB_XHCI_PLATFORM TYPEC_UCSI UCSI_PMIC_GLINK \
      TYPEC_MUX_WCD939X_USBSS QCOM_PMIC_GLINK DRM_MSM_DP \
      REGULATOR_QCOM_RPMH QCOM_SMEM \
      QCOM_COMMAND_DB PINCTRL_SM8650 SM_GCC_8650 SM_TCSRCC_8650 \
      INTERCONNECT_QCOM_SM8650 PSTORE_RAM SCSI_UFSHCD SCSI_UFS_QCOM \
      PHY_QCOM_QMP_UFS SCSI BLK_DEV_SD ARM_QCOM_CPUFREQ_HW \
      DRM_PANEL_XIAOMI_N1 FRAMEBUFFER_CONSOLE FONT_TER16x32 \
      INPUT_EVDEV KEYBOARD_GPIO INPUT_PM8941_PWRKEY PINCTRL_QCOM_SPMI_PMIC \
      DEBUG_INFO_BTF DEBUG_INFO_BTF_MODULES BPF_LSM; do
      grep -q "^CONFIG_$symbol=y$" build/.config
    done
  '';
}
