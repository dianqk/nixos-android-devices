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
    ../../patches/iris-hfi-gen2-deblocking.patch
    ../../patches/iris-hfi-gen2-error-timestamps.patch
    ../../patches/iris-hfi-gen2-noshow.patch
    ./radio.patch
    ./audio.patch
    ./audio-codec-clock.patch
    ./optional-supplies.patch
    ./unused-crypto.patch
    ./usb-dp.patch
    ./wifi-qmi-mlo.patch
    ../../patches/ath12k-single-pdev-reg.patch
    ../../patches/pcie-qcom-iommu-cells.patch
    # armada: optional PCIe-memory sleep-set vote (suspend-only OPP) in
    # s2idle; a fallback since the link is torn down (patches below), off by
    # default (pcie_qcom.suspend_opp_floor).
    ./pcie-suspend-opp-floor.patch
    ./pcie-suspend-opp.patch
    ./n1-panel.patch
    ./n1-transfer.patch
    ./n1-120hz.patch
    ./n1-30hz.patch
    ./n1-boot-power-cycle.patch
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
    # Charger type from the OEM adapter-type field, charge counter in uAh and
    # no battery ID resistor as internal resistance.
    ./battmgr-reporting.patch
    # Charge thresholds with the firmware's charge-control enable, errors
    # returned; writable charge current cap (uA) for thermal limiting.
    ./battmgr-charge-control.patch
    # ADSP charger log (fcc/icl votes) through dynamic debug.
    ./battmgr-adsp-log.patch
    # USB input current limit from the configured gadget current (dwc3
    # usb-psy-name), instead of the firmware's unconfigured 100 mA SDP limit.
    ./battmgr-usb-icl.patch
    ./usb-psy-name.patch
    # Power the touch controller off while the panel is off.
    ./touch-panel-follower.patch
    # Firmware touch reports (0x11) through input-mt; no controller firmware pin.
    ./touch-controller-firmware.patch
    # Generic: the DSI PHY kept its interface clock prepared (pm_clk), which
    # held the display clock controller and MMCX on with the display off.
    ../../patches/dsi-phy-iface-clk-runtime-pm.patch
    # Write-combined ramoops with oops/panic records in the stock region.
    ./ramoops.patch
    # pcie_qcom.suspend_opp_floor=off (default)|full|cx|bw selects the votes.
    ./pcie-suspend-floor-modes.patch
    # armada: tear the WLAN link down in s2idle (root port no longer vetoes
    # D3cold) and let the PCIe GDSCs power off.
    ./pci-host-common-endpoint-d3cold.patch
    ./pcie-gdsc-off.patch
    # Debug: AOP low-power monitor log (which requestors block AOSS sleep).
    ./aop-lpm-monitor.patch
    # Debug, opt-in: PCIe CESTA power-control override (qcom_pm_vx.pcie_sm_override).
    ./pcie-sm-override.patch
    # Sony IMX858 (fixed 4096x3072 RAW10 mode) and the ultra-wide camera
    # on CCI0/CSIPHY1.
    ./imx858.patch
    ./camera-ultra.patch
    # OmniVision OV32B40 (fixed 3264x2448 RAW10 mode); tele 3.2x IMX858 on
    # CCI1/CSIPHY5 and the front OV32B40 on QUP SE9 I2C/CSIPHY4.
    ./ov32b40.patch
    ./camera-tele-front.patch
    # Stop the started subdevs when a CAMSS stream fails to start or stop.
    ../../patches/camss-stream-unwind.patch
    # Upstream series (v9): CAMSS C-PHY support.
    ../../patches/camss-cphy/0001.patch
    ../../patches/camss-cphy/0002.patch
    ../../patches/camss-cphy/0003.patch
    ../../patches/camss-cphy/0004.patch
    ../../patches/camss-cphy/0005.patch
    ../../patches/camss-cphy/0006.patch
    ../../patches/camss-cphy/0007.patch
    ../../patches/camss-cphy/0008.patch
    ../../patches/camss-cphy/0009.patch
    # SM8650 C-PHY lane settings from the Qualcomm camera kernel.
    ../../patches/camss-sm8650-cphy.patch
    # Sony LYT-900 (fixed 4096x3072 mode); wide on CSIPHY0 and tele 5x on
    # CSIPHY3, both C-PHY.
    ./lyt900.patch
    ./camera-wide-tele5x.patch
    # C-PHY on gen3 CSIDs and the C-PHY CSIPHY clock rate.
    ../../patches/camss-csid-gen3-cphy.patch
    ../../patches/camss-csiphy-cphy-clock.patch
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
    # Hypervisor watchdog, registered by qcom_scm under Gunyah (no DT node);
    # built in so systemd's runtime watchdog can arm it from early boot.
    GUNYAH_WATCHDOG = lib.kernel.yes;
    QCOM_PM_VX = lib.kernel.module;
    # Ultra-wide camera: CAMSS and CCI come from the base configuration.
    VIDEO_IMX858 = lib.kernel.module;
    VIDEO_OV32B40 = lib.kernel.module;
    VIDEO_LYT900 = lib.kernel.module;
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
  # Build resolve_btfids (`prepare`; nixpkgs no longer runs it while
  # configuring) and exercise its loader before compiling the kernel, so
  # missing host libraries fail immediately.
  preBuild = ''
    make "''${makeFlags[@]}" -j"$NIX_BUILD_CORES" prepare
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
      DEBUG_INFO_BTF DEBUG_INFO_BTF_MODULES BPF_LSM GUNYAH_WATCHDOG \
      SM_CAMCC_8650; do
      grep -q "^CONFIG_$symbol=y$" "$buildRoot"/.config
    done
    for symbol in VIDEO_QCOM_CAMSS I2C_QCOM_CCI VIDEO_IMX858 VIDEO_OV32B40 VIDEO_LYT900; do
      grep -q "^CONFIG_$symbol=[ym]$" "$buildRoot"/.config
    done
  '';
}
