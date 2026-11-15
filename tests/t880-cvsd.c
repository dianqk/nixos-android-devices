/* SPDX-License-Identifier: BSD-3-Clause */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "btcvsd-cvsd.h"
extern const int16_t direct_FIR_8kHz_on_64kHz_Fx[64];
extern const int16_t polyphase_FIR_8kHz_on_64kHz_Fx[64];

static unsigned char *load(const char *directory, const char *name,
			   size_t *length)
{
	char path[1024];
	FILE *f;
	unsigned char *data;
	assert(snprintf(path, sizeof(path), "%s/%s", directory, name) <
	       (int)sizeof(path));
	f = fopen(path, "rb");
	assert(f);
	assert(!fseek(f, 0, SEEK_END));
	*length = ftell(f);
	rewind(f);
	data = malloc(*length + 1);
	assert(data);
	assert(fread(data + 1, 1, *length, f) == *length);
	assert(!fclose(f));
	return data;
}
static void vectors(const char *directory, unsigned int chunk,
		    unsigned int packing)
{
	size_t n, r, pos, k, i;
	unsigned char *input, *reference, *output, *wire;
	struct btcvsd_cvsd_tx tx;
	struct btcvsd_cvsd_rx rx;
	input = load(directory, "input-pcm.raw", &n);
	reference = load(directory, "reference-cvsd.cod", &r);
	assert(n == 2 * r);
	output = malloc(r + 2);
	assert(output);
	output[0] = 0xa7;
	output[r + 1] = 0xc3;
	btcvsd_cvsd_tx_reset(&tx);
	for (pos = 0; pos < r; pos += k) {
		k = chunk ? chunk : 1 + (pos * 17) % 181;
		if (k > r - pos)
			k = r - pos;
		assert(btcvsd_cvsd_encode(&tx, input + 1 + 2 * pos, 2 * k,
					  output + 1 + pos, k, packing) == k);
	}
	assert(output[0] == 0xa7 && output[r + 1] == 0xc3);
	for (i = 0; i < r; i++)
		assert(output[i + 1] ==
		       (packing ? btcvsd_cvsd_reverse(reference[i + 1]) :
				  reference[i + 1]));
	free(input);
	free(reference);
	free(output);
	input = load(directory, "input-cvsd.cod", &n);
	reference = load(directory, "reference-pcm.raw", &r);
	assert(r == 2 * n);
	wire = malloc(n + 1);
	assert(wire);
	for (i = 0; i < n; i++)
		wire[i + 1] = packing ? btcvsd_cvsd_reverse(input[i + 1]) :
					input[i + 1];
	output = malloc(r + 2);
	assert(output);
	output[0] = 0xa7;
	output[r + 1] = 0xc3;
	btcvsd_cvsd_rx_reset(&rx);
	for (pos = 0; pos < n; pos += k) {
		k = chunk ? chunk : 1 + (pos * 13) % 181;
		if (k > n - pos)
			k = n - pos;
		assert(btcvsd_cvsd_decode(&rx, wire + 1 + pos, k, NULL,
					  output + 1 + 2 * pos, 2 * k, NULL,
					  packing) == 2 * k);
	}
	assert(output[0] == 0xa7 && output[r + 1] == 0xc3);
	assert(!memcmp(output + 1, reference + 1, r));
	free(input);
	free(reference);
	free(output);
	free(wire);
}
static void bounds(void)
{
	struct btcvsd_cvsd_tx tx, saved_tx;
	struct btcvsd_cvsd_rx rx, saved_rx;
	unsigned char *in = malloc(3), *out = malloc(2), *pcm = malloc(3);
	unsigned int i;
	btc_s64 sum = 0;
	assert(in && out && pcm);
	in[1] = 0xff;
	in[2] = 0x7f;
	btcvsd_cvsd_tx_reset(&tx);
	saved_tx = tx;
	assert(!btcvsd_cvsd_encode(&tx, NULL, 1, NULL, 0, 0));
	assert(!btcvsd_cvsd_encode(&tx, NULL, 2, NULL, 0, 0));
	assert(!btcvsd_cvsd_encode(&tx, NULL, 2, NULL, 1, 2));
	assert(!memcmp(&tx, &saved_tx, sizeof(tx)));
	/* Exact one-byte destination, unaligned on both sides. ASan catches tails. */
	assert(btcvsd_cvsd_encode(&tx, in + 1, 2, out + 1, 1, 0) == 1);
	btcvsd_cvsd_rx_reset(&rx);
	saved_rx = rx;
	assert(!btcvsd_cvsd_decode(&rx, NULL, 1, NULL, NULL, 1, NULL, 0));
	assert(!btcvsd_cvsd_decode(&rx, NULL, 1, NULL, NULL, 2, NULL, 2));
	assert(!memcmp(&rx, &saved_rx, sizeof(rx)));
	assert(btcvsd_cvsd_decode(&rx, out + 1, 1, NULL, pcm + 1, 2, NULL, 0) ==
	       2);
	free(in);
	free(out);
	free(pcm);
	for (i = 0; i < 64; i++) {
		assert(btcvsd_cvsd_direct[i] == direct_FIR_8kHz_on_64kHz_Fx[i]);
		assert(btcvsd_cvsd_polyphase[i] ==
		       polyphase_FIR_8kHz_on_64kHz_Fx[i]);
		sum += (btc_s64)abs(btcvsd_cvsd_direct[i]) * 32768;
	}
	assert(sum >
	       INT32_MAX); /* A signed32 FIR accumulator is insufficient. */
	for (i = 0; i < 256; i++)
		assert(btcvsd_cvsd_reverse(btcvsd_cvsd_reverse(i)) == i);
	assert(btcvsd_cvsd_reverse(1) == 0x80 &&
	       btcvsd_cvsd_reverse(0x96) == 0x69);
	assert(btcvsd_cvsd_shift(-1, 10) == -1 &&
	       btcvsd_cvsd_shift(-32769, 10) == -33);
	assert(btcvsd_cvsd_sample(INT64_C(1000000000)) == 32767);
	assert(btcvsd_cvsd_sample(-INT64_C(1000000000)) == -32768);
	/* Saturation is exercised through the actual decimation path. */
	for (unsigned int negative = 0; negative < 2; negative++) {
		unsigned char byte = 0, raw[2];
		btcvsd_cvsd_rx_reset(&rx);
		for (i = 0; i < 64; i++)
			rx.history[i] = (btcvsd_cvsd_direct[i] < 0) ^ negative ?
						-32768 :
						32767;
		assert(btcvsd_cvsd_decode(&rx, &byte, 1, NULL, raw, 2, NULL,
					  0) == 2);
		assert((int16_t)(raw[0] | raw[1] << 8) ==
		       (negative ? -32768 : 32767));
	}

	/* Full-scale alternating, block and impulse inputs exercise clipping and
	 * every predictor update without signed overflow. */
	for (unsigned int mode = 0; mode < 3; mode++) {
		btcvsd_cvsd_tx_reset(&tx);
		btcvsd_cvsd_rx_reset(&rx);
		for (i = 0; i < 2048; i++) {
			int16_t value =
				mode == 0 ? (i & 1 ? 32767 : -32768) :
				mode == 1 ? (i % 64 < 32 ? 32767 : -32768) :
					    (i % 31 ? 0 : 32767);
			unsigned char input[2] = { (uint16_t)value,
						   (uint16_t)value >> 8 };
			unsigned char encoded, output[2];
			assert(btcvsd_cvsd_encode(&tx, input, 2, &encoded, 1,
						  0) == 1);
			assert(btcvsd_cvsd_decode(&rx, &encoded, 1, NULL,
						  output, 2, NULL, 0) == 2);
			assert(tx.core.accumulator <= 32767 * 1024 &&
			       tx.core.accumulator >= -32767 * 1024);
			assert(rx.core.accumulator <= 32767 * 1024 &&
			       rx.core.accumulator >= -32767 * 1024);
			assert(tx.core.step >= 10 * 1024 &&
			       tx.core.step <= 1280 * 1024);
			assert(rx.core.step >= 10 * 1024 &&
			       rx.core.step <= 1280 * 1024);
		}
	}
	assert(!btcvsd_cvsd_status(NULL, 0));
}
static void loss(void)
{
	enum { N = 4000 };
	unsigned char input[2 * N], encoded[N], clean[2 * N], damaged[2 * N],
		valid[N], status[N];
	struct btcvsd_cvsd_tx tx;
	struct btcvsd_cvsd_rx a, b;
	unsigned int i;
	int max_after8 = 0;
	for (i = 0; i < N; i++) {
		int16_t sample = i < 1015 ? 30000 : -30000;
		input[2 * i] = (uint16_t)sample;
		input[2 * i + 1] = (uint16_t)sample >> 8;
		valid[i] = i != 1000;
	}
	btcvsd_cvsd_tx_reset(&tx);
	btcvsd_cvsd_rx_reset(&a);
	btcvsd_cvsd_rx_reset(&b);
	assert(btcvsd_cvsd_encode(&tx, input, sizeof(input), encoded,
				  sizeof(encoded), 0) == N);
	assert(btcvsd_cvsd_decode(&a, encoded, N, NULL, clean, sizeof(clean),
				  NULL, 0) == 2 * N);
	assert(btcvsd_cvsd_decode(&b, encoded, N, valid, damaged,
				  sizeof(damaged), status, 0) == 2 * N);
	assert(!memcmp(clean, damaged, 2000));
	assert(!damaged[2000] && !damaged[2001] && status[1000] == 2);
	for (i = 0; i < 1000; i++)
		assert(!status[i]);
	for (i = 1001; i < N; i++) {
		assert(status[i] ==
		       1); /* Uncertainty persists beyond the FIR flush. */
		if (i >= 1009) {
			int e = abs((int16_t)(clean[2 * i] | clean[2 * i + 1]
								     << 8) -
				    (int16_t)(damaged[2 * i] |
					      damaged[2 * i + 1] << 8));
			if (e > max_after8)
				max_after8 = e;
		}
	}
	assert(max_after8 > 1000);
	assert(btcvsd_cvsd_status(status, 60) == 0);
	assert(btcvsd_cvsd_status(status + 960, 60) == 3);
	assert(btcvsd_cvsd_status(status + 1020, 60) == 1);
	btcvsd_cvsd_rx_reset(&b);
	assert(!b.uncertain);
	assert(btcvsd_cvsd_decode(&b, encoded, 60, NULL, damaged, 120, status,
				  0) == 120);
	for (i = 0; i < 60; i++)
		assert(!status[i]);
	/* Entire lost duration is zero, with state independent of stale bytes. */
	memset(valid, 0, 60);
	memset(encoded, 0x55, 60);
	assert(btcvsd_cvsd_decode(&a, encoded, 60, valid, clean, 120, status,
				  0) == 120);
	memset(encoded, 0xff, 60);
	assert(btcvsd_cvsd_decode(&b, encoded, 60, valid, damaged, 120, status,
				  0) == 120);
	for (i = 0; i < 120; i++)
		assert(!clean[i] && !damaged[i]);
	assert(btcvsd_cvsd_status(status, 60) == 2);
	/* After an all-lost flush both histories are zero; no stale payload used. */
	for (i = 0; i < 64; i++)
		assert(!a.history[i] && !b.history[i]);
}
static void fifo(void)
{
	struct btcvsd_cvsd_fifo q;
	unsigned char input[2160], output[2160];
	unsigned int i, iteration, produced, consumed, n;
	for (i = 0; i < 1024; i++) {
		assert(btcvsd_cvsd_pcm_supported(i, 120) == (i == 0x60));
		assert(btcvsd_cvsd_pcm_supported(i, 184) == (i == 0x60));
		assert(!btcvsd_cvsd_pcm_supported(i, 119));
	}
	for (unsigned int capacity = 1080; capacity <= 2160; capacity += 1080) {
		btcvsd_cvsd_fifo_reset(&q, 3, capacity);
		produced = consumed = 0;
		for (iteration = 0; iteration < 10000; iteration++) {
			n = 1 + iteration * 37 % 184;
			if (n <= capacity - q.used) {
				for (i = 0; i < n; i++)
					input[i] = (produced + i) * 71 + 13;
				assert(btcvsd_cvsd_fifo_push(&q, 3, input, n));
				produced += n;
			}
			n = 1 + iteration * 53 % 180;
			if (n <= q.used) {
				assert(btcvsd_cvsd_fifo_pop(&q, 3, output, n));
				for (i = 0; i < n; i++)
					assert(output[i] == (unsigned char)((consumed + i) * 71 + 13));
				consumed += n;
			}
			assert(q.used == produced - consumed);
		}
		n = q.used;
		assert(!btcvsd_cvsd_fifo_push(&q, 3, NULL, capacity + 1));
		assert(!btcvsd_cvsd_fifo_pop(&q, 3, NULL, capacity + 1));
		assert(q.used == n);
		btcvsd_cvsd_fifo_reset(&q, 4, capacity);
		assert(!btcvsd_cvsd_fifo_push(&q, 3, input, 1));
		assert(!btcvsd_cvsd_fifo_pop(&q, 3, output, 1));
		assert(!q.used);
		memset(input, 0x5a, capacity);
		assert(btcvsd_cvsd_fifo_push(&q, 4, input, capacity));
		assert(!btcvsd_cvsd_fifo_push(&q, 4, input, 1));
		assert(btcvsd_cvsd_fifo_pop(&q, 4, output, capacity));
		assert(!memcmp(input, output, capacity) && !q.used);
	}
	btcvsd_cvsd_fifo_reset(&q, 5, BTCVSD_CVSD_FIFO_BYTES + 1);
	assert(!btcvsd_cvsd_fifo_push(&q, 5, NULL, 0));
	assert(!btcvsd_cvsd_fifo_pop(&q, 5, NULL, 0));
}
static void packetization(void)
{
	struct btcvsd_cvsd_packet p = { 0 };
	unsigned int total = 0, packets = 0;
	/* Alternate firmware layouts, carrying partial packets across batches. */
	for (unsigned int batch = 0; batch < 100; batch++) {
		unsigned int count = batch % 3 ? 180 : 120;
		for (unsigned int i = 0; i < count; i++, total++) {
			unsigned char sample[2] = { total, total >> 8 };
			unsigned char status = total % 3;
			int ready = btcvsd_cvsd_packet_push(&p, sample, status);
			assert(ready == ((total + 1) % 24 == 0));
			if (!ready)
				continue;
			packets++;
			for (unsigned int j = 0; j < 24; j++) {
				unsigned int expected = total - 23 + j;
				assert(p.pcm[j * 2] == (expected & 255));
				assert(p.pcm[j * 2 + 1] == (expected >> 8));
				assert(p.status[j] == expected % 3);
			}
			assert(btcvsd_cvsd_status(p.status, 24) == 3);
		}
	}
	assert(packets * 24 + p.used == total);
	/* A generation change discards the old partial, preserving silent losses. */
	btcvsd_cvsd_packet_reset(&p);
	for (unsigned int i = 0; i < 12; i++) {
		const unsigned char old[2] = { 0xaa, 0x55 };
		assert(!btcvsd_cvsd_packet_push(&p, old, 1));
	}
	btcvsd_cvsd_packet_reset(&p);
	for (unsigned int state = 0; state < 3; state++) {
		for (unsigned int i = 0; i < 24; i++) {
			const unsigned char zero[2] = { 0, 0 };
			assert(btcvsd_cvsd_packet_push(&p, zero, state) == (i == 23));
		}
		for (unsigned int i = 0; i < 48; i++)
			assert(p.pcm[i] == 0);
		assert(btcvsd_cvsd_status(p.status, 24) == state);
	}
}
int main(int argc, char **argv)
{
	unsigned int sizes[] = { 1, 7, 24, 30, 60, 2056, 4096, 0 };
	assert(argc == 2);
	for (unsigned int packing = 0; packing < 2; packing++)
		for (unsigned int i = 0; i < sizeof(sizes) / sizeof(sizes[0]);
		     i++)
			vectors(argv[1], sizes[i], packing);
	bounds();
	loss();
	fifo();
	packetization();
	puts("CVSD reference/chunk/packing/tail/alignment/bounds/saturation/loss/reset checks passed");
	return 0;
}
