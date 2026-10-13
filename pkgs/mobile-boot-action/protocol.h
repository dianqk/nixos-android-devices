/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef MOBILE_BOOT_ACTION_PROTOCOL_H
#define MOBILE_BOOT_ACTION_PROTOCOL_H

#ifdef MOBILE_BOOT_ACTION_FIRMWARE
#include <efi_loader.h>
typedef efi_status_t mobile_status_t;
typedef u32 mobile_u32;
typedef s32 mobile_s32;
#define MOBILE_BOOT_ACTION_GUID                                                                    \
	EFI_GUID(0x9d99a5aa, 0x7b04, 0x4d4f, 0xa8, 0x4c, 0x70, 0xe8, 0xf2, 0x35, 0x81, 0x30)
#else
#include <efi.h>
typedef EFI_STATUS mobile_status_t;
typedef UINT32 mobile_u32;
typedef INT32 mobile_s32;
#define MOBILE_BOOT_ACTION_GUID                                                                    \
	{0x9d99a5aa, 0x7b04, 0x4d4f, {0xa8, 0x4c, 0x70, 0xe8, 0xf2, 0x35, 0x81, 0x30}}
#endif
#define MOBILE_BOOT_ACTION_REVISION 1
#define MOBILE_ACTION_BOOTLOADER 1
#define MOBILE_ACTION_RECOVERY 2
#define MOBILE_ACTION_ANDROID 4
#define MOBILE_ACTION_RECOVERY_B 8
#define MOBILE_ACTION_MASK 3
#define MOBILE_ACTION_AB_MASK (MOBILE_ACTION_BOOTLOADER | MOBILE_ACTION_ANDROID | MOBILE_ACTION_RECOVERY_B)

enum mobile_action_stage {
	MOBILE_STAGE_NONE,
	MOBILE_STAGE_PROBE,
	MOBILE_STAGE_READ,
	MOBILE_STAGE_WRITE,
	MOBILE_STAGE_VERIFY,
	MOBILE_STAGE_RESET,
	MOBILE_STAGE_STORAGE,
	MOBILE_STAGE_SLOT
};

/* A reset never returns on success. Errors retain the original operation and
 * separately report whether restoring the original byte succeeded. */
struct mobile_action_result {
	mobile_u32 size;
	mobile_u32 stage;
	mobile_s32 operation_status;
	mobile_u32 restore_attempted;
	mobile_s32 restore_status;
};

struct mobile_boot_action_protocol {
	mobile_u32 revision;
	mobile_u32 size;
	mobile_status_t(EFIAPI *get_capabilities)(struct mobile_boot_action_protocol *self,
						  mobile_u32 *mask);
	mobile_status_t(EFIAPI *execute)(struct mobile_boot_action_protocol *self,
					 mobile_u32 action, struct mobile_action_result *result);
};
#endif
