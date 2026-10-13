/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Actual GPT/UFS adapter and patched EFI loader; all I/O is in memory. */
#define MOBILE_CONFIRM_TEST
static unsigned int confirmation_non_gpt_mask;
#define CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK confirmation_non_gpt_mask
#include "boot-actions-ab-adapter.c"
#undef main
typedef unsigned short u16;
typedef unsigned long efi_uintn_t;
typedef EFI_STATUS efi_status_t;
typedef void *efi_handle_t;
struct efi_device_path { unsigned char type, sub_type; unsigned short length; };
struct efi_device_path_file_path { struct efi_device_path dp; u16 str[]; };
#define DEVICE_PATH_TYPE_MEDIA_DEVICE 4
#define DEVICE_PATH_SUB_TYPE_FILE_PATH 4
#define DEVICE_PATH_TYPE_END 127
#define DEVICE_PATH_SUB_TYPE_END 255
#define CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH "/EFI/BOOT/BOOTAA64.EFI"
static const char *charger_confirmation_path = "/EFI/android-devices/charger.efi";
#define CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_CHARGER_PATH charger_confirmation_path
#define CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP "linux-boot"
#define CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM 1
#define IS_ENABLED(x) (x)
#define EFI_CALL(x) (x)
static unsigned int logged_errors, starts;
static void mock_log(const char *format, ...) {}
#define log_err(...) (logged_errors++, mock_log(__VA_ARGS__))
#define log_info(...) mock_log(__VA_ARGS__)
struct source_path { struct efi_device_path dp; unsigned int disk, part; struct efi_device_path end; };
struct image_path { struct efi_device_path dp; u16 str[23]; struct efi_device_path end; };
static struct source_path source;
static struct image_path image;
#include "mobile-efi-dp-size.c"
static struct efi_device_path *efi_dp_from_part(struct blk_desc *d, int part)
{
	struct source_path *p = calloc(1, sizeof(*p));
	assert(p);
	p->dp = (struct efi_device_path){1, 1, sizeof(*p) - sizeof(p->end)};
	p->disk = d->devnum; p->part = part;
	p->end = (struct efi_device_path){127, 255, 4};
	return &p->dp;
}
static void efi_free_pool(void *p) { free(p); }
#include "../pkgs/mobile-boot-action/qcom-ab-confirm.h"
static efi_status_t load_result, options_result, entry_result;
static void *efi_root;
static struct efi_device_path *efi_dp_concat(struct efi_device_path *a, struct efi_device_path *b, int n)
{
	return a;
}
static efi_status_t efi_load_image(bool policy, void *parent, struct efi_device_path *path,
				 void *buffer, efi_uintn_t size, efi_handle_t *handle)
{
	*handle = &source; return load_result;
}
static efi_status_t efi_env_set_load_options(efi_handle_t handle, const char *name, u16 **out)
{
	*out = NULL; return options_result;
}
static efi_status_t do_bootefi_exec(efi_handle_t handle, u16 *options)
{
	starts++; return entry_result;
}
#include "mobile-efi-run-image.c"
static void sync_tables(void)
{
	for (unsigned int i = 0; i < 2; i++) {
		memcpy(media[i] + (BLOCKS - 2) * AB_BLOCK, media[i] + 2 * AB_BLOCK, 12 * 128);
		headers(i);
	}
}
static void prepare_confirmation(void)
{
	static const unsigned char esp[16] = {0x28,0x73,0x2a,0xc1,0x1f,0xf8,0xd2,0x11,0xba,0x4b,0,0xa0,0xc9,0x3e,0xc9,0x3b};
	const char *path = CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH;
	prepare_adapter(); ab_confirmation_disabled = false;
	/* Last ABL attempt, unbootable Android A and pending BCB are allowed. */
	ab_put(media[0] + 2 * AB_BLOCK + 128 + 48, AB_ACTIVE | AB_PRIORITY, 8);
	ab_put(media[0] + 2 * AB_BLOCK + 48, AB_UNBOOTABLE, 8);
	media[0][18 * AB_BLOCK] = 'x';
	memcpy(media[0] + 2 * AB_BLOCK + 5 * 128, esp, 16);
	sync_tables(); memcpy(original, media, sizeof(media));
	struct efi_device_path *p = efi_dp_from_part(&desc[0], 6);
	memcpy(&source, p, sizeof(source)); efi_free_pool(p);
	memset(&image, 0, sizeof(image));
	assert(strlen(path) + 1 == sizeof(image.str) / sizeof(image.str[0]));
	image.dp = (struct efi_device_path){4, 4, sizeof(image) - sizeof(image.end)};
	for (unsigned int i = 0; i < strlen(path); i++) image.str[i] = path[i];
	image.end = (struct efi_device_path){127, 255, 4};
	logged_errors = starts = 0; load_result = options_result = entry_result = EFI_SUCCESS;
}
static void boot(void)
{
	assert(efi_run_image(NULL, 0, &source.dp, &image.dp) == entry_result);
	assert(starts == 1);
	assert(!lun_writes && !reason_reads && !reason_writes && !resets);
}
static void assert_unchanged(void) { assert(!writes && !memcmp(media, original, sizeof(media))); }
static void prepare_non_gpt(const unsigned int order[4])
{
	prepare_confirmation();
	confirmation_non_gpt_mask = (1U << 6) | (1U << 7);
	enabled_mask |= confirmation_non_gpt_mask;
	for (unsigned int i = 6; i < 8; i++) {
		memset(media[i], 0, sizeof(media[i]));
		memset(original[i], 0, sizeof(original[i]));
		desc[i] = (struct blk_desc){.uclass_id = UCLASS_SCSI, .devnum = i,
			.lun = i, .blksz = AB_BLOCK, .lba = BLOCKS};
		blocks[i] = (struct udevice){.parent = &scsi, .desc = &desc[i]};
	}
	for (unsigned int i = 0; i < 4; i++)
		blocks[order[i]].next = i == 3 ? NULL : &blocks[order[i + 1]];
	block_class.first = &blocks[order[0]];
}
static void candidate_gpt(unsigned int lun, const char *name)
{
	entry(lun, 0, name, 99);
	memcpy(media[lun] + (BLOCKS - 2) * AB_BLOCK,
	       media[lun] + 2 * AB_BLOCK, 12 * 128);
	headers(lun);
	media[lun][510] = 0x55; media[lun][511] = 0xaa;
	memcpy(original, media, sizeof(media));
}
static unsigned int non_gpt_tests(void)
{
	unsigned int count = 0, normal_reads, normal_writes;
	static unsigned char expected[sizeof(media)];
	const unsigned int orders[][4] = {{0, 1, 6, 7}, {6, 0, 7, 1}, {7, 6, 1, 0}};
	/* The mask permits an exception; it never removes support for valid GPTs. */
	for (unsigned int lun = 6; lun < 8; lun++) {
		prepare_non_gpt(orders[1]); candidate_gpt(lun, "metadata");
		struct ab_state state;
		assert(!ab_open(&state, AB_CONFIRM) && state.disks == 3);
		ab_free(&state); boot(); assert(writes == 4 && !logged_errors);
		assert(!memcmp(media[lun], original[lun], sizeof(media[lun]))); count++;
		for (unsigned int fault = 0; fault < 5; fault++) {
			prepare_non_gpt(orders[1]);
			candidate_gpt(lun, fault == 3 ? "boot_b" : fault == 4 ? "linux-boot" : "metadata");
			if (fault < 2)
				media[lun][(fault ? BLOCKS - 1 : 1) * AB_BLOCK + 16] ^= 1;
			else if (fault == 2) {
				media[lun][(BLOCKS - 2) * AB_BLOCK + 56] ^= 1;
				headers(lun); /* Two valid CRCs, conflicting arrays. */
			}
			memcpy(original, media, sizeof(media)); boot();
			assert(logged_errors); assert_unchanged(); count++;
		}
	}
	prepare_confirmation(); confirmation_non_gpt_mask = 192;
	boot(); assert(writes == 4 && !logged_errors); count++; /* Candidates disabled. */
	for (unsigned int o = 0; o < sizeof(orders) / sizeof(orders[0]); o++) {
		prepare_non_gpt(orders[o]); boot();
		assert(writes == 4 && !logged_errors);
		memcpy(expected, media, sizeof(media));
		memcpy(media, original, sizeof(media));
		media[0][2 * AB_BLOCK + 128 + 54] |= 0x40;
		sync_tables(); assert(!memcmp(media, expected, sizeof(media)));
		assert(ab_get(media[0] + 2 * AB_BLOCK + 128 + 48, 8) & AB_SUCCESS);
		for (unsigned int i = 1; i < AB_MAX_LUNS; i++)
			assert(!memcmp(media[i], original[i], sizeof(media[i])));
		writes = starts = 0; boot(); assert(!writes); count += 2;
	}
	prepare_non_gpt(orders[1]); boot();
	normal_reads = reads; normal_writes = writes;
	for (unsigned int i = 1; i <= normal_writes; i++) {
		prepare_non_gpt(orders[1]); fail_write = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
	}
	for (unsigned int i = 1; i <= normal_reads; i++) {
		prepare_non_gpt(orders[1]); fail_read = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
		prepare_non_gpt(orders[1]); mismatch_read = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
	}
	for (unsigned int mask = 0; mask < 3; mask++) {
		prepare_non_gpt(orders[0]);
		confirmation_non_gpt_mask = mask == 0 ? 0 : 1U << (mask == 1 ? 6 : 7);
		boot(); assert(logged_errors); assert_unchanged(); count++;
	}
	for (unsigned int purpose = AB_ANDROID; purpose <= AB_RECOVERY; purpose++) {
		struct ab_state state;
		prepare_non_gpt(orders[0]);
		assert(ab_open(&state, purpose) == -EINVAL);
		ab_free(&state); assert_unchanged(); count++;
	}
	/* Each purpose requires its own policy; neither option leaks into another. */
	{
		struct ab_state state;
		prepare_non_gpt(orders[0]);
		confirmation_non_gpt_mask = 0; android_non_gpt_mask = 192;
		assert(ab_open(&state, AB_CONFIRM) == -EINVAL); ab_free(&state);
		assert(ab_open(&state, AB_RECOVERY) == -EINVAL); ab_free(&state);
		assert_unchanged(); count += 2;
	}
	/* Every byte matters, not just the absent signature. Each read is mandatory. */
	for (unsigned int lun = 6; lun < 8; lun++) {
		unsigned int positions[] = {0, AB_BLOCK, (BLOCKS - 1) * AB_BLOCK};
		for (unsigned int block = 0; block < 3; block++) {
			prepare_non_gpt(orders[1]);
			media[lun][positions[block] + AB_BLOCK - 1] = 1;
			memcpy(original, media, sizeof(media)); boot();
			assert(logged_errors); assert_unchanged(); count++;
			/* Non-GPT LUNs are first so their read positions are deterministic. */
			prepare_non_gpt(orders[2]);
			fail_read = (lun == 7 ? 0 : 3) + block + 1;
			boot(); assert(logged_errors); assert_unchanged(); count++;
		}
	}
	for (unsigned int fault = 0; fault < 9; fault++) {
		prepare_non_gpt(orders[0]);
		switch (fault) {
		case 0: blocks[6].next = NULL; break; /* Enabled LUN7 missing. */
		case 1: desc[7].lun = 6; break;
		case 2: desc[6].blksz = 512; break;
		case 3: desc[6].lba = 0; break;
		case 4: desc[6].lba = 15; break;
		case 5: desc[6].lba = 0x100000000ULL; break;
		case 6: enabled_mask &= ~(1U << 6); break;
		case 7: desc[6].removable = 1; break;
		case 8: blocks[7].parent = NULL; break;
		}
		boot(); assert(logged_errors); assert_unchanged(); count++;
	}
	/* Valid GPT-bearing LUNs keep their CRC and consistency gates. */
	for (unsigned int fault = 0; fault < 2; fault++) {
		prepare_non_gpt(orders[0]);
		media[0][(fault ? BLOCKS - 1 : 1) * AB_BLOCK + 16] ^= 1;
		memcpy(original, media, sizeof(media)); boot();
		assert(logged_errors); assert_unchanged(); count++;
	}
	return count;
}
static unsigned int charger_tests(void)
{
	const char *valid = "/EFI/android-devices/charger.efi";
	unsigned int count = 0;
	for (unsigned int fault = 0; fault < 12; fault++) {
		uint64_t storage[32] = {0};
		struct efi_device_path_file_path *file = (void *)storage;
		const char *path = fault == 2 ? "/EFI/android-devices/charger.efi.bak" : valid;
		unsigned int length = strlen(path);
		struct efi_device_path *end = (void *)((unsigned char *)storage + 4 + 2 * (length + 1));
		prepare_confirmation();
		charger_confirmation_path = fault == 3 ? "" : valid;
		file->dp = (struct efi_device_path){4, 4, 4 + 2 * (length + 1)};
		for (unsigned int i = 0; i < length; i++) file->str[i] = path[i];
		*end = (struct efi_device_path){127, 255, 4};
		switch (fault) {
		case 1: file->str[0] = '\\'; file->str[1] = 'e'; break;
		case 4: file->str[length] = 'x'; break;
		case 5: end->type = 4; break;
		case 6: file->dp.length--; break;
		case 7: source.disk = 1; break;
		case 8: source.part = 5; break;
		case 9: boot_lun = 1; break;
		case 10: load_result = EFI_LOAD_ERROR; break;
		case 11: options_result = EFI_OUT_OF_RESOURCES; break;
		}
		efi_run_image(NULL, 0, &source.dp, &file->dp);
		if (fault < 2) assert(writes == 4 && starts == 1 && !logged_errors);
		else assert_unchanged();
		assert(!lun_writes && !reason_reads && !reason_writes && !resets);
		count++;
	}
	charger_confirmation_path = valid;
	return count;
}
int main(void)
{
	unsigned int count = charger_tests(), normal_reads, normal_writes;
	static unsigned char expected[sizeof(media)];
	prepare_confirmation(); boot();
	normal_reads = reads; normal_writes = writes;
	assert(normal_writes == 4 && !logged_errors);
	memcpy(expected, media, sizeof(media));
	/* Independently construct the expected whole-media diff. */
	memcpy(media, original, sizeof(media));
	media[0][2 * AB_BLOCK + 128 + 54] |= 0x40;
	sync_tables(); assert(!memcmp(media, expected, sizeof(media))); count++;
	/* Repeated successful boots perform no writes, including headers. */
	writes = starts = 0; boot(); assert(!writes); count++;
	for (unsigned int i = 1; i <= normal_writes; i++) {
		prepare_confirmation(); fail_write = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
	}
	for (unsigned int i = 1; i <= normal_reads; i++) {
		prepare_confirmation(); fail_read = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
		prepare_confirmation(); mismatch_read = i; boot();
		assert(logged_errors && active && !memcmp(media, original, sizeof(media))); count++;
	}
	/* Loader/setup failures never reach the confirmation hook or StartImage. */
	prepare_confirmation(); load_result = EFI_LOAD_ERROR;
	assert(efi_run_image(NULL, 0, &source.dp, &image.dp) == EFI_LOAD_ERROR);
	assert(!starts && !reads); assert_unchanged(); count++;
	prepare_confirmation(); options_result = EFI_OUT_OF_RESOURCES;
	assert(efi_run_image(NULL, 0, &source.dp, &image.dp) == EFI_OUT_OF_RESOURCES);
	assert(!starts && !reads); assert_unchanged(); count++;
	/* EFI execution failure does not change the earlier load-success contract. */
	prepare_confirmation(); entry_result = EFI_LOAD_ERROR; boot(); assert(writes == 4); count++;
	/* FAT case/slash equivalence; wrong path, malformed/extra nodes refuse. */
	prepare_confirmation(); image.str[0] = '\\'; image.str[1] = 'e'; boot(); assert(writes == 4); count++;
	for (unsigned int i = 0; i < 7; i++) {
		prepare_confirmation();
		switch (i) {
		case 0: image.str[1] = 'X'; break;
		case 1: image.str[22] = 'x'; break;
		case 2: image.dp.length--; break;
		case 3: image.dp.sub_type = 3; break;
		case 4: image.end.type = 4; break;
		case 5: image.end.sub_type = 1; break;
		case 6: image.end.length = 8; break;
		}
		boot(); assert(!reads); assert_unchanged(); count++;
	}
	for (unsigned int i = 0; i < 12; i++) {
		prepare_confirmation();
		switch (i) {
		case 0: source.disk = 1; break;
		case 1: source.part = 5; break;
		case 2: source.dp.sub_type = 2; break;
		case 3: boot_lun = 1; break;
		case 4: enabled_mask = 7; break;
		case 5: media[0][AB_BLOCK + 16] ^= 1; break;
		case 6: media[1][(BLOCKS - 1) * AB_BLOCK + 16] ^= 1; break;
		case 7: media[0][2 * AB_BLOCK + 5 * 128] ^= 1; sync_tables(); break;
		case 8: entry(1, 4, "linux-boot", 15); sync_tables(); break;
		case 9: ab_put(media[0] + 2 * AB_BLOCK + 128 + 48, AB_UNBOOTABLE | AB_ACTIVE | AB_PRIORITY, 8); sync_tables(); break;
		case 10: ab_put(media[0] + 2 * AB_BLOCK + 128 + 48, AB_PRIORITY, 8); sync_tables(); break;
		case 11: ab_put(media[0] + 2 * AB_BLOCK + 128 + 48, AB_ACTIVE, 8); sync_tables(); break;
		}
		memcpy(original, media, sizeof(media)); boot(); assert_unchanged(); count++;
	}
	/* Confirmation does not require either misc or the recovery pair. */
	prepare_confirmation();
	memset(media[0] + 2 * AB_BLOCK + 2 * 128, 0, 3 * 128); sync_tables();
	boot(); assert(writes == 4); count++;
	/* Permanent failure during restoration disables every later mutation. */
	prepare_confirmation(); fail_write = 1; fail_block_restoration = 1;
	boot(); assert(!active && ab_confirmation_disabled && logged_errors >= 2);
	int saved_writes = writes; starts = 0; boot(); assert(writes == saved_writes); count++;
	printf("PASS: %u EFI-load confirmation and fault cases\n", count);
	printf("PASS: %u explicit non-GPT confirmation cases\n", non_gpt_tests());
	return 0;
}
