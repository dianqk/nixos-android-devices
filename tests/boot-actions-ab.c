/* SPDX-License-Identifier: GPL-2.0-or-later */
/* In-memory UFS fixtures: no block devices or hardware are accessed. */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../pkgs/mobile-boot-action/qcom-ab.h"
#define BLOCKS 128
static unsigned char media[AB_MAX_LUNS][BLOCKS * AB_BLOCK], original[AB_MAX_LUNS][BLOCKS * AB_BLOCK];
static int writes, reads, fail_write, fail_read, mismatch_read;
static unsigned int cases;
static unsigned int crc(const void *data, unsigned int size)
{
	const unsigned char *p = data;
	unsigned int v = ~0U, i;
	while (size--) {
		v ^= *p++;
		for (i = 0; i < 8; i++)
			v = (v >> 1) ^ ((v & 1) ? 0xedb88320U : 0);
	}
	return ~v;
}
static int read_blocks(void *ctx, unsigned long long lba, unsigned int n, void *p)
{
	assert(lba + n <= BLOCKS);
	reads++;
	if (reads == fail_read)
		return -EIO;
	memcpy(p, (unsigned char *)ctx + AB_BLOCK * lba, AB_BLOCK * n);
	if (reads == mismatch_read)
		((unsigned char *)p)[0] ^= 1;
	return 0;
}
static int write_blocks(void *ctx, unsigned long long lba, unsigned int n, const void *p)
{
	assert(n == 1 && lba + n <= BLOCKS && lba != 0);
	writes++;
	/* Include an error returned after a partially/completely performed write. */
	memcpy((unsigned char *)ctx + AB_BLOCK * lba, p, AB_BLOCK * n);
	return writes == fail_write ? -EIO : 0;
}
static void *allocate(unsigned int n) { return malloc(n); }
static const struct ab_ops ops = {read_blocks, write_blocks, crc, allocate, free};
static void entry(unsigned int disk, unsigned int index, const char *name, unsigned int guid)
{
	unsigned char *e = media[disk] + 2 * AB_BLOCK + index * 128;
	unsigned int i, n = strlen(name);
	memset(e, 0, 128);
	e[0] = guid;
	e[16] = disk * 32 + index + 1;
	ab_put(e + 32, 10 + index * 2, 8);
	ab_put(e + 40, 11 + index * 2, 8);
	if (name[n - 1] == 'a')
		ab_put(e + 48, (2ULL << 48) | AB_SUCCESS, 8);
	else if (name[n - 1] == 'b')
		ab_put(e + 48, AB_ACTIVE | AB_PRIORITY | AB_SUCCESS, 8);
	for (i = 0; i < n; i++)
		e[56 + i * 2] = name[i];
}
static void headers(unsigned int disk)
{
	unsigned int side;
	for (side = 0; side < 2; side++) {
		unsigned char *h = media[disk] + (side ? BLOCKS - 1 : 1) * AB_BLOCK;
		unsigned char *e = media[disk] + (side ? BLOCKS - 2 : 2) * AB_BLOCK;
		memset(h, 0, 92);
		memcpy(h, "EFI PART", 8);
		ab_put(h + 8, 0x10000, 4);
		ab_put(h + 12, 92, 4);
		ab_put(h + 24, side ? BLOCKS - 1 : 1, 8);
		ab_put(h + 32, side ? 1 : BLOCKS - 1, 8);
		ab_put(h + 40, 3, 8);
		ab_put(h + 48, BLOCKS - 3, 8);
		h[56] = disk + 1;
		ab_put(h + 72, side ? BLOCKS - 2 : 2, 8);
		ab_put(h + 80, 12, 4);
		ab_put(h + 84, 128, 4);
		ab_put(h + 88, crc(e, 12 * 128), 4);
		ab_put(h + 16, crc(h, 92), 4);
	}
}
static void fixture(void)
{
	unsigned int d;
	memset(media, 0xa5, sizeof(media));
	for (d = 0; d < 2; d++)
		memset(media[d] + 2 * AB_BLOCK, 0, 12 * 128);
	entry(0, 0, "boot_a", 10);
	entry(0, 1, "boot_b", 11);
	entry(0, 2, "recovery_a", 12);
	entry(0, 3, "recovery_b", 13);
	entry(0, 4, "misc", 14);
	entry(0, 5, "linux-boot", 15);
	entry(1, 0, "abl_a", 20);
	entry(1, 1, "abl_b", 21);
	entry(0, 6, "xbl_a", 22);
	ab_put(media[0] + 2 * AB_BLOCK + 6 * 128 + 32, 34, 8);
	ab_put(media[0] + 2 * AB_BLOCK + 6 * 128 + 40, 35, 8);
	/* Make misc large enough for the 32 KiB snapshot record; move the ESP. */
	ab_put(media[0] + 2 * AB_BLOCK + 4 * 128 + 40, 26, 8);
	ab_put(media[0] + 2 * AB_BLOCK + 5 * 128 + 32, 30, 8);
	ab_put(media[0] + 2 * AB_BLOCK + 5 * 128 + 40, 31, 8);
	entry(1, 3, "xbl_b", 22);
	for (d = 0; d < 2; d++) {
		memcpy(media[d] + (BLOCKS - 2) * AB_BLOCK, media[d] + 2 * AB_BLOCK, 12 * 128);
		headers(d);
	}
	media[0][18 * AB_BLOCK] = 0; /* misc command */
	memset(media[0] + 26 * AB_BLOCK, 0, 64);
	media[0][26 * AB_BLOCK] = 2;
	ab_put(media[0] + 26 * AB_BLOCK + 1, 0x56740ab0, 4);
	writes = reads = fail_write = fail_read = mismatch_read = 0;
	memcpy(original, media, sizeof(media));
}
static int open_state(struct ab_state *s)
{
	unsigned int i;
	memset(s, 0, sizeof(*s));
	s->ops = &ops;
	s->scratch = allocate(AB_BLOCK);
	for (i = 0; i < 2; i++) {
		s->disk[i].blocks = BLOCKS;
		s->disk[i].context = media[i];
		s->disks++;
		int ret = ab_load(s, &s->disk[i]);
		if (ret)
			return ret;
	}
	return 0;
}
int main(void)
{
	struct ab_state s;
	unsigned int i, normal_writes, normal_reads;
	fixture();
	assert(!open_state(&s));
	assert(!ab_validate(&s, 2, 1) && !ab_validate(&s, 2, 0));
	assert(ab_validate(&s, 1, 1));
	ab_plan_android(&s);
	reads = 0;
	assert(!ab_store(&s, 0));
	normal_writes = writes;
	normal_reads = reads;
	/* Whole-disk diff: only pair type GUIDs, selected attributes and CRCs.
	 * All payloads, PMBR, unique GUIDs, geometry, padding and XBL survive. */
	for (i = 0; i < 2; i++) {
		unsigned int side, j;
		assert(!memcmp(media[i], original[i], AB_BLOCK));
		assert(!memcmp(media[i] + 3 * AB_BLOCK, original[i] + 3 * AB_BLOCK, (BLOCKS - 5) * AB_BLOCK));
		for (side = 0; side < 2; side++) {
			unsigned int h = (side ? BLOCKS - 1 : 1) * AB_BLOCK;
			unsigned int a = (side ? BLOCKS - 2 : 2) * AB_BLOCK;
			assert(!memcmp(media[i] + h + 92, original[i] + h + 92, AB_BLOCK - 92));
			assert(!memcmp(media[i] + a + 12 * 128, original[i] + a + 12 * 128, AB_BLOCK - 12 * 128));
			for (j = 0; j < 12; j++) {
				assert(!memcmp(media[i] + a + 128 * j + 16, original[i] + a + 128 * j + 16, 32));
				assert(!memcmp(media[i] + a + 128 * j + 56, original[i] + a + 128 * j + 56, 72));
			}
		}
	}
	assert(!memcmp(media[1] + 2 * AB_BLOCK + 2 * 128, original[1] + 2 * AB_BLOCK + 2 * 128, 2 * 128));
	assert((ab_get(s.disk[0].new_entries[0] + 48, 8) & (AB_ACTIVE | AB_PRIORITY | AB_RETRY | AB_SUCCESS | AB_UNBOOTABLE)) == (AB_ACTIVE | AB_PRIORITY | AB_RETRY));
	assert(!ab_store(&s, 1) && !memcmp(media, original, sizeof(media)));
	ab_free(&s);
	cases++;
	/* Inject every read/write failure in a multi-LUN transaction; restore
	 * also covers the write that returned an error after changing media. */
	for (i = 1; i <= normal_writes; i++) {
		fixture(); assert(!open_state(&s)); ab_plan_android(&s);
		fail_write = i;
		assert(ab_store(&s, 0));
		fail_write = 0;
		assert(!ab_store(&s, 1) && !memcmp(media, original, sizeof(media)));
		ab_free(&s); cases++;
	}
	for (i = 1; i <= normal_reads; i++) {
		fixture(); assert(!open_state(&s)); ab_plan_android(&s); reads = 0; fail_read = i;
		assert(ab_store(&s, 0)); fail_read = 0;
		assert(!ab_store(&s, 1) && !memcmp(media, original, sizeof(media)));
		ab_free(&s); cases++;
	}
	for (i = 1; i <= normal_reads; i++) {
		fixture(); assert(!open_state(&s)); ab_plan_android(&s); reads = 0; mismatch_read = i;
		assert(ab_store(&s, 0)); mismatch_read = 0;
		assert(!ab_store(&s, 1) && !memcmp(media, original, sizeof(media)));
		ab_free(&s); cases++;
	}
	fixture(); assert(!open_state(&s)); ab_plan_android(&s); assert(!ab_store(&s, 0));
	fail_write = writes + 1; assert(ab_store(&s, 1)); ab_free(&s); cases++;
	/* Refuse unknown/corrupt metadata, BCB, missing pairs and wrong slots. */
	for (i = 0; i < 11; i++) {
		fixture();
		if (i == 0) media[0][AB_BLOCK + 16] ^= 1;
		if (i == 1) media[1][(BLOCKS - 1) * AB_BLOCK + 16] ^= 1;
		if (i == 2) media[0][(BLOCKS - 2) * AB_BLOCK] ^= 1;
		if (i == 3) media[0][18 * AB_BLOCK] = 'b';
		if (i == 4) memset(media[0] + 2 * AB_BLOCK + 3 * 128, 0, 128);
		if (i == 5) memset(media[1] + 2 * AB_BLOCK, 0, 128);
		if (i == 6) ab_put(media[0] + 2 * AB_BLOCK + 128 + 48, AB_ACTIVE | AB_PRIORITY | AB_UNBOOTABLE, 8);
		if (i == 7) ab_put(media[0] + 2 * AB_BLOCK + 48, AB_ACTIVE | AB_PRIORITY | AB_SUCCESS, 8);
		if (i == 8) ab_put(media[0] + 2 * AB_BLOCK + 32, 1, 8);
		if (i == 9) ab_put(media[0] + 2 * AB_BLOCK + 128 + 32, 10, 8);
		if (i == 10) media[1][2 * AB_BLOCK + 3 * 128] = 23;
		if (i >= 4) {
			for (unsigned int d = 0; d < 2; d++) {
				memcpy(media[d] + (BLOCKS - 2) * AB_BLOCK, media[d] + 2 * AB_BLOCK, 12 * 128);
				headers(d);
			}
		}
		int ret = open_state(&s);
		if (!ret) ret = ab_validate(&s, 2, i == 4);
		assert(ret && !writes); ab_free(&s); cases++;
	}
	printf("PASS %u Qualcomm GPT validation, exact diff and fault/restore cases\n", cases);
	return 0;
}
