/* SPDX-License-Identifier: GPL-2.0-only */
/* Packet layout from MediaTek's mtk-btcvsd.c, Copyright 2019 MediaTek Inc.
 * KaiChieh Chuang <kaichieh.chuang@mediatek.com>.
 * https://github.com/MiCode/MTK_kernel_device_modules/blob/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/sound/soc/mediatek/common/mtk-btcvsd.c
 * New bounded helpers; no normal-memory accesses to MMIO are made here.
 */
#ifndef BTMTK_BTCVSD_LAYOUT_H
#define BTMTK_BTCVSD_LAYOUT_H
struct btcvsd_layout {
	unsigned int bytes, blocks, valid[6];
};
static const struct btcvsd_layout btcvsd_layouts[] = {
	{ 30, 6, { 1, 2, 4, 8, 16, 32 } },
	{ 60, 3, { 1, 1, 2, 2, 4, 4 } },
	{ 90, 2, { 1, 1, 1, 2, 2, 2 } },
	{ 120, 1, { 1, 1, 1, 1, 0, 0 } },
	{ 10, 18, { 7, 0x38, 0x1c0, 0xe00, 0x7000, 0x38000 } },
	{ 20, 9, { 3, 6, 0x18, 0x30, 0xc0, 0x180 } },
};
static inline unsigned int btcvsd_payload(unsigned int layout)
{
	return layout < 6 ? btcvsd_layouts[layout].bytes *
				    btcvsd_layouts[layout].blocks :
			    0;
}
static inline unsigned int btcvsd_stride(unsigned int layout)
{
	unsigned int n;
	if (layout >= 6)
		return 0;
	n = btcvsd_layouts[layout].bytes;
	return n + ((n == 30 || n == 90 || n == 10) ? 2 : 0);
}
static inline int btcvsd_address(unsigned int addr, unsigned int layout,
				 unsigned int size, unsigned int *offset)
{
	unsigned int start = addr & 0xffff, span;
	if (layout >= 6 || addr == 0xdeadfeed || (addr & 1))
		return 0;
	if (btcvsd_stride(layout) == btcvsd_layouts[layout].bytes && (addr & 3))
		return 0;
	span = btcvsd_stride(layout) * btcvsd_layouts[layout].blocks;
	if (start > size || span > size - start)
		return 0;
	*offset = start;
	return 1;
}
static inline int btcvsd_valid(unsigned int ctl, unsigned int layout,
			       unsigned int chunk)
{
	unsigned int mask;
	if (layout >= 6 || chunk >= btcvsd_payload(layout) / 30)
		return 0;
	mask = btcvsd_layouts[layout].valid[chunk];
	return (ctl & mask) == mask;
}
static inline int btcvsd_msbc(const unsigned char *data)
{
	return data[0] == 1 &&
	       (data[1] == 8 || data[1] == 0x38 || data[1] == 0xc8 ||
		data[1] == 0xf8) &&
	       data[2] == 0xad && data[59] == 0;
}
/* Production/test shared access walker: contiguous layouts use 32-bit MMIO;
 * padded layouts use 16-bit MMIO and never touch the two-byte holes. */
static inline int
btcvsd_copy(unsigned int layout, void *io, unsigned char *data,
	    unsigned int capacity, int to_sram,
	    unsigned int (*read_io)(void *, unsigned int, unsigned int),
	    void (*write_io)(void *, unsigned int, unsigned int, unsigned int))
{
	unsigned int i, j, k, width, value, pos, n, stride;
	if (layout >= 6 || capacity < btcvsd_payload(layout))
		return 0;
	n = btcvsd_layouts[layout].bytes;
	stride = btcvsd_stride(layout);
	width = stride == n ? 4 : 2;
	for (i = 0; i < btcvsd_layouts[layout].blocks; i++) {
		for (j = 0; j < n; j += width) {
			pos = i * n + j;
			if (to_sram) {
				value = 0;
				for (k = 0; k < width; k++)
					value |= (unsigned int)data[pos + k]
						 << (8 * k);
				write_io(io, i * stride + j, width, value);
			} else {
				value = read_io(io, i * stride + j, width);
				for (k = 0; k < width; k++)
					data[pos + k] =
						(unsigned char)(value >>
								(8 * k));
			}
		}
	}
	return 1;
}

#define BTCVSD_TX_BYTES 1080
#define BTCVSD_TX_PACKETS 64
struct btcvsd_txq {
	unsigned char bytes[BTCVSD_TX_BYTES];
	unsigned short remaining[BTCVSD_TX_PACKETS];
	unsigned int head, used, first, packets, generation;
};
static inline unsigned int btcvsd_tx_reset(struct btcvsd_txq *q,
					   unsigned int generation)
{
	unsigned int dropped = q->packets;
	q->head = q->used = q->first = q->packets = 0;
	q->generation = generation;
	return dropped;
}
static inline int btcvsd_tx_push(struct btcvsd_txq *q, unsigned int generation,
				 const unsigned char *data, unsigned int length)
{
	unsigned int i;
	if (generation != q->generation || !length || length > 255 ||
	    length > BTCVSD_TX_BYTES - q->used ||
	    q->packets == BTCVSD_TX_PACKETS)
		return 0;
	for (i = 0; i < length; i++)
		q->bytes[(q->head + q->used + i) % BTCVSD_TX_BYTES] = data[i];
	q->remaining[(q->first + q->packets) % BTCVSD_TX_PACKETS] = length;
	q->used += length;
	q->packets++;
	return 1;
}
static inline int btcvsd_tx_peek(const struct btcvsd_txq *q,
				 unsigned int generation, unsigned char *data,
				 unsigned int length)
{
	unsigned int i;
	if (generation != q->generation || length > q->used)
		return 0;
	for (i = 0; i < length; i++)
		data[i] = q->bytes[(q->head + i) % BTCVSD_TX_BYTES];
	return 1;
}
/* Returns completed host packets, not bytes or firmware frames. */
static inline int btcvsd_tx_pop(struct btcvsd_txq *q, unsigned int generation,
				unsigned int length)
{
	unsigned int n, done = 0;
	if (generation != q->generation || length > q->used)
		return -1;
	q->head = (q->head + length) % BTCVSD_TX_BYTES;
	q->used -= length;
	while (length) {
		n = q->remaining[q->first];
		if (length < n) {
			q->remaining[q->first] -= length;
			break;
		}
		length -= n;
		q->remaining[q->first] = 0;
		q->first = (q->first + 1) % BTCVSD_TX_PACKETS;
		q->packets--;
		done++;
	}
	return (int)done;
}

/* Find a full H2/mSBC frame without assuming an initial byte alignment.
 * Keep the final59 bytes when no complete header/frame can be recognized. */
static inline int btcvsd_tx_frame(struct btcvsd_txq *q, unsigned int generation,
				  unsigned char frame[60],
				  unsigned int *discarded)
{
	if (generation != q->generation)
		return 0;
	while (q->used >= 60) {
		btcvsd_tx_peek(q, generation, frame, 60);
		if (btcvsd_msbc(frame)) {
			btcvsd_tx_pop(q, generation, 60);
			return 1;
		}
		btcvsd_tx_pop(q, generation, 1);
		(*discarded)++;
	}
	return 0;
}
/* Retain complete frames until the requested firmware batch is available. */
static inline int btcvsd_tx_batch(struct btcvsd_txq *q, unsigned int generation,
				  unsigned char batch[180],
				  unsigned int *staged, unsigned int count,
				  unsigned int *discarded)
{
	unsigned char frame[60];
	if (generation != q->generation || (count != 120 && count != 180) ||
	    *staged > 180 || *staged % 60)
		return 0;
	while (*staged < count &&
	       btcvsd_tx_frame(q, generation, frame, discarded)) {
		unsigned int i;
		for (i = 0; i < 60; i++)
			batch[*staged + i] = frame[i];
		*staged += 60;
	}
	return *staged >= count;
}
#define BTCVSD_RX_BYTES 360
struct btcvsd_rxq {
	unsigned char bytes[BTCVSD_RX_BYTES], valid[BTCVSD_RX_BYTES];
	unsigned int head, used, generation, synced;
};
static inline void btcvsd_rx_reset(struct btcvsd_rxq *q,
				   unsigned int generation)
{
	q->head = q->used = q->synced = 0;
	q->generation = generation;
}
static inline int btcvsd_rx_push(struct btcvsd_rxq *q, unsigned int generation,
				 const unsigned char *data, unsigned int layout,
				 unsigned int ctl)
{
	unsigned int i, n = btcvsd_payload(layout), pos;
	if (generation != q->generation || !n || n > BTCVSD_RX_BYTES - q->used)
		return 0;
	for (i = 0; i < n; i++) {
		pos = (q->head + q->used + i) % BTCVSD_RX_BYTES;
		q->bytes[pos] = data[i];
		q->valid[pos] = btcvsd_valid(ctl, layout, i / 30);
	}
	q->used += n;
	return 1;
}
static inline int btcvsd_rx_frame(struct btcvsd_rxq *q, unsigned int generation,
				  unsigned char frame[60], unsigned int *status,
				  unsigned int *discarded)
{
	unsigned int i, valid;
	if (generation != q->generation)
		return 0;
	while (q->used >= 60) {
		valid = 0;
		for (i = 0; i < 60; i++) {
			/* Core HCI 5.4.3: missing octets are zero, including H2.
			 * Invalid SRAM headers must not establish synchronization.
			 */
			unsigned int present =
				q->valid[(q->head + i) % BTCVSD_RX_BYTES];
			frame[i] = present ? q->bytes[(q->head + i) %
						      BTCVSD_RX_BYTES] :
					     0;
			valid += present;
		}
		if (q->synced || btcvsd_msbc(frame)) {
			q->synced = 1;
			*status = valid == 60 ? 0 : valid ? 3 : 2;
			if (!btcvsd_msbc(frame) && !*status)
				*status = 1;
			q->head = (q->head + 60) % BTCVSD_RX_BYTES;
			q->used -= 60;
			return 1;
		}
		q->head = (q->head + 1) % BTCVSD_RX_BYTES;
		q->used--;
		(*discarded)++;
	}
	return 0;
}

static inline int btcvsd_control(unsigned int ctl)
{
	return ctl != 0xdeadfeed && (ctl & (1u << 31)) && ((ctl >> 18) & 7) < 6;
}
static inline int btcvsd_supported(unsigned int air, unsigned int flowctl,
				   unsigned int codec)
{
	return air == 3 && !flowctl && codec == 2;
}
static inline int btcvsd_cvsd_supported(unsigned int air, unsigned int flowctl,
					unsigned int codec)
{
	/* HCI voice-setting bits (CVSD=0), not event air_mode (CVSD=2). */
	return air == 0 && !flowctl && codec == 1;
}
static inline unsigned int btcvsd_sco_header(const unsigned char header[3],
					     unsigned int total,
					     unsigned int handle)
{
	unsigned int raw;
	if (total < 3)
		return 0;
	raw = header[0] | ((unsigned int)header[1] << 8);
	return total >= 3 && !(raw & 0xf000) && raw == handle && header[2] &&
			       total == 3u + header[2] ?
		       header[2] :
		       0;
}
#endif
