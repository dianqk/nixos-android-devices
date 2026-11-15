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
static int writes, reads, fail_write, fail_read, mismatch_read, tolerate;
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
	writes = reads = fail_write = fail_read = mismatch_read = tolerate = 0;
	memcpy(original, media, sizeof(media));
}
/* Recompute one copy's entries CRC and header CRC. */
static void reseal(unsigned int disk, unsigned int side)
{
	unsigned char *h = media[disk] + (side ? BLOCKS - 1 : 1) * AB_BLOCK;
	ab_put(h + 88, crc(media[disk] + (side ? BLOCKS - 2 : 2) * AB_BLOCK, 12 * 128), 4);
	memset(h + 16, 0, 4);
	ab_put(h + 16, crc(h, 92), 4);
}
static unsigned char *slot_entry(unsigned int disk, unsigned int side, unsigned int index)
{
	return media[disk] + (side ? BLOCKS - 2 : 2) * AB_BLOCK + index * 128;
}
/* Xiaomi Marble ABL: only the primary GPT is rewritten on each
 * boot. Retry decrements (backup boot_b 0x3f, primary 0x37) and set_active's
 * placeholder type swap leave the backup array stale; with stale_crc the
 * backup header's entries CRC no longer matches the backup array either.
 * Applied to LUN 0 (boot_b) and, with both, also to LUN 1 (abl/xbl). */
static void marble_stale(int stale_crc, int both)
{
	static const unsigned char placeholder[16] = {
		0xd4, 0x6c, 0x03, 0x77, 0xd5, 0x03, 0xbb, 0x42,
		0x8e, 0xd1, 0x37, 0xe5, 0xa8, 0x8b, 0xaa, 0x34
	};
	for (unsigned int d = 0; d < (both ? 2U : 1U); d++)
		for (unsigned int side = 0; side < 2; side++) {
			unsigned char *e = slot_entry(d, side, 0), *f = slot_entry(d, side, 1);
			unsigned long long a = ab_get(e + 48, 8), b = ab_get(f + 48, 8);
			if (d == 0) {
				/* boot_a: inactive, placeholder type, bit 60 set by ABL. */
				ab_put(e + 48, (a & ~AB_SLOT_ATTRIBUTES) | (side ? 0 : 1ULL << 60), 8);
				if (!side) memcpy(e, placeholder, 16);
				ab_put(f + 48, (b & ~AB_SLOT_ATTRIBUTES) | AB_ACTIVE | AB_PRIORITY |
				       ((side ? 7ULL : 6ULL) << 51), 8);
				if (side) f[0] = 99; /* pre-swap boot_b type */
			} else if (!side) {
				memcpy(e, placeholder, 16); /* abl_a */
			}
		}
	for (unsigned int d = 0; d < 2; d++) {
		reseal(d, 0);
		if (!stale_crc || d >= (both ? 2U : 1U)) reseal(d, 1);
	}
	memcpy(original, media, sizeof(media));
}
/* Both copies valid, identical and equal to the given primary snapshot. */
static void assert_synced(const unsigned char *primary, unsigned int disk)
{
	unsigned char *m = media[disk];
	assert(!memcmp(m + 2 * AB_BLOCK, primary, 12 * 128));
	assert(!memcmp(m + (BLOCKS - 2) * AB_BLOCK, primary, 12 * 128));
	for (unsigned int side = 0; side < 2; side++) {
		unsigned char *h = m + (side ? BLOCKS - 1 : 1) * AB_BLOCK, copy[92];
		memcpy(copy, h, 92); memset(copy + 16, 0, 4);
		assert(ab_get(h + 88, 4) == crc(primary, 12 * 128) && ab_get(h + 16, 4) == crc(copy, 92));
	}
}
static int open_state(struct ab_state *s)
{
	unsigned int i;
	memset(s, 0, sizeof(*s));
	s->ops = &ops;
	s->scratch = allocate(AB_BLOCK);
	s->tolerate_stale_backup = tolerate;
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
/* OEM end-of-LUN sentinels repeat across disks; calibration names can
 * end in _a/_b without carrying slot-selection attributes. */
static void unrelated_oem_metadata(unsigned int kinds)
{
	if (kinds & 1) {
		entry(0, 7, "last_parti", 90);
		ab_put(slot_entry(0, 0, 7) + 48, 1ULL << 60, 8);
		ab_put(media[0] + 2 * AB_BLOCK + 7 * 128 + 32, 40, 8);
		ab_put(media[0] + 2 * AB_BLOCK + 7 * 128 + 40, 41, 8);
		entry(1, 4, "last_parti", 91);
		ab_put(slot_entry(1, 0, 4) + 48, 1ULL << 60, 8);
	}
	if (kinds & 2) {
		entry(1, 8, "oplusstanvbk_a", 92);
		entry(1, 9, "oplusstanvbk_b", 93);
		ab_put(media[1] + 2 * AB_BLOCK + 8 * 128 + 48, 0, 8);
		ab_put(media[1] + 2 * AB_BLOCK + 9 * 128 + 48, 0, 8);
	}
	for (unsigned int d = 0; d < 2; d++) {
		memcpy(media[d] + (BLOCKS - 2) * AB_BLOCK, media[d] + 2 * AB_BLOCK, 12 * 128);
		headers(d);
	}
	memcpy(original, media, sizeof(media));
}
static void confirmation_scope_tests(void)
{
	struct ab_state s;
	for (unsigned int kinds = 1; kinds <= 3; kinds++) {
		fixture(); unrelated_oem_metadata(kinds);
		assert(!open_state(&s) && !ab_validate(&s, 2, AB_CONFIRM));
		assert(ab_validate(&s, 2, AB_ANDROID) && ab_validate(&s, 2, AB_RECOVERY));
		ab_free(&s); assert(!writes); cases++;
	}
	for (unsigned int fault = 0; fault < 7; fault++) {
		unsigned int lun = 2;
		fixture();
		unsigned char *a = media[0] + 2 * AB_BLOCK, *b = a + 128;
		switch (fault) {
		case 0: entry(1, 4, "boot_b", 94); break;
		case 1: ab_put(b + 48, AB_PRIORITY, 8); break;
		case 2: ab_put(a + 48, AB_ACTIVE | AB_PRIORITY | AB_SUCCESS, 8); break;
		case 3: ab_put(b + 48, AB_ACTIVE | AB_SUCCESS, 8); break;
		case 4: ab_put(b + 48, AB_ACTIVE | AB_PRIORITY | AB_UNBOOTABLE, 8); break;
		case 5: lun = 1; break;
		case 6: memcpy(b, media[1] + 2 * AB_BLOCK + 128, 16); break;
		}
		unrelated_oem_metadata(0);
		assert(!open_state(&s) && ab_validate(&s, lun, AB_CONFIRM));
		ab_free(&s); assert(!writes); cases++;
	}
}
static const char oem_non_slot_names[] = "last_parti oplusstanvbk_a oplusstanvbk_b";
static void non_slot_policy_tests(void)
{
	struct ab_state s;
	fixture(); unrelated_oem_metadata(3);
	assert(!open_state(&s)); s.non_slot_names = oem_non_slot_names;
	assert(!ab_validate(&s, 2, AB_ANDROID));
	ab_plan_android(&s);
	/* Whole calibration/sentinel entries survive, including type GUIDs. */
	for (unsigned int d = 0; d < s.disks; d++)
		for (unsigned int j = 0; j < s.disk[d].count; j++) {
			unsigned char *e = s.disk[d].entries[0] + j * 128;
			char name[36];
			if (!ab_zero(e, 16) && !ab_name(e, name) && ab_non_slot(&s, e, name) == 1)
				for (unsigned int side = 0; side < 2; side++)
					assert(!memcmp(e, s.disk[d].new_entries[side] + j * 128, 128));
		}
	assert(!ab_store(&s, 0) && !ab_store(&s, 1));
	assert(!memcmp(media, original, sizeof(media))); ab_free(&s); cases++;
	for (unsigned int fault = 0; fault < 13; fault++) {
		fixture(); unrelated_oem_metadata(3);
		if (fault < 8)
			ab_put(slot_entry(1, 0, 8) + 48, 1ULL << (48 + fault), 8);
		if (fault == 8) entry(1, 10, "boot_a", 94); /* ambiguous mandatory target */
		if (fault == 9) entry(1, 10, "extra_a", 94); /* unknown orphan */
		if (fault == 10) {
			entry(1, 10, "last_parti", 94);
			ab_put(slot_entry(1, 0, 10) + 48, AB_ACTIVE, 8);
		}
		if (fault == 11) entry(1, 10, "abl_b", 94); /* ambiguous early firmware */
		if (fault == 12) entry(1, 10, "oplusstanvbk_c", 94); /* unknown duplicate */
		if (fault == 12) {
			entry(0, 8, "oplusstanvbk_c", 95);
			ab_put(slot_entry(0, 0, 8) + 32, 44, 8);
			ab_put(slot_entry(0, 0, 8) + 40, 45, 8);
		}
		for (unsigned int d = 0; d < 2; d++) {
			memcpy(slot_entry(d, 1, 0), slot_entry(d, 0, 0), 12 * 128);
			headers(d);
		}
		memcpy(original, media, sizeof(media));
		assert(!open_state(&s)); s.non_slot_names = oem_non_slot_names;
		assert(ab_validate(&s, 2, AB_ANDROID));
		assert(!writes && !memcmp(media, original, sizeof(media))); ab_free(&s); cases++;
	}
	/* A real pair cannot have only one member excluded, even with zero flags. */
	fixture(); unrelated_oem_metadata(2);
	assert(!open_state(&s)); s.non_slot_names = "oplusstanvbk_a";
	assert(ab_validate(&s, 2, AB_ANDROID)); ab_free(&s); cases++;
	/* Independently check mandatory names cannot be configured as exceptions. */
	fixture(); assert(!open_state(&s)); s.non_slot_names = "boot_a";
	assert(ab_non_slot(&s, s.disk[0].entries[0], "boot_a") < 0); ab_free(&s); cases++;
}
int main(void)
{
	struct ab_state s;
	unsigned int i, normal_writes, normal_reads;
	confirmation_scope_tests();
	non_slot_policy_tests();
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
	/* Marble: the authoritative primary is confirmed and the backup rebuilt
	 * from it, for a stale backup array with a valid or stale entries CRC.
	 * Only boot_b's LU is written; a stale LU 1 is validated read-only. */
	for (i = 0; i < 4; i++) {
		unsigned char expected[12 * 128], lun1[BLOCKS * AB_BLOCK];
		fixture(); marble_stale(i & 1, i >> 1); tolerate = 1;
		assert(!open_state(&s) && s.disk[0].stale_backup && s.disk[1].stale_backup == (int)(i >> 1));
		assert(!ab_validate(&s, 2, AB_CONFIRM));
		ab_plan_confirm(&s); assert(!ab_store(&s, 0)); ab_free(&s);
		memcpy(expected, original[0] + 2 * AB_BLOCK, sizeof(expected));
		expected[128 + 54] |= 0x40;
		assert_synced(expected, 0);
		assert(ab_get(slot_entry(0, 1, 1) + 48, 8) == ((6ULL << 51) | AB_ACTIVE | AB_PRIORITY | AB_SUCCESS));
		/* Padding, payload and the other LU are untouched. */
		assert(!memcmp(media[0] + (BLOCKS - 2) * AB_BLOCK + 12 * 128,
			       original[0] + (BLOCKS - 2) * AB_BLOCK + 12 * 128, AB_BLOCK - 12 * 128));
		assert(!memcmp(media[0] + 3 * AB_BLOCK, original[0] + 3 * AB_BLOCK, (BLOCKS - 5) * AB_BLOCK));
		memcpy(lun1, original[1], sizeof(lun1));
		assert(!memcmp(media[1], lun1, sizeof(lun1)));
		/* LU 0 now passes the strict both-copies rule; a stale LU 1 does not. */
		tolerate = 0;
		assert(!open_state(&s) == !(i >> 1));
		ab_free(&s); cases++;
	}
	/* Every write/read fault restores the original (stale) state. */
	fixture(); marble_stale(1, 0); tolerate = 1; assert(!open_state(&s));
	ab_plan_confirm(&s); reads = 0; assert(!ab_store(&s, 0)); ab_free(&s);
	normal_writes = writes; normal_reads = reads; assert(normal_writes == 4);
	for (i = 1; i <= normal_writes + 2 * normal_reads; i++) {
		fixture(); marble_stale(1, 0); tolerate = 1; assert(!open_state(&s));
		ab_plan_confirm(&s); reads = writes = 0;
		if (i <= normal_writes) fail_write = i;
		else if (i <= normal_writes + normal_reads) fail_read = i - normal_writes;
		else mismatch_read = i - normal_writes - normal_reads;
		assert(ab_store(&s, 0));
		fail_write = fail_read = mismatch_read = 0;
		assert(!ab_store(&s, 1) && !memcmp(media, original, sizeof(media)));
		ab_free(&s); cases++;
	}
	/* Power loss after the backup write (backup = confirmed primary, primary
	 * old) and the ABL state (primary newer) are both accepted. */
	for (i = 0; i < 2; i++) {
		fixture(); marble_stale(1, 0);
		if (!i) {
			memcpy(slot_entry(0, 1, 0), slot_entry(0, 0, 0), 12 * 128);
			slot_entry(0, 1, 1)[54] |= 0x40;
		} else {
			slot_entry(0, 0, 1)[54] |= 0x40;
		}
		reseal(0, !i); memcpy(original, media, sizeof(media)); tolerate = 1;
		assert(!open_state(&s) && s.disk[0].stale_backup && !ab_validate(&s, 2, AB_CONFIRM));
		ab_free(&s); cases++;
	}
	/* The stale-backup rule is confirmation-only and exactly scoped. */
	for (i = 0; i < 17; i++) {
		fixture(); marble_stale(1, 0); tolerate = i != 0;
		switch (i) {
		case 1: ab_put(slot_entry(0, 1, 0) + 32, 9, 8); break;        /* boot_a LBA */
		case 2: ab_put(slot_entry(0, 1, 1) + 40, 12, 8); break;       /* boot_b end */
		case 3: slot_entry(0, 1, 1)[56] = 'B'; break;                 /* name */
		case 4: slot_entry(0, 1, 1)[16] ^= 1; break;                  /* unique GUID */
		case 5: slot_entry(0, 1, 4)[0] ^= 1; break;                   /* misc type */
		case 6: slot_entry(0, 1, 4)[48 + 6] ^= 1; break;              /* misc slot bits */
		case 7: slot_entry(0, 1, 1)[48 + 5] ^= 1; break;              /* boot_b bit 40 */
		case 8: slot_entry(0, 1, 1)[48 + 7] ^= 0x80; break;           /* boot_b bit 63 */
		case 9: slot_entry(0, 1, 8)[0] = 1; break;                    /* unused entry */
		case 10: memset(slot_entry(0, 1, 0), 0, 16); break;           /* boot_a unused */
		case 11: entry(0, 7, "lonely_a", 40);
			ab_put(slot_entry(0, 0, 7) + 32, 50, 8); ab_put(slot_entry(0, 0, 7) + 40, 51, 8);
			memcpy(slot_entry(0, 1, 7), slot_entry(0, 0, 7), 128);
			slot_entry(0, 1, 7)[0] ^= 1; reseal(0, 0); break;     /* no partner */
		case 12: slot_entry(0, 0, 1)[54] |= 0x40; break;              /* primary CRC */
		case 13: media[0][AB_BLOCK + 16] ^= 1; break;                 /* primary header */
		case 14: media[0][(BLOCKS - 1) * AB_BLOCK + 16] ^= 1; break;  /* backup header */
		case 15: ab_put(media[0] + (BLOCKS - 1) * AB_BLOCK + 48, BLOCKS - 4, 8); break;
		case 16: media[0][(BLOCKS - 1) * AB_BLOCK + 60] ^= 1; break;  /* disk GUID */
		}
		if (i >= 15) {
			unsigned char *h = media[0] + (BLOCKS - 1) * AB_BLOCK;
			memset(h + 16, 0, 4); ab_put(h + 16, crc(h, 92), 4);  /* valid CRC */
		}
		memcpy(original, media, sizeof(media));
		assert(open_state(&s) && !writes && !memcmp(media, original, sizeof(media)));
		ab_free(&s); cases++;
	}
	printf("PASS %u Qualcomm GPT validation, exact diff and fault/restore cases\n", cases);
	return 0;
}
