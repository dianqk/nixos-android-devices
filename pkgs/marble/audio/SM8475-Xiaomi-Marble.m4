dnl SPDX-License-Identifier: BSD-3-Clause
dnl Xiaomi Poco F5 / Redmi Note 12 Turbo (marble), SM7475.
dnl MultiMedia1 plays to two AW88263S amplifiers on the tertiary TDM
dnl interface like the stock group device (96 kHz, 3 channels, slot_mask 7):
dnl 32-bit samples, 4 x 32-bit slots, three channels in slots 0-2 (slot 0
dnl top amplifier, slot 1 bottom, slot 2 the top amplifier's TDM ultrasound
dnl input, driven so that it never reads an idle line), short frame sync
dnl with a one-bit data delay, internal sync, data output on. The device
dnl MFC converts the 48 kHz stereo stream to 96 kHz FL/FR/FC.
dnl MultiMedia3 records from the WCD9385 through TX_CODEC_DMA_TX_3.
dnl Graph layout and container types follow the community topology
dnl (SM8475-Xiaomi-Marble-tplg.bin): the MultiMedia1 stream graph has no
dnl data logging module. Voice graphs are not included.
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')

dnl Playback MultiMedia1
STREAM_SG_PCM_ADD(subgraph-stream-vol-playback-nolog.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl Capture MultiMedia3
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006020, `110000')

dnl Tertiary TDM speaker interface (PARAM_ID_TDM_INTF_CFG values)
define(`TDM_SYNC_SRC', 1) dnl internal
define(`TDM_DATA_OUT_ENABLE', 1)
define(`TDM_SLOT_MASK', 0x7)
define(`TDM_NSLOTS', 4)
define(`TDM_SLOT_WIDTH', 32)
define(`TDM_SYNC_MODE', 0) dnl short sync, bit mode
define(`TDM_INVERT_SYNC', 0)
define(`TDM_SYNC_DATA_DELAY', 1) dnl one bit clock
define(`TDM_STREAM_NAME', `Tertiary TDM0 Playback')
DEVICE_SG_ADD(subgraph-device-tdm-playback.m4, `TERTIARY_TDM_RX_0', TERTIARY_TDM_RX_0,
	`S32_LE', 96000, 96000, 3, 3,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_TERTIARY, 0, DATA_FORMAT_FIXED_POINT,
	0x00004006, 0x00004006, 0x00006060, `TERTIARY_TDM_RX_0')

dnl WCD9385 capture
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
	0x00004009, 0x00004009, 0x00006090)

STREAM_DEVICE_PLAYBACK_MIXER(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0 Audio Mixer'', ``MultiMedia1, stream0.mfc1'')

STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``TX_CODEC_DMA_TX_3'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
