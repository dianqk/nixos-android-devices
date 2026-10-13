{
  bootActionProfile = "pon";
  deviceTree = "qcom/sdm845-xiaomi-polaris";
  patches = [
    ./patches/0001-polaris-abl-framebuffer.patch
    ./patches/0002-video-scale-bitmap-console-fonts.patch
  ];
  chargerEnvironment = true;
  environment = ./polaris.env;
  config = ''
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sdm845-xiaomi-polaris"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/polaris.env"
    # CONFIG_VIDEO_FONT_16X32 is not set
    CONFIG_VIDEO_FONT_8X16=y
    CONFIG_VIDEO_FONT_SCALE=3
    # CONFIG_NO_FB_CLEAR is not set
  '';
}
