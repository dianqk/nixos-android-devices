{ lib }:
with lib.kernel;
{
  # The installed system and module-free RAM recovery share this kernel.
  EFI = yes;
  EFI_STUB = yes;
  EFI_GENERIC_STUB = yes;
  EFI_ARMSTUB_DTB_LOADER = yes;
  OF_OVERLAY = yes;
  RD_ZSTD = yes;
  USB_CONFIGFS_ACM = yes;
  USB_CONFIGFS_NCM = yes;
  USB_CONFIGFS_F_FS = yes;
  USB_CONFIGFS_F_HID = yes;
  USB_CONFIGFS_MASS_STORAGE = yes;
  USB_CONFIGFS_F_UVC = yes;
  # uMTP-Responder uses POSIX queues, including inside its PrivateIPC namespace.
  POSIX_MQUEUE = yes;
  USB_ROLE_SWITCH = yes;
  TYPEC = yes;
  TYPEC_UCSI = module;
  UCSI_PMIC_GLINK = module;
  USB_DWC3_GADGET = no;
  USB_DWC3_DUAL_ROLE = yes;
  USB_XHCI_HCD = yes;
  USB_XHCI_PLATFORM = yes;
  SND_USB_AUDIO = module;
  HID = module;
  HID_SUPPORT = yes;
  USB_HID = module;
  HID_GENERIC = module;
  HIDRAW = yes;
  # BlueZ uses userspace HID for Bluetooth keyboards, mice and HID-over-GATT.
  UHID = module;
  USB_STORAGE = module;
  USB_UAS = module;
  USB_NET_DRIVERS = yes;
  USB_USBNET = module;
  USB_NET_CDCETHER = module;
  USB_NET_CDC_NCM = module;
  USB_NET_RNDIS_HOST = module;
  USB_RTL8152 = module;
  USB_NET_AX8817X = module;
  USB_NET_AX88179_178A = module;
  # Dependencies for the shared NixOS reverse-path firewall matches.
  IP_NF_IPTABLES = module;
  IP6_NF_IPTABLES = module;
  NFT_COMPAT = module;
  NF_TABLES = yes;
  NF_TABLES_INET = yes;
  NF_CONNTRACK = yes;
  NFT_CT = yes;
  NFT_NAT = yes;
  NFT_MASQ = yes;
  NET = yes;
  INET = yes;
  PACKET = yes;
  UNIX = yes;
  VFAT_FS = yes;
  FAT_FS = yes;
  NLS_CODEPAGE_437 = yes;
  NLS_ISO8859_1 = yes;
  EXT4_FS = yes;
  DEVTMPFS = yes;
  DEVTMPFS_MOUNT = yes;
  # Expose the board RTC for wake alarms.
  RTC_INTF_DEV = yes;
  RTC_INTF_SYSFS = yes;
  # NixOS compresses stage-2 firmware with zstd.
  FW_LOADER_COMPRESS = yes;
  FW_LOADER_COMPRESS_ZSTD = yes;
  MAGIC_SYSRQ = yes;
  MAGIC_SYSRQ_SERIAL = no;

  # Let the UFS driver bind the separate inline crypto engine.
  BLK_INLINE_ENCRYPTION = yes;
  SCSI_UFS_CRYPTO = yes;
  QCOM_INLINE_CRYPTO_ENGINE = yes;

  # Three CPU frequency policies and the GPU provide passive cooling.
  CPU_THERMAL = yes;
  CPU_FREQ_THERMAL = yes;
  DEVFREQ_THERMAL = yes;

  # Display and touch must be available before the root filesystem is mounted.
  FRAMEBUFFER_CONSOLE = yes;
  DRM_FBDEV_EMULATION = yes;
  DRM = yes;
  DRM_MSM = yes;
  DRM_MSM_DSI = yes;
  DRM_MSM_DSI_7NM_PHY = yes;
  DRM_PANEL_XIAOMI_L2S_380C0A = yes;
  BACKLIGHT_CLASS_DEVICE = yes;
  VT = yes;
  VT_CONSOLE = yes;
  INPUT_TOUCHSCREEN = yes;
  TOUCHSCREEN_ST_FTS_SPI = yes;
  SPI = yes;
  SPI_QCOM_GENI = yes;

  # DSP services, battery reporting and the WCD938x / CS35L41 audio paths.
  REMOTEPROC = yes;
  QCOM_Q6V5_PAS = module;
  RPMSG_QCOM_GLINK_SMEM = module;
  RPMSG_QCOM_SMD = module;
  QRTR = module;
  QRTR_SMD = module;
  QCOM_PD_MAPPER = module;
  QCOM_FASTRPC = module;
  QCOM_PMIC_GLINK = module;
  BATTERY_QCOM_BATTMGR = module;
  QCOM_APR = module;
  SOUND = yes;
  SND = module;
  SND_SOC = module;
  SND_SOC_QCOM = module;
  SOUNDWIRE = module;
  SOUNDWIRE_QCOM = module;
  SND_SOC_SC8280XP = module;
  SND_SOC_WCD938X_SDW = module;
  SND_SOC_CS35L41_I2C = module;
  SND_SOC_LPASS_RX_MACRO = module;
  SND_SOC_LPASS_TX_MACRO = module;
  SND_SOC_LPASS_VA_MACRO = module;

  # PCIe and UART radio hosts, with one shared external power sequencer.
  PCI = yes;
  PCI_MSI = yes;
  PCIE_QCOM = yes;
  PHY_QCOM_QMP_PCIE = yes;
  POWER_SEQUENCING = yes;
  POWER_SEQUENCING_XIAOMI_UNICORN = module;
  PCI_PWRCTRL_PWRSEQ = module;
  WLAN = yes;
  WLAN_VENDOR_ATH = yes;
  CFG80211 = module;
  # wpa_supplicant's systemd sandbox binds /dev/rfkill.
  RFKILL = yes;
  MAC80211 = module;
  ATH11K = module;
  ATH11K_PCI = module;
  BT = module;
  # HFP uses RFCOMM for AT commands in addition to the SCO audio transport.
  BT_RFCOMM = module;
  SERIAL_QCOM_GENI = yes;
  SERIAL_DEV_BUS = yes;
  SERIAL_DEV_CTRL_TTYPORT = yes;
  BT_HCIUART = module;
  BT_HCIUART_SERDEV = yes;
  BT_HCIUART_QCA = yes;

  # Native RAW10: S5KJN1 ultra/tele, OV32B40 front, IMX707 C-PHY main.
  SM_CAMCC_8450 = yes;
  MEDIA_SUPPORT = module;
  MEDIA_CAMERA_SUPPORT = yes;
  MEDIA_PLATFORM_SUPPORT = yes;
  V4L_PLATFORM_DRIVERS = yes;
  VIDEO_DEV = module;
  VIDEO_QCOM_CAMSS = module;
  VIDEO_UNICORN_SENSORS = module;
  V4L2_CCI_I2C = module;
  V4L2_FWNODE = module;
  MEDIA_CONTROLLER = yes;
  VIDEO_V4L2_SUBDEV_API = yes;
  PHY_QCOM_MIPI_CSI2 = module;
  I2C_QCOM_CCI = module;
  MFD_QCOM_PM8008 = module;
  REGULATOR_QCOM_PM8008 = module;
  # libcamera's software ISP allocates userspace buffers from /dev/dma_heap/system.
  DMABUF_HEAPS = yes;
  DMABUF_HEAPS_SYSTEM = yes;

  # Normal-mode NFC, force feedback and the SPI infrared transmitter.
  NFC = module;
  NFC_NCI = module;
  NFC_SN_NCI_I2C = module;
  INPUT_MISC = yes;
  INPUT_AW86927 = module;
  RC_CORE = module;
  RC_DEVICES = yes;
  LIRC = yes;
  IR_SPI = module;
}
