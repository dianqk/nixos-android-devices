/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compile the UFS patch's actual narrow API using independent descriptor fixtures. */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
typedef unsigned char u8;
#define UCLASS_UFS 1
#define UPIU_QUERY_OPCODE_READ_ATTR 1
#define UPIU_QUERY_OPCODE_WRITE_ATTR 2
#define UPIU_QUERY_OPCODE_READ_DESC 3
#define QUERY_ATTR_IDN_BOOT_LU_EN 0
#define QUERY_DESC_IDN_DEVICE 0
#define QUERY_DESC_IDN_CONFIGURATION 1
#define QUERY_DESC_MAX_SIZE 255
#define DEVICE_DESC_PARAM_UD_OFFSET 0x1a
#define DEVICE_DESC_PARAM_UD_LEN 0x1b
struct ufs_hba { struct { unsigned int dev_desc; } desc_size; };
struct udevice { bool active; unsigned int uclass; struct ufs_hba hba; };
static u8 device_bytes[255], configuration_bytes[255];
static unsigned int config_length, boot_lun, attr_writes;
static int attr_error, desc_error;
static struct ufs_hba *dev_get_uclass_priv(struct udevice *d) { return &d->hba; }
static unsigned int device_get_uclass_id(struct udevice *d) { return d->uclass; }
static bool device_active(struct udevice *d) { return d->active; }
static int ufshcd_query_attr_retry(struct ufs_hba *h, unsigned int op, unsigned int id,
				 unsigned int index, unsigned int selector, unsigned int *v)
{
	assert(id == 0 && index == 0 && selector == 0);
	if (op == UPIU_QUERY_OPCODE_WRITE_ATTR) { attr_writes++; boot_lun = *v; }
	else *v = boot_lun;
	return attr_error;
}
static int ufshcd_read_desc(struct ufs_hba *h, unsigned int id, unsigned int index, u8 *buf, unsigned int n)
{
	assert(id == 0 && index == 0 && n <= sizeof(device_bytes));
	memcpy(buf, device_bytes, n); return desc_error;
}
static int ufshcd_query_descriptor_retry(struct ufs_hba *h, unsigned int op, unsigned int id,
				       unsigned int index, unsigned int selector, u8 *buf, int *length)
{
	assert(op == 3 && id == 1 && !index && !selector && *length >= (int)config_length);
	memcpy(buf, configuration_bytes, config_length); *length = config_length;
	return desc_error;
}
#include "mobile-ufs-api.c"
int main(void)
{
	struct udevice d = {.active = true, .uclass = UCLASS_UFS, .hba.desc_size.dev_desc = 0x40};
	unsigned int mask = 0, v, cases = 0;
	u8 ids[8];
	/* UFS 2.x and longer UFS 3.x layout, with only six enabled LUNs. */
	for (unsigned int version = 0; version < 2; version++) {
		unsigned int offset = version ? 0x16 : 0x10, stride = version ? 0x1a : 0x10;
		memset(device_bytes, 0, sizeof(device_bytes)); memset(configuration_bytes, 0, sizeof(configuration_bytes));
		device_bytes[0] = 0x40; device_bytes[0x1a] = offset; device_bytes[0x1b] = stride;
		config_length = offset + 8 * stride;
		configuration_bytes[0] = config_length; configuration_bytes[1] = 1;
		configuration_bytes[3] = 1;
		configuration_bytes[offset + stride + 1] = 1;
		configuration_bytes[offset + 2 * stride + 1] = 2;
		for (unsigned int i = 0; i < 6; i++) configuration_bytes[offset + i * stride] = 1;
		assert(!ufs_mobile_enabled_luns(&d, &mask) && mask == 0x3f); cases++;
		assert(!ufs_mobile_lun_info(&d, &mask, ids) && mask == 0x3f && ids[1] == 1 && ids[2] == 2); cases++;
		configuration_bytes[3] = 0;
		assert(ufs_mobile_lun_info(&d, &mask, ids) == -EINVAL); cases++;
		assert(!ufs_mobile_enabled_luns(&d, &mask)); cases++;
		configuration_bytes[3] = 1;
		configuration_bytes[offset + 1] = 3;
		assert(ufs_mobile_lun_info(&d, &mask, ids) == -EINVAL); cases++;
		configuration_bytes[offset + 1] = 0;
		configuration_bytes[offset + 7 * stride + 1] = 1;
		assert(ufs_mobile_lun_info(&d, &mask, ids) == -EINVAL); cases++;
		configuration_bytes[offset + 7 * stride + 1] = 0;
		configuration_bytes[offset + 7 * stride] = 2;
		assert(ufs_mobile_enabled_luns(&d, &mask) == -EINVAL); cases++;
		configuration_bytes[offset + 7 * stride] = 0;
		device_bytes[0x1a] = 255; assert(ufs_mobile_enabled_luns(&d, &mask) == -EINVAL); cases++;
		device_bytes[0x1a] = offset;
		device_bytes[0x1b] = 0; assert(ufs_mobile_enabled_luns(&d, &mask) == -EINVAL); cases++;
		device_bytes[0x1b] = stride;
		config_length--; assert(ufs_mobile_enabled_luns(&d, &mask) == -EINVAL); cases++;
		config_length++;
		device_bytes[0] = 0x10; assert(ufs_mobile_enabled_luns(&d, &mask) == -EINVAL); cases++;
		device_bytes[0] = 0x40;
		desc_error = -EIO; assert(ufs_mobile_enabled_luns(&d, &mask) == -EIO); cases++;
		desc_error = 0;
	}
	assert(ufs_mobile_boot_lun_set(&d, 0) == -EINVAL && !attr_writes); cases++;
	assert(ufs_mobile_boot_lun_set(&d, 3) == -EINVAL && !attr_writes); cases++;
	assert(!ufs_mobile_boot_lun_set(&d, 1) && !ufs_mobile_boot_lun_get(&d, &v) && v == 1); cases++;
	attr_error = -EIO; assert(ufs_mobile_boot_lun_set(&d, 2) == -EIO); cases++;
	d.active = false; assert(ufs_mobile_boot_lun_set(&d, 1) == -EINVAL); cases++;
	assert(ufs_mobile_boot_lun_get(&d, NULL) == -EINVAL); cases++;
	printf("PASS %u actual UFS descriptor/boot-LUN API cases\n", cases);
	return 0;
}
