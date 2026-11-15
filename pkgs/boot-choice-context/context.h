/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef MOBILE_BOOT_CHOICE_CONTEXT_H
#define MOBILE_BOOT_CHOICE_CONTEXT_H
#include <efi_loader.h>
#include <commit-intent.h>
#include <boot-choice-context-wire.h>
/* Boot-services data, not authenticated write authority or an NVRAM variable. */
#define BOOT_CHOICE_GUID_EXPAND(...) EFI_GUID(__VA_ARGS__)
#define MOBILE_BOOT_CHOICE_CONTEXT_GUID BOOT_CHOICE_GUID_EXPAND(BOOT_CHOICE_CONTEXT_GUID_ARGS)
#define MOBILE_BOOT_CHOICE_CONTEXT_ABI 1
struct mobile_boot_choice_context {
 u32 version;
 u32 size;
 u32 capabilities; /* bit 0: strict slot-bound wire decoder */
 u32 reserved;
 u8 token[EG_INTENT_BYTES];
};
int mobile_boot_choice_copy(const void *source, void *dest, size_t capacity);
efi_status_t efi_boot_choice_context_register(void);
extern const volatile u32 android_devices_boot_choice_context_abi_v1;
#endif
