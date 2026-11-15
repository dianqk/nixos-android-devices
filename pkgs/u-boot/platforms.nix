# Upstream base configuration and shared patches per U-Boot platform. Boards
# select a platform explicitly; Qualcomm-only drivers and boot-action
# protocols are not applied to other platforms.
{
  qualcomm = {
    defconfig = "qcom_defconfig";
    baseConfig = "board/qualcomm/qcom-phone.config";
    environmentDirectory = "board/qualcomm";
    bootActions = true;
    patches = [
      ./patches/0001-acm-stop-cancelled-rx.patch
      ./patches/0002-acm-nonblocking-console.patch
      ./patches/0003-button-kbd-events.patch
      ./patches/0004-spmi-single-byte.patch
      ./patches/0005-pmic-gpio-input-state.patch
      ./patches/0006-simplefb-optional-properties.patch
      ./patches/0007-mobile-boot-action-protocol.patch
      ./patches/0008-mobile-ufs-boot-lun.patch
      ./patches/0009-mobile-qcom-ab-efi-confirm.patch
      ./patches/0010-acm-initialize-stdio.patch
      ./patches/0011-mobile-ufs-descriptor-length.patch
      ./patches/0012-mobile-ufs-hpb-lu-enable.patch
    ];
  };
  # Chainloaded by MediaTek LK as an Android boot-image kernel. The board
  # directory and defconfig come from the SoC patch series.
  mediatek = {
    defconfig = "mediatek_mobile_defconfig";
    baseConfig = null;
    environmentDirectory = "board/mediatek/mediatek-mobile";
    bootActions = false;
    patches = [
      ./patches/0001-acm-stop-cancelled-rx.patch
      ./patches/0002-acm-nonblocking-console.patch
      ./patches/0003-button-kbd-events.patch
      ./patches/0006-simplefb-optional-properties.patch
      ./patches/0010-acm-initialize-stdio.patch
    ];
  };
}
