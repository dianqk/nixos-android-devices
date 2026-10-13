/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef MOBILE_QCOM_AB_FIRMWARE_H
#define MOBILE_QCOM_AB_FIRMWARE_H
#include <blk.h>
#include <malloc.h>
#include <memalign.h>
#include <ufs.h>
#include <u-boot/crc.h>
#include "mobile_qcom_ab.h"

static struct udevice *ab_ufs;
static int ab_read_blocks(void *context, unsigned long long lba, unsigned int count, void *data)
{
	struct blk_desc *d = context;
	blkcache_invalidate(d->uclass_id, d->devnum);
	return blk_dread(d, lba, count, data) == count ? 0 : -EIO;
}
static int ab_write_blocks(void *context, unsigned long long lba, unsigned int count, const void *data)
{
	/* Fixed U-Boot's SCSI WRITE(10) sets FUA; writes bypass the device cache. */
	return blk_dwrite(context, lba, count, data) == count ? 0 : -EIO;
}
static unsigned int ab_crc(const void *data, unsigned int bytes) { return crc32(0, data, bytes); }
static void *ab_alloc(unsigned int bytes) { return malloc_cache_aligned(bytes); }
static const struct ab_ops ab_block_ops = {ab_read_blocks, ab_write_blocks, ab_crc, ab_alloc, free};

#if defined(CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK) || \
    defined(CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK)
/* An explicit profile permits zero-metadata layouts on candidate LUNs. This
 * does not imply their payload is empty. Any nonzero metadata goes through
 * full GPT validation; a failed read can never establish an exception. */
static int ab_non_gpt(struct ab_state *s, struct blk_desc *d, bool *non_gpt)
{
	unsigned long long lba[] = {0, 1, d->lba - 1};
	unsigned int i;
	int ret;
	*non_gpt = true;
	for (i = 0; i < sizeof(lba) / sizeof(lba[0]); i++) {
		ret = s->ops->read(d, lba[i], 1, s->scratch);
		if (ret)
			return ret;
		if (!ab_zero(s->scratch, AB_BLOCK))
			*non_gpt = false;
	}
	return 0;
}
#endif

/* Bind selector IDs to actual XBL placement, never ordinary LUN numbers. */
static int ab_boot_mapping(struct ab_state *s, const unsigned char ids[AB_MAX_LUNS])
{
	unsigned int selector, i, j;
	for (selector = 1; selector <= 2; selector++) {
		unsigned char *xbl = ab_find(s, selector == 1 ? "xbl_a" : "xbl_b");
		bool found = false;
		if (!xbl)
			return -EINVAL;
		for (i = 0; i < s->disks; i++)
			for (j = 0; j < s->disk[i].count; j++)
				if (s->disk[i].entries[0] + j * 128 == xbl) {
					struct blk_desc *d = s->disk[i].context;
					if (ids[d->lun] != selector)
						return -EINVAL;
					found = true;
				}
		if (!found)
			return -EINVAL;
	}
	return 0;
}

static int ab_open(struct ab_state *s, enum ab_purpose purpose)
{
	struct uclass *ufs_class, *blk_class;
	struct udevice *dev;
	unsigned int enabled, seen = 0, boot_lun, non_gpt_mask = 0;
	unsigned char boot_ids[AB_MAX_LUNS] = {0};
	int ret, matches = 0;
	memset(s, 0, sizeof(*s));
	s->ops = &ab_block_ops;
	ab_ufs = NULL;
	ret = uclass_get(UCLASS_UFS, &ufs_class);
	if (ret)
		return ret;
	uclass_foreach_dev(dev, ufs_class) {
		if (device_is_compatible(dev, "qcom,ufshc")) {
			ab_ufs = dev;
			matches++;
		}
	}
	if (matches != 1)
		return -ENODEV;
	ret = device_probe(ab_ufs);
	if (ret || (ret = ufs_mobile_boot_lun_get(ab_ufs, &boot_lun)))
		return ret;
	ret = purpose == AB_ANDROID ? ufs_mobile_lun_info(ab_ufs, &enabled, boot_ids) :
		ufs_mobile_enabled_luns(ab_ufs, &enabled);
	if (ret) {
		printf("Mobile boot action: UFS descriptor check failed (%d)\n", ret);
		return ret;
	}
	if (purpose == AB_ANDROID) {
		unsigned int counts[3] = {0};
		for (unsigned int i = 0; i < AB_MAX_LUNS; i++) {
			if (boot_ids[i] > 2 || (!(enabled & (1U << i)) && boot_ids[i]))
				return -EINVAL;
			counts[boot_ids[i]]++;
		}
		if (counts[1] != 1 || counts[2] != 1) {
			printf("Mobile boot action: missing or duplicate boot-LU IDs\n");
			return -EINVAL;
		}
	}
#ifdef CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK
	if (purpose == AB_CONFIRM)
		non_gpt_mask = CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK;
#endif
#ifdef CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK
	if (purpose == AB_ANDROID)
		non_gpt_mask = CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK;
#endif
	ret = uclass_get(UCLASS_BLK, &blk_class);
	if (ret)
		return ret;
	s->scratch = ab_alloc(AB_BLOCK);
	if (!s->scratch)
		return -ENOMEM;
	uclass_foreach_dev(dev, blk_class) {
		struct udevice *parent = dev_get_parent(dev);
		struct blk_desc *d;
		if (!parent || dev_get_parent(parent) != ab_ufs)
			continue;
		ret = device_probe(dev);
		if (ret)
			return ret;
		d = dev_get_uclass_plat(dev);
		if (d->uclass_id != UCLASS_SCSI || d->target != 0 || d->lun >= AB_MAX_LUNS ||
		    d->blksz != AB_BLOCK || d->removable || !(enabled & (1U << d->lun)) ||
		    (seen & (1U << d->lun)) || s->disks == AB_MAX_LUNS ||
		    d->lba < 16 || d->lba > 0xffffffffULL)
			return -EINVAL;
		seen |= 1U << d->lun;
#if defined(CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK) || \
    defined(CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK)
		if (non_gpt_mask & (1U << d->lun)) {
			bool non_gpt;
			ret = ab_non_gpt(s, d, &non_gpt);
			if (ret)
				return ret;
			if (non_gpt) {
				if (purpose == AB_ANDROID && boot_ids[d->lun])
					return -EINVAL;
				continue;
			}
		}
#else
		(void)non_gpt_mask;
#endif
		s->disk[s->disks].context = d;
		s->disk[s->disks].blocks = d->lba;
		ret = ab_load(s, &s->disk[s->disks++]);
		if (ret) {
			printf("Mobile boot action: LUN %u GPT validation failed (%d)\n", d->lun, ret);
			return ret;
		}
	}
	if (!enabled || seen != enabled)
		return -ENODEV; /* An unscanned/missing LUN must never be omitted. */
	if (purpose == AB_ANDROID && (ret = ab_boot_mapping(s, boot_ids))) {
		printf("Mobile boot action: boot-LU IDs do not match XBL placement (%d)\n", ret);
		return ret;
	}
	ret = ab_validate(s, boot_lun, purpose);
	if (ret)
		printf("Mobile boot action: slot/request check failed (%d)\n", ret);
	return ret;
}

static int ab_execute_android(struct mobile_action_result *result)
{
	struct ab_state state;
	unsigned char old_reason, wanted, actual;
	unsigned int boot_lun;
	int ret, restore_error = 0, reason_touched = 0, lun_touched = 0;
	result->stage = MOBILE_STAGE_STORAGE;
	ret = ab_open(&state, AB_ANDROID);
	if (ret)
		goto done;
	result->stage = MOBILE_STAGE_READ;
	ret = pon_read(pon_pmic, &old_reason);
	if (ret)
		goto done;
	ab_plan_android(&state);
	result->stage = MOBILE_STAGE_STORAGE;
	ret = ab_store(&state, 0);
	if (ret)
		goto restore;
	result->stage = MOBILE_STAGE_SLOT;
	lun_touched = 1;
	ret = ufs_mobile_boot_lun_set(ab_ufs, 1);
	if (!ret)
		ret = ufs_mobile_boot_lun_get(ab_ufs, &boot_lun);
	if (!ret && boot_lun != 1)
		ret = -EIO;
	if (ret)
		goto restore;
	/* Clear only SDAM's reboot-mode bits; a nonempty BCB was rejected. */
	wanted = old_reason & 1;
	result->stage = MOBILE_STAGE_WRITE;
	reason_touched = 1;
	ret = pon_write(pon_pmic, wanted);
	if (ret)
		goto restore;
	result->stage = MOBILE_STAGE_VERIFY;
	ret = pon_read(pon_pmic, &actual);
	if (!ret && actual != wanted)
		ret = -EIO;
	if (ret)
		goto restore;
	result->stage = MOBILE_STAGE_RESET;
	ret = pon_reset(NULL);
restore:
	result->operation_status = ret;
	result->restore_attempted = 1;
	restore_error = ab_store(&state, 1);
	/* Try every restoration even when an earlier one failed. */
	if (lun_touched) {
		int error = ufs_mobile_boot_lun_set(ab_ufs, 2);
		if (!error)
			error = ufs_mobile_boot_lun_get(ab_ufs, &boot_lun);
		if (!error && boot_lun != 2)
			error = -EIO;
		if (!restore_error)
			restore_error = error;
	}
	if (reason_touched) {
		int error = pon_write(pon_pmic, old_reason);
		if (!error)
			error = pon_read(pon_pmic, &actual);
		if (!error && actual != old_reason)
			error = -EIO;
		if (!restore_error)
			restore_error = error;
	}
	result->restore_status = restore_error;
	if (restore_error)
		active = false;
done:
	result->operation_status = ret;
	ab_free(&state);
	return ret ? ret : -EIO;
}
#endif
