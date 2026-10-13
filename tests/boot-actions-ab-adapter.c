/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compile the actual storage adapter using in-memory GPT and UFS/PMIC mocks. */
#define main fixture_tests
#include "boot-actions-ab.c"
#undef main
#include <stdbool.h>
#include "../pkgs/mobile-boot-action/protocol.h"
#define UCLASS_UFS 1
#define UCLASS_BLK 2
#define UCLASS_SCSI 3
struct blk_desc {
	unsigned int uclass_id, devnum, target, lun, blksz, removable;
	unsigned long long lba;
};
struct udevice { struct udevice *parent, *next; struct blk_desc *desc; };
struct uclass { struct udevice *first; };
#define uclass_foreach_dev(dev, c) for (dev = (c)->first; dev; dev = dev->next)
static struct udevice ufs, scsi, blocks[AB_MAX_LUNS];
static struct blk_desc desc[AB_MAX_LUNS];
static struct uclass ufs_class, block_class;
static void *pon_pmic;
static bool active = true;
static unsigned int boot_lun, enabled_mask, resets, lun_writes, reason_reads, reason_writes;
static unsigned char boot_ids[AB_MAX_LUNS];
static unsigned int android_non_gpt_mask;
#define CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK android_non_gpt_mask
static unsigned char reason;
static unsigned int fail_lun_write, fail_reason_read, fail_reason_write;
static int reset_result, restore_failure;
static int fail_block_restoration;
static int uclass_get(unsigned int id, struct uclass **out)
{
	*out = id == UCLASS_UFS ? &ufs_class : &block_class;
	return 0;
}
static int device_is_compatible(struct udevice *d, const char *name)
{
	return d == &ufs && !strcmp(name, "qcom,ufshc");
}
static int device_probe(struct udevice *d) { return 0; }
static struct udevice *dev_get_parent(struct udevice *d) { return d->parent; }
static struct blk_desc *dev_get_uclass_plat(struct udevice *d) { return d->desc; }
static void blkcache_invalidate(unsigned int id, unsigned int num) {}
static unsigned int blk_dread(struct blk_desc *d, unsigned long long lba, unsigned int n, void *p)
{
	return read_blocks(media[d->devnum], lba, n, p) ? 0 : n;
}
static unsigned int blk_dwrite(struct blk_desc *d, unsigned long long lba, unsigned int n, const void *p)
{
	assert(d->devnum < 2); /* Declared non-GPT LUNs must never be written. */
	int ret = write_blocks(media[d->devnum], lba, n, p);
	return ret || (fail_block_restoration && writes > fail_write) ? 0 : n;
}
static unsigned int crc32(unsigned int seed, const void *p, unsigned int n)
{
	assert(!seed); return crc(p, n);
}
static void *malloc_cache_aligned(unsigned int n) { return malloc(n); }
static int ufs_mobile_boot_lun_get(struct udevice *d, unsigned int *lun)
{
	assert(d == &ufs); *lun = boot_lun; return 0;
}
static int ufs_mobile_boot_lun_set(struct udevice *d, unsigned int lun)
{
	assert(d == &ufs); lun_writes++; boot_lun = lun;
	return lun_writes == fail_lun_write || (restore_failure && lun == 2) ? -EIO : 0;
}
static int ufs_mobile_enabled_luns(struct udevice *d, unsigned int *mask)
{
	assert(d == &ufs); *mask = enabled_mask; return 0;
}
static int ufs_mobile_lun_info(struct udevice *d, unsigned int *mask, unsigned char ids[8])
{
	memcpy(ids, boot_ids, 8); return ufs_mobile_enabled_luns(d, mask);
}
static int pon_read(void *ctx, unsigned char *value)
{
	reason_reads++; *value = reason;
	return reason_reads == fail_reason_read ? -EIO : 0;
}
static int pon_write(void *ctx, unsigned char value)
{
	reason_writes++; reason = value;
	return reason_writes == fail_reason_write ? -EIO : 0;
}
static int pon_reset(void *ctx)
{
	resets++; assert(boot_lun == 1 && reason == 1);
	assert(media[0][2 * AB_BLOCK] == 11 && media[1][2 * AB_BLOCK] == 21);
	return reset_result;
}
#include "../pkgs/mobile-boot-action/qcom-ab-firmware.h"
static void prepare_adapter(void)
{
#ifdef MOBILE_CONFIRM_TEST
	confirmation_non_gpt_mask = 0;
#endif
	fixture(); active = true; boot_lun = 2; enabled_mask = 3; reason = 0x85;
	memset(boot_ids, 0, sizeof(boot_ids)); boot_ids[0] = 1; boot_ids[1] = 2;
	android_non_gpt_mask = 0;
	resets = lun_writes = reason_reads = reason_writes = 0;
	fail_lun_write = fail_reason_read = fail_reason_write = restore_failure = reset_result = 0;
	fail_block_restoration = 0;
	ufs = (struct udevice){0}; scsi = (struct udevice){.parent = &ufs};
	for (unsigned int i = 0; i < 2; i++) {
		desc[i] = (struct blk_desc){.uclass_id = UCLASS_SCSI, .devnum = i, .lun = i, .blksz = AB_BLOCK, .lba = BLOCKS};
		blocks[i] = (struct udevice){.parent = &scsi, .desc = &desc[i], .next = i ? NULL : &blocks[1]};
	}
	ufs_class.first = &ufs; block_class.first = &blocks[0];
}
static void prepare_android_candidate(void)
{
	prepare_adapter(); enabled_mask |= 1U << 6;
	memset(media[6], 0, sizeof(media[6]));
	desc[6] = (struct blk_desc){.uclass_id=UCLASS_SCSI,.devnum=6,.lun=6,.blksz=AB_BLOCK,.lba=BLOCKS};
	blocks[6] = (struct udevice){.parent=&scsi,.desc=&desc[6]}; blocks[1].next=&blocks[6];
	android_non_gpt_mask = 1U << 6;
}
#ifdef MOBILE_CONFIRM_TEST
#define main adapter_tests
#endif
int main(void)
{
	struct mobile_action_result result;
	unsigned int count = 0;
	/* Errors after metadata, boot-LUN and reason writes must restore all
	 * three before returning, including PSCI success/error returns. */
	for (unsigned int fault = 0; fault < 10; fault++) {
		prepare_adapter(); memset(&result, 0, sizeof(result));
		if (fault == 1) fail_write = 3;
		if (fault == 2) fail_lun_write = 1;
		if (fault == 3) fail_reason_write = 1;
		if (fault == 4) fail_reason_read = 2;
		if (fault == 5) reset_result = -1;
		if (fault == 6) fail_reason_read = 1;
		if (fault == 7) media[0][18 * AB_BLOCK] = 'b';
		if (fault == 8) enabled_mask = 7; /* omitted LU */
		if (fault == 9) boot_lun = 1;
		assert(ab_execute_android(&result) < 0);
		assert(active && !result.restore_status);
		assert(reason == 0x85 && boot_lun == (fault == 9 ? 1 : 2));
		if (fault != 7) assert(!memcmp(media, original, sizeof(media)));
		if (fault >= 6) assert(!writes && !lun_writes && !reason_writes && !resets);
		else assert(result.restore_attempted);
		count++;
	}
	prepare_adapter(); restore_failure = 1;
	assert(ab_execute_android(&result) < 0 && result.restore_status && !active);
	assert(reason == 0x85 && !memcmp(media, original, sizeof(media)));
	count++;
	/* Recovery gate is read only, even with a storage/backend fault. */
	for (unsigned int fault = 0; fault < 5; fault++) {
		struct ab_state state;
		prepare_adapter();
		if (fault == 1) enabled_mask = 7;
		if (fault == 2) desc[0].blksz = 512;
		if (fault == 3) desc[1].lun = 0;
		if (fault == 4) boot_lun = 1;
		assert(!!ab_open(&state, 1) == !!fault);
		assert(!writes && !reason_writes && !lun_writes && !resets);
		ab_free(&state); count++;
	}
	/* The snapshot record is independent of the BCB command. Every rejection
	 * occurs before GPT/boot-selector/PMIC writes, including execute recheck. */
	for (unsigned int fault = 0; fault < 13; fault++) {
		prepare_adapter();
		unsigned char *v = media[0] + 26 * AB_BLOCK;
		switch (fault) {
		case 0: v[5] = 1; break; /* UNKNOWN */
		case 1: v[5] = 2; break; /* SNAPSHOTTED */
		case 2: v[5] = 3; break; /* MERGING */
		case 3: v[5] = 4; break; /* CANCELLED requires separate semantics review */
		case 4: v[5] = 255; break;
		case 5: v[0] = 1; break;
		case 6: v[1] ^= 1; break;
		case 7: v[6] = 2; break;
		case 8: v[63] = 1; break;
		case 9: boot_ids[0] = 2; boot_ids[1] = 1; break;
		case 10: boot_ids[1] = 1; break; /* duplicate selector */
		case 11: boot_ids[1] = 0; break; /* missing selector */
		case 12: boot_ids[7] = 1; break; /* disabled LUN */
		}
		memcpy(original, media, sizeof(media));
		assert(ab_execute_android(&result) < 0);
		assert(!writes && !lun_writes && !reason_writes && !resets);
		assert(!memcmp(media, original, sizeof(media))); count++;
	}
	for (unsigned int source = 0; source < 2; source++) {
		struct ab_state state;
		prepare_adapter(); media[0][26 * AB_BLOCK + 6] = source;
		/* Other system-space structures may be nonzero. */
		media[0][26 * AB_BLOCK + 64] = 0xf0;
		assert(!ab_open(&state, AB_ANDROID)); ab_free(&state);
		assert(!writes && !lun_writes && !reason_writes && !resets); count++;
	}
	/* Android candidates have their own policy and remain enumerated. */
	for (unsigned int fault = 0; fault < 7; fault++) {
		struct ab_state state;
		prepare_android_candidate();
		if (fault == 1) android_non_gpt_mask = 0;
		if (fault == 2) media[6][AB_BLOCK - 1] = 1;
		if (fault == 3) media[6][2 * AB_BLOCK - 1] = 1;
		if (fault == 4) media[6][sizeof(media[6]) - 1] = 1;
		if (fault == 5) { boot_ids[0] = 0; boot_ids[6] = 1; }
		if (fault == 6) blocks[1].next = NULL;
		assert(!!ab_open(&state, AB_ANDROID) == !!fault); ab_free(&state);
		assert(!writes && !lun_writes && !reason_writes && !resets); count++;
	}
	{
		struct ab_state state;
		unsigned int total_reads;
		prepare_android_candidate();
		assert(!ab_open(&state, AB_ANDROID)); total_reads = reads; ab_free(&state);
		/* Includes all three candidate reads, BCB and independent snapshot I/O. */
		for (unsigned int failure = 1; failure <= total_reads; failure++) {
			prepare_android_candidate(); fail_read = failure;
			assert(ab_open(&state, AB_ANDROID) < 0); ab_free(&state);
			assert(!writes && !lun_writes && !reason_writes && !resets); count++;
		}
		prepare_android_candidate();
		assert(ab_open(&state, AB_RECOVERY) == -EINVAL); ab_free(&state); count++;
		prepare_adapter();
		ab_put(media[0] + 2 * AB_BLOCK + 4 * 128 + 40, 19, 8);
		memcpy(media[0] + (BLOCKS - 2) * AB_BLOCK, media[0] + 2 * AB_BLOCK, 12 * 128);
		headers(0);
		assert(ab_open(&state, AB_ANDROID) == -EINVAL); ab_free(&state);
		assert(!writes && !lun_writes && !reason_writes && !resets); count++;
		/* Mask candidates with valid GPTs participate in global checks. */
		for (unsigned int fault = 0; fault < 4; fault++) {
			prepare_android_candidate();
			entry(6, 0, fault == 2 ? "boot_b" : "extra", 32);
			memcpy(media[6] + (BLOCKS - 2) * AB_BLOCK, media[6] + 2 * AB_BLOCK, 12 * 128);
			headers(6);
			if (fault == 1) media[6][AB_BLOCK + 16] ^= 1;
			if (fault == 3) media[6][(BLOCKS - 1) * AB_BLOCK + 16] ^= 1;
			assert(!!ab_open(&state, AB_ANDROID) == !!fault); ab_free(&state);
			assert(!writes && !lun_writes && !reason_writes && !resets); count++;
		}
	}
	printf("PASS %u actual A/B storage adapter/slot/PMIC fault cases\n", count);
	return 0;
}
