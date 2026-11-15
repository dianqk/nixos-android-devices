/* SPDX-License-Identifier: GPL-2.0-only */
#include <efi_loader.h>
#include <asm/global_data.h>
#include <linux/libfdt.h>
#include <boot-choice-context.h>
DECLARE_GLOBAL_DATA_PTR;
const volatile u32 android_devices_boot_choice_context_abi_v1 = 1;

/* Full traversal: fdt_getprop alone would silently accept duplicate properties.
 * Source identity and memory ownership are validated by the board first. */
static const u8 *checked_token(const void *source, size_t bound)
{
 int node = -1, depth = -1, chosen = -1, count = 0, poff, len;
 const u8 *token = NULL;
 struct eg_choice_observation observed;
 unsigned selected;
 if (!source || fdt_check_full(source, bound))
  return NULL;
 while ((node = fdt_next_node(source, node, &depth)) >= 0) {
  const char *name;
  if (depth < 0) { node = -FDT_ERR_NOTFOUND; break; }
  name = fdt_get_name(source, node, NULL);
  if (!name)
   return NULL;
  if (depth == 1 && !strcmp(name, "chosen")) {
   if (chosen >= 0)
    return NULL;
   chosen = node;
  }
 }
 if (node != -FDT_ERR_NOTFOUND || chosen < 0)
  return NULL;
 fdt_for_each_property_offset(poff, source, chosen) {
  const char *name;
  const void *value = fdt_getprop_by_offset(source, poff, &name, &len);
  if (!value)
   return NULL;
  if (!strcmp(name, EG_INTENT_PROPERTY)) {
   if (++count != 1 || len != EG_INTENT_BYTES)
    return NULL;
   token = value;
  }
 }
 if (poff != -FDT_ERR_NOTFOUND || count != 1 || !token ||
     !eg_intent_decode(token, token + 16, &observed, &selected) ||
     (token[68] != 1 && token[68] != 2) || token[72] != 1)
  return NULL;
 return token;
}
int mobile_boot_choice_copy(const void *source, void *dest, size_t capacity)
{
 const u8 *token = checked_token(source, 1536 * 1024);
 int chosen;
 if (!token || capacity != 64 * 1024 ||
     fdt_check_full(dest, capacity) || fdt_totalsize(dest) > capacity)
  return -1;
 chosen = fdt_path_offset(dest, "/chosen");
 if (chosen < 0 || fdt_getprop(dest, chosen, EG_INTENT_PROPERTY, NULL))
  return -1;
 return fdt_setprop(dest, chosen, EG_INTENT_PROPERTY, token, EG_INTENT_BYTES);
}
efi_status_t efi_boot_choice_context_register(void)
{
 static const efi_guid_t guid = MOBILE_BOOT_CHOICE_CONTEXT_GUID;
 struct mobile_boot_choice_context *record;
 const u8 *token = checked_token(gd->fdt_blob, 64 * 1024);
 efi_status_t ret;
 if (!token)
  return EFI_INVALID_PARAMETER;
 ret = efi_allocate_pool(EFI_BOOT_SERVICES_DATA, sizeof(*record), (void **)&record);
 if (ret != EFI_SUCCESS)
  return ret;
 memset(record, 0, sizeof(*record));
 record->version = android_devices_boot_choice_context_abi_v1;
 record->size = sizeof(*record);
 record->capabilities = 1;
 memcpy(record->token, token, EG_INTENT_BYTES);
 ret = efi_install_configuration_table(&guid, record);
 if (ret != EFI_SUCCESS)
  efi_free_pool(record);
 return ret;
}
