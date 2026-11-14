# SPDX-License-Identifier: BSD-3-Clause
# Combined WCD and 96 kHz speaker transport; no amplifier calibration or activation.
# Fixed Unicorn TDM parameters and provenance: provenance.json.
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
include(`tdm-parameters.m4')

# Graph IDs are ALSA DAI IDs; all instance IDs below are host-allocated.
STREAM_SG_PCM_ADD(subgraph-stream-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
    `S16_LE', 48000, 48000, 2, 2,
    0x4001, 0x5001, 0x6001)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
    `S16_LE', 48000, 48000, 1, 2,
    0x4002, 0x5002, 0x6020)

DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `RX_CODEC_DMA_RX_0', RX_CODEC_DMA_RX_0,
    `S16_LE', 48000, 48000, 2, 2,
    LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
    0x4003, 0x5003, 0x6040)
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
    `S16_LE', 48000, 48000, 1, 2,
    LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
    0x4004, 0x5004, 0x6060)

STREAM_DEVICE_PLAYBACK_MIXER(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``TX_CODEC_DMA_TX_3'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``TX_CODEC_DMA_TX_3, device120.logger1'')

# Dedicated frontend5 accepts exactly L/R/zero at 96 kHz/3ch S16_LE.
# No 2ch-to-3ch upmix or independent ultrasound source is included.
STREAM_SG_PCM_ADD(subgraph-stream-playback.m4, FRONTEND_DAI_MULTIMEDIA5,
    `S16_LE', 96000, 96000, 3, 3,
    0x4010, 0x5010, 0x6100)
DEVICE_SG_ADD(subgraph-device-tdm-playback.m4, `Tertiary TDM0', TERTIARY_TDM_RX_0,
    `S24_LE', 96000, 96000, 3, 3,
    LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_TERTIARY, 0, DATA_FORMAT_FIXED_POINT,
    0x4011, 0x5011, 0x6120, `TERTIARY_TDM_RX_0')
STREAM_DEVICE_PLAYBACK_MIXER(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0'', ``MultiMedia5'')
STREAM_DEVICE_PLAYBACK_ROUTE(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0 Audio Mixer'', ``MultiMedia5, stream4.logger1'')
