dnl SPDX-License-Identifier: BSD-3-Clause
dnl Legacy AudioReach TDM sink module (MODULE_ID_TDM_SINK, 0x0700100E). The
dnl Marble ADSP has no Audio IF module; the kernel reads the interface type,
dnl index, data format and lane from the I2S tokens and the framing from the
dnl Audio IF tokens (sync source, data output, slots, sync mode/inversion/
dnl delay), declared in marble_tdm_tokens.
include(`util/util.m4') dnl
define(`MODULE_ID_TDM_SINK', `0x0700100E') dnl
dnl
`SectionVendorTokens."marble_tdm_tokens" {'
`	AR_TKN_U32_MODULE_ID "200"'
`	AR_TKN_U32_MODULE_INSTANCE_ID "201"'
`	AR_TKN_U32_MODULE_MAX_IP_PORTS "202"'
`	AR_TKN_U32_MODULE_MAX_OP_PORTS "203"'
`	AR_TKN_U32_MODULE_SRC_OP_PORT_ID "206"'
`	AR_TKN_U32_MODULE_DST_IN_PORT_ID "207"'
`	AR_TKN_U32_MODULE_SRC_INSTANCE_ID "208"'
`	AR_TKN_U32_MODULE_DST_INSTANCE_ID "209"'
`	AR_TKN_U32_MODULE_HW_IF_IDX "250"'
`	AR_TKN_U32_MODULE_HW_IF_TYPE "251"'
`	AR_TKN_U32_MODULE_FMT_DATA "253"'
`	AR_TKN_U32_MODULE_SD_LINE_IDX "256"'
`	AR_TKN_U32_MODULE_SYNC_SRC "262"'
`	AR_TKN_U32_MODULE_CTRL_DATA_OUT_ENABLE "263"'
`	AR_TKN_U32_MODULE_SLOT_MASK "264"'
`	AR_TKN_U32_MODULE_NSLOTS_PER_FRAME "265"'
`	AR_TKN_U32_MODULE_SLOT_WIDTH "266"'
`	AR_TKN_U32_MODULE_SYNC_MODE "267"'
`	AR_TKN_U32_MODULE_CTRL_INVERT_SYNC_PULSE "268"'
`	AR_TKN_U32_MODULE_CTRL_SYNC_DATA_DELAY "269"'
`}'
dnl
dnl AR_MODULE_TDM_RX(index, sgidx, container-idx, iid, maxip-ports, max-op-ports,
dnl	src-port, dst-port, hw-if-type, hw-if-idx, fmt, sd-line-idx,
dnl	sync-src, data-out-enable, slot-mask, nslots, slot-width,
dnl	sync-mode, invert-sync, sync-data-delay, stream-name, dst-iid)
define(`AR_MODULE_TDM_RX',
`'
`SectionVendorTuples."NAME_PREFIX.tdm_rx$1_tuples" {'
`        tokens "marble_tdm_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_ID STR(MODULE_ID_TDM_SINK)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR($5)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR($6)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR($7)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR($8)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($22)'
`                AR_TKN_U32_MODULE_HW_IF_TYPE STR($9)'
`                AR_TKN_U32_MODULE_HW_IF_IDX STR($10)'
`                AR_TKN_U32_MODULE_FMT_DATA STR($11)'
`                AR_TKN_U32_MODULE_SD_LINE_IDX STR($12)'
`                AR_TKN_U32_MODULE_SYNC_SRC STR($13)'
`                AR_TKN_U32_MODULE_CTRL_DATA_OUT_ENABLE STR($14)'
`                AR_TKN_U32_MODULE_SLOT_MASK STR($15)'
`                AR_TKN_U32_MODULE_NSLOTS_PER_FRAME STR($16)'
`                AR_TKN_U32_MODULE_SLOT_WIDTH STR($17)'
`                AR_TKN_U32_MODULE_SYNC_MODE STR($18)'
`                AR_TKN_U32_MODULE_CTRL_INVERT_SYNC_PULSE STR($19)'
`                AR_TKN_U32_MODULE_CTRL_SYNC_DATA_DELAY STR($20)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.tdm_rx$1_data" {'
`        tuples "NAME_PREFIX.tdm_rx$1_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.tdm_rx$1" {'
`        index STR($1)'
`        type "aif_in"'
`        no_pm "true"'
`        stream_name "$21"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$2_data"'
`                "NAME_PREFIX.container$3_data"'
`                "NAME_PREFIX.tdm_rx$1_data"'
`        ]'
`}') dnl
