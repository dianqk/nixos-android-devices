{
  # Stock LK on slot A loads this header-v4 boot image (boot partition only;
  # the stock vendor_boot, init_boot and dtbo stay). U-Boot finds its own
  # control DT appended to u-boot.bin and takes memory, reservations, the
  # initrd window and the framebuffer from the FDT LK passes in x0.
  platform = "mediatek";
  deviceTree = "mt6897-alldocube-t880";
  # Branch order: later shared patches also touch the T880 DT.
  patches = [
    ../patches/0001-video-Add-proper-handling-for-ARGB8888.patch
    ../patches/0002-reset-Add-TI-SYSCON-based-reset-driver.patch
    ../patches/0003-WIP-phy-phy-mtk-tphy-Force-software-role-switch.patch
    ../patches/0004-arm-mach-mediatek-Add-support-for-MT6897.patch
    ../patches/0005-ufs-ufs-mediatek-Reset-device-by-SMC-call.patch
    ../patches/0006-pinctrl-add-mt6897-driver.patch
    ../patches/0007-The-worst-button-drivers-known-to-man.patch
    ../patches/0008-mach-mediatek-Introduce-mediatek-mobile-board.patch
    ../patches/0009-HACK-ufs-mediatek-disable-clocks.patch
    ../patches/0010-board-mediatek-mobile-run-chainloaded-from-LK-as-a-b.patch
    ../patches/0011-ufs-ufs-mediatek-make-the-bootloader-reset-SMC-optio.patch
    ./patches/0001-arm-dts-mt6897-add-the-Alldocube-iPlay-80-mini-Ultra.patch
    ../patches/0012-button-mtkkp-HACK-read-a-key-s-matrix-state-by-index.patch
    ../patches/0013-configs-mediatek_mobile-service-the-watchdog-xsphy-U.patch
    ./patches/0002-arm-dts-mt6897-alldocube-t880-use-the-measured-board.patch
    ../patches/0014-board-mediatek-mobile-trace-boot-into-pstore-fall-ba.patch
    ../patches/0015-board-mediatek-mobile-optional-reboot-to-fastboot-pr.patch
    ../patches/0016-arm-save_prev_bl_data-keep-save_boot_params-free-of-.patch
    ../patches/0017-board-mediatek-mobile-trace-from-the-first-board-hoo.patch
    ../patches/0018-configs-mediatek_mobile-reset-through-reset_cpu-not-.patch
    ../patches/0019-board-mediatek-mobile-reserve-LK-s-regions-in-LMB-be.patch
    ../patches/0020-configs-mediatek_mobile-enable-the-clock-framework.patch
    ../patches/0021-phy-mediatek-xsphy-release-UTMI-signals-forced-by-th.patch
    ../patches/0022-board-mediatek-mobile-optional-bring-up-autoreset-th.patch
    ../patches/0023-board-mediatek-mobile-take-the-serial-number-from-fi.patch
    ../patches/0024-board-mediatek-mobile-request-stock-bootloader-modes.patch
    ../patches/0025-board-mediatek-mobile-correct-the-A-B-retry-note-of-.patch
    ../patches/0026-board-mediatek-mobile-sleep-in-WFE-while-U-Boot-wait.patch
    ../patches/0027-board-mediatek-mobile-keep-the-previous-console-reco.patch
    ../patches/0028-mach-mediatek-mediatek-mobile-cache-maintenance-by-V.patch
    ../patches/0029-board-mediatek-mobile-flush-all-DRAM-before-booting-.patch
    ../patches/0030-board-mediatek-mobile-restart-the-watchdog-right-bef.patch
    ../patches/0031-board-mediatek-mobile-forward-the-boot-framebuffer-a.patch
    ../patches/0032-board-mediatek-mobile-detect-USB-RAM-recovery-requests.patch
    ../patches/0033-board-mediatek-mobile-mark-the-booted-slot-successfu.patch
    ../patches/0034-board-mediatek-mobile-clear-the-overlay-buffers-LK-l.patch
    ../patches/0035-button-mt6363-poll-PMIF-and-enable-t880-power-key.patch
    ../patches/0036-board-mediatek-mobile-forward-runtime-LK-modem-descriptors.patch
  ];
  environment = ./t880.env;
  # u-boot.bin carries the control DT at _end; LK's own FDT arrives in x0.
  payload = "u-boot.bin";
  # Like the stock kernel: a legacy LZ4 frame that LK decompresses to
  # 0x40000000 (the stock vendor_boot kernel address).
  kernelCompression = "lz4-legacy";
  # The stock boot image has no ramdisk: LK takes the generic ramdisk from
  # init_boot and the vendor ramdisk from vendor_boot.
  emptyRamdisk = true;
  android = {
    # Header v4 holds only kernel, ramdisk and command line; LK takes the
    # load addresses (kernel 0x40000000, ramdisk 0x66f00000, DTB
    # 0x47c80000) and page size from the stock vendor_boot, so the base and
    # offsets passed to mkbootimg are not written to the image.
    headerVersion = 4;
    # boot_a capacity from the device GPT.
    maximumBytes = 67108864;
    # Unlocked LK still loads boot_a through AVB: without a parseable
    # footer and vbmeta (the stock one sits ~16 MB in, beyond our image,
    # until something larger overwrites it) it never loads the headers and
    # asserts. Fill the partition and carry our own unsigned hash footer.
    avbFooter = {
      partitionName = "boot";
      partitionSize = 67108864;
    };
  };
  config = ''
    CONFIG_DEFAULT_DEVICE_TREE="mt6897-alldocube-t880"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/mediatek/mediatek-mobile/t880.env"
    CONFIG_BUTTON_MTK_KP=y
    # The power key uses bounded PMIF reads of MT6363 TOPSTATUS.
    CONFIG_BUTTON_MTK_PMIC=y
    CONFIG_IDENT_STRING=" t880"
    # Read-only checks over USB while waiting in fastboot.
    CONFIG_FASTBOOT_OEM_RUN=y
    CONFIG_CMD_DM=y
    # PSCI queries (AFFINITY_INFO) during bring-up.
    CONFIG_CMD_SMC=y
    # Bring-up without UART or screen: record progress and the console in
    # the stock ramoops console zone (ramoops.mem_address=0x48090000 with
    # 31 x 4 KiB dmesg records before it) and restart the RGU at entry.
    CONFIG_MEDIATEK_MOBILE_ENTRY_TRACE=y
    CONFIG_MEDIATEK_MOBILE_PSTORE_CONSOLE=0x480af000
    CONFIG_MEDIATEK_MOBILE_PSTORE_CONSOLE_SIZE=0x40000
    CONFIG_MEDIATEK_MOBILE_ENTRY_WDT_RESTART=0x1c00a008
    # Mark the booted slot (A) successful in misc once bootefi has loaded
    # /EFI/BOOT/BOOTAA64.EFI from linux-boot; recovery FITs never do.
    CONFIG_PARTITION_TYPE_GUID=y
    CONFIG_MEDIATEK_MOBILE_AB_CONFIRM=y
  '';
}
