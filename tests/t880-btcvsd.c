/* SPDX-License-Identifier: GPL-2.0-only */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "btcvsd-layout.h"
static unsigned int read_io(void *p, unsigned int pos, unsigned int width)
{
	unsigned char *data = p;
	unsigned int i, value = 0;
	for (i = 0; i < width; i++)
		value |= (unsigned int)data[pos + i] << (8 * i);
	return value;
}
static void write_io(void *p, unsigned int pos, unsigned int width,
		     unsigned int value)
{
	unsigned char *data = p;
	unsigned int i;
	for (i = 0; i < width; i++)
		data[pos + i] = (unsigned char)(value >> (8 * i));
}
int main(void)
{
	unsigned int i, j, k, offset;
	unsigned char sram[256], payload[180], restored[180];
	for (i = 0; i < 6; i++) {
		unsigned int len = btcvsd_payload(i), stride = btcvsd_stride(i),
			     n = btcvsd_layouts[i].bytes;
		assert(len == (i == 3 ? 120 : 180));
		assert(btcvsd_address(0x18840000, i, 0x20000, &offset) &&
		       offset == 0);
		assert(!btcvsd_address(0xdeadfeed, i, 0x20000, &offset));
		assert(!btcvsd_address(3, i, 0x20000, &offset));
		assert(btcvsd_address(2, i, 0x20000, &offset) == (stride != n));
		assert(!btcvsd_address(
			0, i, stride * btcvsd_layouts[i].blocks - 1, &offset));
		assert(btcvsd_address(0, i, stride * btcvsd_layouts[i].blocks,
				      &offset));
		memset(sram, 0xa5, sizeof(sram));
		for (j = 0; j < len; j++)
			payload[j] = (unsigned char)j;
		assert(btcvsd_copy(i, sram, payload, len, 1, read_io,
				   write_io));
		assert(btcvsd_copy(i, sram, restored, len, 0, read_io,
				   write_io));
		assert(!btcvsd_copy(i, sram, restored, len - 1, 0, read_io,
				    write_io));
		for (j = 0; j < btcvsd_layouts[i].blocks; j++) {
			for (k = n; k < stride; k++)
				assert(sram[j * stride + k] == 0xa5);
		}
		assert(!memcmp(restored, payload, len));
		for (j = 0; j < len / 30; j++) {
			unsigned int mask = btcvsd_layouts[i].valid[j];
			assert(btcvsd_valid(mask, i, j));
			for (k = 0; k < 18; k++)
				if (mask & (1u << k))
					assert(!btcvsd_valid(mask & ~(1u << k),
							     i, j));
		}
		assert(!btcvsd_valid(~0u, i, len / 30));
	}
	assert(!btcvsd_address(0, 6, 0x20000, &offset));
	assert(!btcvsd_address(0, 0, 0, &offset));
	memset(payload, 0, 60);
	payload[0] = 1;
	payload[1] = 0x38;
	payload[2] = 0xad;
	assert(btcvsd_msbc(payload));
	payload[2] = 0xae;
	assert(!btcvsd_msbc(payload));
	{
		struct btcvsd_txq q = { 0 };
		unsigned char input[180], out[180];
		unsigned int chunk, pass, produced, consumed, credits, expected,
			ends[256];
		for (chunk = 1; chunk <= 180; chunk++) {
			btcvsd_tx_reset(&q, 7);
			produced = consumed = credits = 0;
			for (pass = 0; pass < 256; pass++) {
				for (i = 0; i < chunk; i++)
					input[i] =
						(unsigned char)(produced + i);
				assert(btcvsd_tx_push(&q, 7, input, chunk));
				produced += chunk;
				ends[pass] = produced;
				while (q.used >= 60) {
					assert(btcvsd_tx_peek(&q, 7, out, 60));
					for (i = 0; i < 60; i++)
						assert(out[i] ==
						       (unsigned char)(consumed +
								       i));
					consumed += 60;
					expected = credits;
					while (expected <= pass &&
					       ends[expected] <= consumed)
						expected++;
					assert(btcvsd_tx_pop(&q, 7, 60) ==
					       (int)(expected - credits));
					credits = expected;
				}
			}
			assert(btcvsd_tx_peek(&q, 7, out, q.used));
			for (i = 0; i < q.used; i++)
				assert(out[i] == (unsigned char)(consumed + i));
			assert(btcvsd_tx_pop(&q, 7, q.used) ==
			       (int)(256 - credits));
			assert(q.packets == 0 && q.used == 0);
		}
		for (i = 0; i < 180; i++)
			input[i] = (unsigned char)i;
		btcvsd_tx_reset(&q, 8);
		assert(!btcvsd_tx_push(&q, 7, input, 60));
		for (i = 0; i < 6; i++)
			assert(btcvsd_tx_push(&q, 8, input, 180));
		assert(!btcvsd_tx_push(&q, 8, input, 1));
		assert(btcvsd_tx_pop(&q, 8, 180) == 1);
		assert(btcvsd_tx_push(&q, 8, input, 180));
		assert(btcvsd_tx_reset(&q, 9) == 6);
		assert(btcvsd_tx_pop(&q, 8, 60) == -1 && !q.used);
	}
	{
		struct btcvsd_txq tx = { 0 };
		struct btcvsd_rxq rx = { 0 };
		unsigned char frames[180], frame[60], junk[7] = { 0 },
						      stream[240];
		unsigned int dropped = 0, status;
		memset(frames, 0x5a, sizeof(frames));
		for (i = 0; i < 180; i += 60) {
			frames[i] = 1;
			frames[i + 1] = 0x38;
			frames[i + 2] = 0xad;
			frames[i + 59] = 0;
		}
		btcvsd_tx_reset(&tx, 1);
		assert(btcvsd_tx_push(&tx, 1, junk, 7));
		assert(btcvsd_tx_push(&tx, 1, frames, 13));
		assert(!btcvsd_tx_frame(&tx, 1, frame, &dropped));
		assert(btcvsd_tx_push(&tx, 1, frames + 13, 167));
		for (i = 0; i < 3; i++)
			assert(btcvsd_tx_frame(&tx, 1, frame, &dropped));
		assert(dropped == 7 && !tx.used && !tx.packets);
		/* A partial firmware batch is retained across IRQs and layout change. */
		{
			unsigned char batch[180];
			unsigned int staged = 0;
			assert(btcvsd_tx_push(&tx, 1, frames, 60));
			assert(!btcvsd_tx_batch(&tx, 1, batch, &staged, 180,
						&dropped));
			assert(staged == 60 && !tx.used);
			assert(!btcvsd_tx_batch(&tx, 1, batch, &staged, 180,
						&dropped));
			assert(staged == 60);
			assert(btcvsd_tx_push(&tx, 1, frames + 60, 120));
			assert(btcvsd_tx_batch(&tx, 1, batch, &staged, 180,
					       &dropped));
			assert(staged == 180 && !memcmp(batch, frames, 180));
			assert(!btcvsd_tx_batch(&tx, 2, batch, &staged, 180,
						&dropped));
			/* A smaller layout leaves the final frame for the next IRQ. */
			staged -= 120;
			memmove(batch, batch + 120, staged);
			assert(!btcvsd_tx_batch(&tx, 1, batch, &staged, 120,
						&dropped));
			assert(staged == 60);
			assert(btcvsd_tx_push(&tx, 1, frames, 60));
			assert(btcvsd_tx_batch(&tx, 1, batch, &staged, 120,
					       &dropped));
			assert(staged == 120);
		}
		btcvsd_rx_reset(&rx, 1);
		dropped = 0;
		/* Stale H2 in wholly invalid SRAM cannot establish cadence. */
		assert(btcvsd_rx_push(&rx, 1, frames, 1, 0));
		assert(!btcvsd_rx_frame(&rx, 1, frame, &status, &dropped));
		assert(!rx.synced && rx.used == 59 && dropped == 121);
		assert(frames[33] ==
		       0x5a); /* Raw evidence is never modified. */
		btcvsd_rx_reset(&rx, 1);
		dropped = 0;
		assert(btcvsd_rx_push(&rx, 1, frames, 1, 7));
		for (i = 0; i < 3; i++) {
			assert(btcvsd_rx_frame(&rx, 1, frame, &status,
					       &dropped));
			assert(status == 0);
			assert(!memcmp(frame, frames, 60));
		}
		assert(btcvsd_rx_push(&rx, 1, frames, 0, 1));
		assert(btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       status == 3);
		assert(!memcmp(frame, frames, 30));
		for (j = 30; j < 60; j++)
			assert(!frame[j]);
		assert(btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       status == 2);
		for (j = 0; j < 60; j++)
			assert(!frame[j]);
		assert(btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       status == 2);
		for (j = 0; j < 60; j++)
			assert(!frame[j]);
		/* Partial loss of H2 zeros only the missing first half. */
		assert(btcvsd_rx_push(&rx, 1, frames, 0, 2));
		assert(btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       status == 3);
		for (j = 0; j < 30; j++)
			assert(!frame[j]);
		assert(!memcmp(frame + 30, frames + 30, 30));
		for (i = 0; i < 2; i++) {
			assert(btcvsd_rx_frame(&rx, 1, frame, &status,
					       &dropped) &&
			       status == 2);
			for (j = 0; j < 60; j++)
				assert(!frame[j]);
		}
		/* Invalid frames retain cadence after synchronization. */
		memset(stream, 0x39, sizeof(stream));
		assert(btcvsd_rx_push(&rx, 1, stream, 3, 1));
		for (i = 0; i < 2; i++) {
			assert(btcvsd_rx_frame(&rx, 1, frame, &status,
					       &dropped) &&
			       status == 1);
			for (j = 0; j < 60; j++)
				assert(frame[j] == 0x39);
		}
		btcvsd_rx_reset(&rx, 1);
		/* A frame straddles two IRQ batches after seven stale bytes. */
		memset(stream, 0, sizeof(stream));
		for (i = 7; i < 187; i += 60)
			memcpy(stream + i, frames, 60);
		assert(btcvsd_rx_push(&rx, 1, stream, 3, 1));
		assert(btcvsd_rx_frame(&rx, 1, frame, &status, &dropped));
		assert(!btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       rx.used == 53);
		assert(btcvsd_rx_push(&rx, 1, stream + 120, 3, 1));
		for (i = 0; i < 2; i++)
			assert(btcvsd_rx_frame(&rx, 1, frame, &status,
					       &dropped) &&
			       status == 0);
		assert(!btcvsd_rx_frame(&rx, 1, frame, &status, &dropped) &&
		       rx.used == 53);
		assert(dropped == 7);
		btcvsd_rx_reset(&rx, 2);
		assert(!btcvsd_rx_push(&rx, 1, frames, 1, 7));
		assert(!btcvsd_rx_frame(&rx, 1, frame, &status, &dropped));
	}

	{
		unsigned char header[3] = { 0, 0x0e, 60 };
		assert(!btcvsd_sco_header(NULL, 0, 3584));
		assert(btcvsd_sco_header(header, 63, 3584) == 60);
		assert(!btcvsd_sco_header(header, 62, 3584));
		assert(!btcvsd_sco_header(header, 63, 3585));
		header[1] |= 0x80;
		assert(!btcvsd_sco_header(header, 63, 3584));
		for (i = 0; i < 4; i++)
			for (j = 0; j < 2; j++)
				for (k = 0; k < 4; k++) {
					assert(btcvsd_supported(i, j, k) ==
					       (i == 3 && j == 0 && k == 2));
					assert(btcvsd_cvsd_supported(i, j, k) ==
					       (i == 0 && j == 0 && k == 1));
				}
		assert(btcvsd_control(0x84640000));
		assert(!btcvsd_control(0x04640000));
		assert(!btcvsd_control(0xdeadfeed));
		assert(!btcvsd_control((1u << 31) | (6u << 18)));
	}

	puts("BTCVSD shared layout/padding/validity/bounds/H2/fragment/queue/generation checks passed");
}
