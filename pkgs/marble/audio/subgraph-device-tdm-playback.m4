dnl SPDX-License-Identifier: BSD-3-Clause
dnl Device subgraph for a TDM playback backend, as in the Marble community
dnl topology: the stream mixer feeds an MFC, which converts to the backend
dnl rate, width and channels, and the TDM sink endpoint.
dnl
dnl   Mixer -> [MFC] -> [TDM SINK]
dnl
dnl Uses DEVICE_* from DEVICE_SG_ADD and TDM_* defined by the board file.
include(`audioreach/audioreach.m4') dnl
include(`util/pcm.m4') dnl
include(`audioreach/subgraph.m4') dnl
include(`audioreach/container.m4') dnl
include(`audioreach/module_mfc.m4') dnl
include(`module_tdm.m4') dnl
include(`util/mixer.m4') dnl

undefine(`MFC_MODULE_IID') dnl
undefine(`TDM_MODULE_IID') dnl
undefine(`SG_INDEX') dnl
undefine(`CONTAINER_INDEX') dnl
undefine(`MOD_INDEX') dnl

define(`MFC_MODULE_IID', MOD_IID_START) dnl
define(`TDM_MODULE_IID', eval(MOD_IID_START + 1)) dnl
define(`SG_INDEX', 1) dnl
define(`CONTAINER_INDEX', 1) dnl
define(`MOD_INDEX', 1) dnl

AR_SUBGRAPH(SG_INDEX, DEVICE_DAI_ID, SG_IID_START, APM_SG_PERF_MODE_LOW_LATENCY,
	APM_SUB_GRAPH_DIRECTION_TX, APM_SUB_GRAPH_SID_AUDIO_PLAYBACK)
AR_CONTAINER(CONTAINER_INDEX, CONT_IID_START,
	`ifelse(LPASS_VER_COMPAT, 110000, APM_CONTAINER_TYPE_ID_GC, APM_CONTAINER_CAP_ID_EP)',
	4096, APM_CONT_GRAPH_POS_GLOBAL_DEV, APM_PROC_DOMAIN_ID_ADSP)

AR_MODULE_MFC(MOD_INDEX, SG_INDEX, CONTAINER_INDEX, MFC_MODULE_IID, 1, 1, 1, 2, TDM_MODULE_IID)
AR_MODULE_TDM_RX(MOD_INDEX, SG_INDEX, CONTAINER_INDEX, TDM_MODULE_IID, 1, 0, 1, 0,
	DEVICE_INTF_TYPE, DEVICE_INTF_INDEX, DEVICE_DATA_FORMAT, DEVICE_SD_LINE_IDX,
	TDM_SYNC_SRC, TDM_DATA_OUT_ENABLE, TDM_SLOT_MASK, TDM_NSLOTS, TDM_SLOT_WIDTH,
	TDM_SYNC_MODE, TDM_INVERT_SYNC, TDM_SYNC_DATA_DELAY, TDM_STREAM_NAME, NONE_IID)

dnl TDM_PLAYBACK_ROUTE(stream-index, mixer-prefix, dai-stream-name)
define(`TDM_PLAYBACK_ROUTE',
`'
`SectionGraph."NAME_PREFIX.$1 $2 Graph" {'
`        index STR($1)'
`        lines ['
`                "NAME_PREFIX.mfc$1, , $2 Audio Mixer"'
`                "NAME_PREFIX.tdm_rx$1, , NAME_PREFIX.mfc$1"'
`                "$3, , NAME_PREFIX.tdm_rx$1"'
`        ]'
`}')

TDM_PLAYBACK_ROUTE(MOD_INDEX, `MIXER_PREFIX', `TDM_STREAM_NAME')
