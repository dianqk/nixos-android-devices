/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included by the shared firmware adapter after the Qualcomm storage backend. */
#ifndef MOBILE_QCOM_AB_CONFIRM_H
#define MOBILE_QCOM_AB_CONFIRM_H
#include <efi_device_path.h>
#include <efi_loader.h>

static bool ab_confirmation_disabled;

static unsigned int ab_path_char(unsigned int c)
{
	if (c == '\\')
		return '/';
	return c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c;
}

static bool ab_confirmation_path_matches(struct efi_device_path *path, const char *wanted)
{
	struct efi_device_path_file_path *file = (void *)path;
	struct efi_device_path *end;
	unsigned int i, length = strlen(wanted);
	if (!length || !path || path->type != DEVICE_PATH_TYPE_MEDIA_DEVICE ||
	    path->sub_type != DEVICE_PATH_SUB_TYPE_FILE_PATH ||
	    path->length != sizeof(*path) + 2 * (length + 1))
		return false;
	for (i = 0; i < length; i++)
		if (ab_path_char(file->str[i]) != ab_path_char((unsigned char)wanted[i]))
			return false;
	if (file->str[length])
		return false;
	/* efi_dp_next() intentionally hides END nodes by returning NULL. */
	end = (void *)((unsigned char *)path + path->length);
	return end->type == DEVICE_PATH_TYPE_END &&
	       end->sub_type == DEVICE_PATH_SUB_TYPE_END && end->length == sizeof(*end);
}

static bool ab_confirmation_path(struct efi_device_path *path)
{
	return ab_confirmation_path_matches(path, CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH) ||
	       ab_confirmation_path_matches(path, CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_CHARGER_PATH);
}

static int ab_confirmation_source(struct ab_state *s, struct efi_device_path *source)
{
	static const unsigned char esp_type[16] = {
		0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11,
		0xba, 0x4b, 0x00, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b
	};
	unsigned char *esp = ab_find(s, CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP);
	unsigned int i, j;
	if (!esp || memcmp(esp, esp_type, sizeof(esp_type)))
		return -EINVAL;
	for (i = 0; i < s->disks; i++)
		for (j = 0; j < s->disk[i].count; j++) {
			struct efi_device_path *expected;
			bool match;
			if (s->disk[i].entries[0] + j * 128 != esp)
				continue;
			expected = efi_dp_from_part(s->disk[i].context, j + 1);
			if (!expected)
				return -ENOMEM;
			match = efi_dp_size(source) == efi_dp_size(expected) &&
				!memcmp(source, expected, efi_dp_size(expected) + sizeof(*expected));
			efi_free_pool(expected);
			return match;
		}
	return -EINVAL;
}

/* No PON, BCB, GUID exchange or boot-LUN writes in this transaction. */
static int ab_confirm_loaded(struct efi_device_path *source)
{
	struct ab_state state;
	int ret, restore;
	if (!active || ab_confirmation_disabled || !source)
		return 0;
	ret = ab_open(&state, AB_CONFIRM);
	if (ret)
		goto done;
	ret = ab_confirmation_source(&state, source);
	if (ret <= 0)
		goto done;
	if (ab_get(ab_find(&state, "boot_b") + 48, 8) & AB_SUCCESS) {
		ret = 0;
		goto done;
	}
	ab_plan_confirm(&state);
	ret = ab_store(&state, 0);
	if (ret) {
		restore = ab_store(&state, 1);
		if (restore) {
			ab_confirmation_disabled = true;
			active = false;
			log_err("Slot B confirmation restore failed: %d; boot actions disabled\n", restore);
		}
	} else {
		log_info("Slot B marked successful after EFI image load\n");
	}
done:
	ab_free(&state);
	return ret;
}

void efi_mobile_qcom_ab_confirm(struct efi_device_path *source,
			      struct efi_device_path *image)
{
	int ret;
	if (!ab_confirmation_path(image))
		return;
	ret = ab_confirm_loaded(source);
	if (ret)
		log_err("Slot B confirmation failed: %d; continuing EFI boot\n", ret);
}
#endif
