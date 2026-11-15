{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-t880";
  platform = "mediatek";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./kernel.config;
  configOverrides = (import ./trim.nix { inherit lib; }) // {
    MTK_IOMMU = lib.kernel.yes;
    MTK_SCPSYS_DISABLE_UNUSED = lib.kernel.yes;
    # GCE mailbox and CMDQ helper, built in for the built-in mediatek-drm
    MTK_CMDQ_MBOX = lib.kernel.yes;
    MTK_CMDQ = lib.kernel.yes;
    DRM_MEDIATEK_MT6897_VA_BOOTSTRAP = lib.kernel.yes;
    # DisplayPort alt mode on the Type-C port: the DP TX and its PHY, and
    # the AUX character device for DPCD/EDID checks. Built in: the DP_INTF
    # is a component of the built-in display, which would otherwise wait
    # for the modules before the internal panel binds.
    DRM_MEDIATEK_DP = lib.kernel.yes;
    PHY_MTK_DP = lib.kernel.yes;
    DRM_DISPLAY_DP_AUX_CHARDEV = lib.kernel.yes;
    # Cellular groundwork: LK's modem boot information, read-only, loaded
    # by hand
    MTK_CCCI_LK_INFO = lib.kernel.module;
    # the vendor CCCI utility library (modem layout only), loaded by hand
    MTK_CCCI_UTIL = lib.kernel.module;
    # the vendor modem driver (CCIF, DPMAIF, ccmni), loaded by hand; it
    # issues no secure monitor call and does not start the modem
    MTK_ECCCI_DRIVER = lib.kernel.module;
    MTK_NET_CCMNI = lib.kernel.module;
    # SCP (sensor hub) bring-up helper: reports state, releases the reset
    # only on request
    MTK_MT6897_SCP_BRINGUP = lib.kernel.module;
    MTK_MT6897_CCCI_SCP = lib.kernel.module;
    # Bootloader-owned VCP; firmware remains stopped until a session starts.
    MTK_VCP = lib.kernel.module;
    V4L_MEM2MEM_DRIVERS = lib.kernel.yes;
    VIDEO_MEDIATEK_VCP = lib.kernel.module;
    VIDEO_MEDIATEK_VCP_ENCODER = lib.kernel.module;
    # DRAM/vcore scaling: DVFSRC with its vcore regulator and EMI
    # interconnect, started by mtk-dram-bw after its floors (built in, so
    # that DRAM leaves the top level early in boot)
    MTK_DVFSRC = lib.kernel.yes;
    REGULATOR_MTK_DVFSRC = lib.kernel.yes;
    INTERCONNECT_MTK = lib.kernel.yes;
    INTERCONNECT_MTK_DVFSRC_EMI = lib.kernel.yes;
    INTERCONNECT_MTK_MT8196 = lib.kernel.yes;
    MTK_DRAM_BW = lib.kernel.yes;
  };
  patches = import ./series.nix;
  dtbs = [ "mediatek/mt6897-alldocube-t880.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
  ];
  preBuild = ''
    export LD_LIBRARY_PATH="${openssl.out}/lib"
  '';
}
