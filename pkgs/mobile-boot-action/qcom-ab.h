/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef MOBILE_QCOM_AB_H
#define MOBILE_QCOM_AB_H

/* Qualcomm GPT slot metadata, not AOSP's misc boot_control. Values follow
 * PartitionTableUpdate.{c,h}, ABL 794aac3253f94ceb13c94795b8ab5c1d18e186b2:
 * https://github.com/CodeLinaro-mirror/la_abl_tianocore_edk2/tree/794aac3253f94ceb13c94795b8ab5c1d18e186b2/QcomModulePkg/Library/BootLib
 * This implementation preserves raw block padding and never writes payloads.
 * Caller provides bounded DMA-safe buffers and uncached, durable block I/O. */
#define AB_BLOCK 4096
#define AB_MAX_ENTRIES 256
#define AB_MAX_LUNS 8
#define AB_ACTIVE (1ULL << 50)
#define AB_PRIORITY (3ULL << 48)
#define AB_RETRY (7ULL << 51)
#define AB_SUCCESS (1ULL << 54)
#define AB_UNBOOTABLE (1ULL << 55)

struct ab_disk {
	void *context;
	unsigned long long blocks;
	unsigned int count, bytes, array_blocks;
	unsigned long long array_lba[2];
	unsigned char *header[2], *entries[2];
	unsigned char *new_header[2], *new_entries[2];
	int touched[2];
};
struct ab_ops {
	int (*read)(void *, unsigned long long, unsigned int, void *);
	int (*write)(void *, unsigned long long, unsigned int, const void *);
	unsigned int (*crc)(const void *, unsigned int);
	void *(*alloc)(unsigned int);
	void (*release)(void *);
};
struct ab_state {
	const struct ab_ops *ops;
	struct ab_disk disk[AB_MAX_LUNS];
	unsigned int disks;
	unsigned char *scratch;
};
static unsigned long long ab_get(const unsigned char *p, unsigned int n)
{
	unsigned long long v = 0;
	unsigned int i;
	for (i = 0; i < n; i++)
		v |= (unsigned long long)p[i] << (8 * i);
	return v;
}
static void ab_put(unsigned char *p, unsigned long long v, unsigned int n)
{
	unsigned int i;
	for (i = 0; i < n; i++)
		p[i] = v >> (8 * i);
}
static int ab_zero(const unsigned char *p, unsigned int n)
{
	unsigned int i;
	for (i = 0; i < n; i++)
		if (p[i])
			return 0;
	return 1;
}
static int ab_header(struct ab_state *s, struct ab_disk *d, unsigned int side)
{
	unsigned char *h = d->header[side];
	unsigned long long first, last, arr;
	unsigned int count, size, expected;
	if (memcmp(h, "EFI PART", 8) || ab_get(h + 8, 4) != 0x10000 ||
	    ab_get(h + 12, 4) != 92 || ab_get(h + 20, 4) ||
	    ab_get(h + 24, 8) != (side ? d->blocks - 1 : 1) ||
	    ab_get(h + 32, 8) != (side ? 1 : d->blocks - 1) || ab_zero(h + 56, 16))
		return -EINVAL;
	expected = ab_get(h + 16, 4);
	memcpy(s->scratch, h, AB_BLOCK);
	memset(s->scratch + 16, 0, 4);
	if (s->ops->crc(s->scratch, 92) != expected)
		return -EINVAL;
	count = ab_get(h + 80, 4);
	size = ab_get(h + 84, 4);
	if (!count || count > AB_MAX_ENTRIES || size != 128)
		return -EINVAL;
	if (!side) {
		d->count = count;
		d->bytes = count * size;
		d->array_blocks = (d->bytes + AB_BLOCK - 1) / AB_BLOCK;
	} else if (count != d->count || memcmp(h + 40, d->header[0] + 40, 32)) {
		return -EINVAL;
	}
	first = ab_get(h + 40, 8);
	last = ab_get(h + 48, 8);
	arr = ab_get(h + 72, 8);
	/* Bound all metadata outside the usable region. No offset can alias a
	 * payload/header or wrap, even for a malformed input. */
	if (first < 2 + d->array_blocks || first > last ||
	    last >= d->blocks - 1 - d->array_blocks ||
	    (!side && (arr < 2 || arr > first - d->array_blocks)) ||
	    (side && (arr <= last || arr > d->blocks - 1 - d->array_blocks)))
		return -EINVAL;
	d->array_lba[side] = arr;
	return 0;
}
static int ab_load(struct ab_state *s, struct ab_disk *d)
{
	unsigned int side, i, j;
	int ret;
	if (d->blocks < 16 || d->blocks > 0xffffffffULL)
		return -EINVAL; /* SCSI WRITE(10) addressing limit. */
	for (side = 0; side < 2; side++) {
		d->header[side] = s->ops->alloc(AB_BLOCK);
		d->new_header[side] = s->ops->alloc(AB_BLOCK);
		if (!d->header[side] || !d->new_header[side])
			return -ENOMEM;
		ret = s->ops->read(d->context, side ? d->blocks - 1 : 1, 1, d->header[side]);
		if (ret || (ret = ab_header(s, d, side)))
			return ret;
		d->entries[side] = s->ops->alloc(d->array_blocks * AB_BLOCK);
		d->new_entries[side] = s->ops->alloc(d->array_blocks * AB_BLOCK);
		if (!d->entries[side] || !d->new_entries[side])
			return -ENOMEM;
		ret = s->ops->read(d->context, d->array_lba[side], d->array_blocks, d->entries[side]);
		if (ret)
			return ret;
		if (s->ops->crc(d->entries[side], d->bytes) != ab_get(d->header[side] + 88, 4) ||
		    (side && memcmp(d->entries[0], d->entries[1], d->bytes)))
			return -EINVAL;
		memcpy(d->new_header[side], d->header[side], AB_BLOCK);
		memcpy(d->new_entries[side], d->entries[side], d->array_blocks * AB_BLOCK);
	}
	for (i = 0; i < d->count; i++) {
		unsigned char *e = d->entries[0] + 128 * i;
		unsigned long long start = ab_get(e + 32, 8), end = ab_get(e + 40, 8);
		if (ab_zero(e, 16))
			continue;
		if (ab_zero(e + 16, 16) || start > end || start < ab_get(d->header[0] + 40, 8) ||
		    end > ab_get(d->header[0] + 48, 8))
			return -EINVAL;
		for (j = 0; j < i; j++) {
			unsigned char *other = d->entries[0] + 128 * j;
			if (!ab_zero(other, 16) &&
			    (start <= ab_get(other + 40, 8) && end >= ab_get(other + 32, 8)))
				return -EINVAL;
		}
	}
	return 0;
}
static void ab_free(struct ab_state *s)
{
	unsigned int i, side;
	for (i = 0; i < s->disks; i++)
		for (side = 0; side < 2; side++) {
			s->ops->release(s->disk[i].header[side]);
			s->ops->release(s->disk[i].new_header[side]);
			s->ops->release(s->disk[i].entries[side]);
			s->ops->release(s->disk[i].new_entries[side]);
		}
	s->ops->release(s->scratch);
}
static int ab_name(const unsigned char *e, char *name)
{
	unsigned int i;
	for (i = 0; i < 36; i++) {
		if (e[56 + 2 * i + 1] || e[56 + 2 * i] > 127)
			return -EINVAL;
		name[i] = e[56 + 2 * i];
		if (!name[i])
			return i ? 0 : -EINVAL;
	}
	return -EINVAL;
}
/* Require an unambiguous global name. */
static unsigned char *ab_find(struct ab_state *s, const char *name)
{
	unsigned int i, j;
	unsigned char *found = NULL;
	char actual[36];
	for (i = 0; i < s->disks; i++)
		for (j = 0; j < s->disk[i].count; j++) {
			unsigned char *e = s->disk[i].entries[0] + 128 * j;
			if (ab_zero(e, 16))
				continue;
			if (ab_name(e, actual))
				return NULL;
			if (!strcmp(actual, name)) {
				if (found)
					return NULL;
				found = e;
			}
		}
	return found;
}
static int ab_bootable(const unsigned char *e)
{
	unsigned long long a = ab_get(e + 48, 8);
	return !(a & AB_UNBOOTABLE) && (a & AB_PRIORITY) && (a & (AB_SUCCESS | AB_RETRY));
}
/* AOSP Android 13 misc_virtual_ab_message, packed v2 at misc + 32 KiB:
 * https://android.googlesource.com/platform/bootable/recovery/+/refs/tags/android-13.0.0_r1/bootloader_message/include/bootloader_message/bootloader_message.h
 * Only a known NONE state is accepted. Never cancel/clear snapshot metadata. */
static int ab_snapshot_none(struct ab_state *s, struct ab_disk *d, const unsigned char *misc)
{
	unsigned long long start = ab_get(misc + 32, 8), end = ab_get(misc + 40, 8);
	int ret;
	if (end < start || end - start < 8)
		return -EINVAL; /* The complete read block must lie inside misc. */
	ret = s->ops->read(d->context, start + 8, 1, s->scratch);
	if (ret)
		return ret;
	if (s->scratch[0] != 2 || ab_get(s->scratch + 1, 4) != 0x56740ab0 ||
	    s->scratch[6] > 1 || !ab_zero(s->scratch + 7, 57))
		return -EINVAL;
	return s->scratch[5] ? -EBUSY : 0;
}
enum ab_purpose { AB_ANDROID, AB_RECOVERY, AB_CONFIRM };
static int ab_validate(struct ab_state *s, unsigned int boot_lun, enum ab_purpose purpose)
{
	unsigned char *a = ab_find(s, "boot_a"), *b = ab_find(s, "boot_b");
	unsigned char *misc = ab_find(s, "misc"), *abl = ab_find(s, "abl_b");
	unsigned int i, j;
	char name[36], peer[36];
	/* ABL may decrement retry to zero before this final allowed boot. */
	if (!a || !b || !abl || boot_lun != 2 ||
	    (purpose == AB_CONFIRM ?
	     ((ab_get(b + 48, 8) & AB_UNBOOTABLE) || !(ab_get(b + 48, 8) & AB_PRIORITY)) :
	     !ab_bootable(b)) ||
	    !(ab_get(b + 48, 8) & AB_ACTIVE) || (ab_get(a + 48, 8) & AB_ACTIVE) ||
	    !memcmp(b, abl, 16) ||
	    (purpose != AB_CONFIRM && !misc) ||
	    (purpose == AB_RECOVERY && !ab_find(s, "recovery_b")))
		return -EINVAL;
	/* Require all pairs and their active bits to agree before any switch.
	 * XBL selection is through bBootLunEn, not a GUID exchange. */
	for (i = 0; i < s->disks; i++)
		for (j = 0; j < s->disk[i].count; j++) {
			unsigned char *e = s->disk[i].entries[0] + 128 * j, *other;
			unsigned int n;
			if (ab_zero(e, 16))
				continue;
			if (ab_name(e, name) || ab_find(s, name) != e)
				return -EINVAL;
			n = strlen(name);
			if (n < 3 || name[n - 2] != '_' || (name[n - 1] != 'a' && name[n - 1] != 'b'))
				continue;
			strcpy(peer, name);
			peer[n - 1] = name[n - 1] == 'a' ? 'b' : 'a';
			other = ab_find(s, peer);
			if (!other)
				return -EINVAL;
			if (!strcmp(name, "xbl_a") || !strcmp(name, "xbl_b")) {
				if (memcmp(e, other, 16))
					return -EINVAL;
				continue;
			}
			if (!!(ab_get(e + 48, 8) & AB_ACTIVE) != (name[n - 1] == 'b'))
				return -EINVAL;
		}
	/* An outstanding BCB command can override normal boot_a. Read only;
	 * never silently discard recovery/OTA requests from this EFI helper. */
	if (purpose == AB_ANDROID) {
		if (!ab_bootable(a))
			return -EINVAL;
		for (i = 0; i < s->disks; i++) {
			struct ab_disk *d = &s->disk[i];
			for (j = 0; j < d->count; j++)
				if (d->entries[0] + j * 128 == misc) {
					if (s->ops->read(d->context, ab_get(misc + 32, 8), 1, s->scratch))
						return -EIO;
					if (s->scratch[0])
						return -EBUSY;
					int ret = ab_snapshot_none(s, d, misc);
					if (ret) {
						printf("Mobile boot action: snapshot state check failed (%d)\n", ret);
						return ret;
					}
				}
		}
	}
	return 0;
}
static inline void ab_plan_confirm(struct ab_state *s)
{
	unsigned char *b = ab_find(s, "boot_b");
	unsigned int i, j, side;
	for (i = 0; i < s->disks; i++) {
		struct ab_disk *d = &s->disk[i];
		for (j = 0; j < d->count; j++) {
			if (d->entries[0] + j * 128 != b)
				continue;
			for (side = 0; side < 2; side++) {
				unsigned char *e = d->new_entries[side] + j * 128;
				unsigned char *h = d->new_header[side];
				ab_put(e + 48, ab_get(e + 48, 8) | AB_SUCCESS, 8);
				ab_put(h + 88, s->ops->crc(d->new_entries[side], d->bytes), 4);
				memset(h + 16, 0, 4);
				ab_put(h + 16, s->ops->crc(h, 92), 4);
			}
		}
	}
}
static void ab_plan_android(struct ab_state *s)
{
	unsigned int i, j, side;
	char name[36], peer[36];
	for (i = 0; i < s->disks; i++)
		for (j = 0; j < s->disk[i].count; j++) {
			unsigned char *e = s->disk[i].entries[0] + 128 * j;
			unsigned int n;
			if (ab_zero(e, 16))
				continue;
			ab_name(e, name); /* validated */
			n = strlen(name);
			if (n < 3 || name[n - 2] != '_' || (name[n - 1] != 'a' && name[n - 1] != 'b'))
				continue;
			if (!strcmp(name, "xbl_a") || !strcmp(name, "xbl_b"))
				continue;
			strcpy(peer, name);
			peer[n - 1] = name[n - 1] == 'a' ? 'b' : 'a';
			for (side = 0; side < 2; side++) {
				unsigned char *p = s->disk[i].new_entries[side] + 128 * j;
				unsigned long long attr = ab_get(e + 48, 8);
				memcpy(p, ab_find(s, peer), 16);
				attr = (attr & ~AB_ACTIVE) | (name[n - 1] == 'a' ? AB_ACTIVE : 0);
				if (!strcmp(name, "boot_a"))
					attr = (attr & ~(AB_SUCCESS | AB_UNBOOTABLE | AB_PRIORITY | AB_RETRY)) |
					       AB_PRIORITY | AB_RETRY | AB_ACTIVE;
				if (!strcmp(name, "boot_b"))
					attr = (attr & ~AB_PRIORITY) | (2ULL << 48);
				ab_put(p + 48, attr, 8);
			}
		}
	for (i = 0; i < s->disks; i++)
		for (side = 0; side < 2; side++) {
			struct ab_disk *d = &s->disk[i];
			unsigned char *h = d->new_header[side];
			ab_put(h + 88, s->ops->crc(d->new_entries[side], d->bytes), 4);
			memset(h + 16, 0, 4);
			ab_put(h + 16, s->ops->crc(h, 92), 4);
		}
}
static int ab_compare(struct ab_state *s, struct ab_disk *d, unsigned long long lba,
		      unsigned int blocks, const unsigned char *expected)
{
	unsigned int k;
	for (k = 0; k < blocks; k++)
		if (s->ops->read(d->context, lba + k, 1, s->scratch) ||
		    memcmp(s->scratch, expected + k * AB_BLOCK, AB_BLOCK))
			return -EIO;
	return 0;
}
static int ab_store(struct ab_state *s, int restore)
{
	unsigned int i, round, k;
	int ret, first_error = 0;
	for (i = 0; i < s->disks; i++) {
		struct ab_disk *d = &s->disk[i];
		/* Complete/read back backup before writing the primary copy. */
		for (round = 0; round < 2; round++) {
			unsigned int side = 1 - round;
			unsigned char *entries = restore ? d->entries[side] : d->new_entries[side];
			unsigned char *header = restore ? d->header[side] : d->new_header[side];
			if (restore && !d->touched[side])
				continue;
			if (!restore) {
				ret = ab_compare(s, d, d->array_lba[side], d->array_blocks, d->entries[side]);
				if (!ret)
					ret = ab_compare(s, d, side ? d->blocks - 1 : 1, 1, d->header[side]);
				if (ret)
					return ret;
			}
			for (k = 0; k < d->array_blocks; k++) {
				if (!restore && !memcmp(entries + AB_BLOCK * k, d->entries[side] + AB_BLOCK * k, AB_BLOCK))
					continue;
				d->touched[side] = 1; /* also restore a partially failed write */
				ret = s->ops->write(d->context, d->array_lba[side] + k, 1, entries + AB_BLOCK * k);
				if (ret && !restore)
					return ret;
				if (ret && !first_error)
					first_error = ret;
			}
			if (restore || memcmp(header, d->header[side], AB_BLOCK)) {
				d->touched[side] = 1;
				ret = s->ops->write(d->context, side ? d->blocks - 1 : 1, 1, header);
				if (ret && !restore)
					return ret;
				if (ret && !first_error)
					first_error = ret;
			}
			ret = ab_compare(s, d, d->array_lba[side], d->array_blocks, entries);
			if (!ret)
				ret = ab_compare(s, d, side ? d->blocks - 1 : 1, 1, header);
			if (ret && !restore)
				return ret;
			if (ret && !first_error)
				first_error = ret;
		}
	}
	return first_error;
}
#endif
