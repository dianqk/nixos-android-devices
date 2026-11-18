# SPDX-License-Identifier: BSD-3-Clause
# Derived from audioreach-topology/subgraph-device-codec-dma-playback.m4,
# Copyright Linaro Ltd, 2023. LOG -> MFC -> legacy TDM endpoint.
include(`audioreach/audioreach.m4') dnl
include(`audioreach/subgraph.m4') dnl
include(`audioreach/container.m4') dnl
include(`audioreach/module_mfc.m4') dnl
include(`audioreach/module_log.m4') dnl
include(`module_tdm.m4') dnl
define(`LOG_MODULE_IID', MOD_IID_START) dnl
define(`MFC_MODULE_IID', eval(MOD_IID_START + 1)) dnl
define(`TDM_MODULE_IID', eval(MOD_IID_START + 2)) dnl

AR_SUBGRAPH(1, DEVICE_DAI_ID, SG_IID_START, APM_SG_PERF_MODE_LOW_LATENCY, APM_SUB_GRAPH_DIRECTION_RX, APM_SUB_GRAPH_SID_AUDIO_PLAYBACK)
AR_CONTAINER(1, CONT_IID_START, APM_CONTAINER_CAP_ID_EP, 8192, APM_CONT_GRAPH_POS_STREAM, APM_PROC_DOMAIN_ID_ADSP)
AR_MODULE_LOG(1, 1, 1, LOG_MODULE_IID, 1, 1, 1, 2, 0x19ab, 1, 0, MFC_MODULE_IID)
AR_MODULE_MFC(1, 1, 1, MFC_MODULE_IID, 1, 1, 1, 2, TDM_MODULE_IID)
AR_MODULE_TDM_RX(1, 1, 1, TDM_MODULE_IID, `DEVICE_NAME')

define(`UNICORN_DEVICE_PLAYBACK_ROUTE',
`SectionGraph."NAME_PREFIX.TDM Graph" {'
`        index "1"'
`        lines ['
`                "NAME_PREFIX.logger1, , MIXER_PREFIX Audio Mixer"'
`                "NAME_PREFIX.mfc1, , NAME_PREFIX.logger1"'
`                "NAME_PREFIX.tdm_rx1, , NAME_PREFIX.mfc1"'
`                "Tertiary TDM0 Playback, , NAME_PREFIX.tdm_rx1"'
`        ]'
`}')
UNICORN_DEVICE_PLAYBACK_ROUTE
