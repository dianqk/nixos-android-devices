dnl SPDX-License-Identifier: BSD-3-Clause
dnl Based on linux-msm/audioreach-topology SM8550-HDK.m4, Linaro Ltd, 2023.
dnl Aurora: Secondary TDM CS35L43 speakers and WCD9395 RX/TX.
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')

STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
`S32_LE', 48000, 48000, 2, 2, 0x4001, 0x4001, 0x6001, `110000')
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
`S16_LE', 48000, 48000, 2, 2, 0x4003, 0x4003, 0x6020, `110000')

DEVICE_SG_ADD(aurora-tdm-playback.m4, `Secondary', SECONDARY_TDM_RX_0,
`S32_LE', 48000, 48000, 2, 2,
LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_SECONDARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
0x4006, 0x4006, 0x6060, `SECONDARY_TDM_RX_0')
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `RX_CODEC_DMA_RX_0', RX_CODEC_DMA_RX_0,
`S16_LE', 48000, 48000, 2, 2,
LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
0x4007, 0x4007, 0x6070)
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
`S16_LE', 48000, 48000, 2, 2,
LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
0x4009, 0x4009, 0x6090)

STREAM_DEVICE_PLAYBACK_MIXER(SECONDARY_TDM_RX_0, ``SECONDARY_TDM_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(SECONDARY_TDM_RX_0, ``SECONDARY_TDM_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_PLAYBACK_MIXER(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``TX_CODEC_DMA_TX_3'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
