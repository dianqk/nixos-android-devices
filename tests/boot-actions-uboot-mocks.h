/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef BOOT_ACTIONS_UBOOT_MOCKS_H
#define BOOT_ACTIONS_UBOOT_MOCKS_H
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#define EIO 5
#define EACCES 13
#define ENODEV 19
#define EINVAL 22
#define ENOTSUPP 524
typedef uint32_t u32;
typedef int32_t s32;
typedef unsigned long efi_status_t;
typedef void *efi_handle_t;
typedef struct {
	unsigned char b[16];
} efi_guid_t;
/* Byte-array GUID layout from fixed U-Boot include/efi.h. Real ARM64
 * object/helper bytes are checked separately from these interface mocks. */
#define EFI_GUID(a, b, c, d0, d1, d2, d3, d4, d5, d6, d7)                                          \
	{                                                                                          \
		{                                                                                  \
			a & 255, (a >> 8) & 255, (a >> 16) & 255, (a >> 24) & 255, b & 255,        \
			    (b >> 8) & 255, c & 255, (c >> 8) & 255, d0, d1, d2, d3, d4, d5, d6,   \
			    d7                                                                     \
		}                                                                                  \
	}
#define EFIAPI
#define EFI_SUCCESS 0
#define EFI_UNSUPPORTED (0x8000000000000000UL | 3)
#define EFI_INVALID_PARAMETER (0x8000000000000000UL | 2)
#define EFI_DEVICE_ERROR (0x8000000000000000UL | 7)
#define EFI_ENTRY(...)                                                                             \
	do {                                                                                       \
	} while (0)
static inline efi_status_t mock_efi_exit(efi_status_t status) { return status; }
#define EFI_EXIT(status) mock_efi_exit(status)
#define EVT_NOTIFY_SIGNAL 0x200
#define TPL_CALLBACK 8
#define UCLASS_PMIC 1
#define UCLASS_FIRMWARE 2
#define PSCI_0_2_FN_PSCI_VERSION 0x84000000
#define PSCI_0_2_FN_SYSTEM_RESET 0x84000009
#define PSCI_1_0_FN_PSCI_FEATURES 0x8400000a
#define PSCI_VERSION_MAJOR(v) (((v) >> 16) & 0xffff)
#define PSCI_VERSION_MINOR(v) ((v) & 0xffff)
struct mock_node {
	bool enabled;
	const char *compatible;
	u32 base, recovery, bootloader;
	struct mock_node *next;
};
typedef struct mock_node *ofnode;
struct udevice {
	const char *compatible;
	ofnode first;
	struct udevice *next;
};
struct uclass {
	struct udevice *first;
};
struct efi_event {
	int unused;
};
#define uclass_foreach_dev(dev, class) for (dev = (class)->first; dev; dev = dev->next)
#define dev_for_each_subnode(node, dev) for (node = dev->first; node; node = node->next)
static efi_handle_t efi_root;
static const efi_guid_t efi_guid_event_group_exit_boot_services;
static int uclass_get(int id, struct uclass **out);
static int device_is_compatible(struct udevice *dev, const char *compatible);
static int ofnode_is_enabled(ofnode node);
static int ofnode_device_is_compatible(ofnode node, const char *compatible);
static int ofnode_read_u32(ofnode node, const char *name, u32 *out);
static int device_probe(struct udevice *dev);
static int uclass_get_device_by_name(int id, const char *name, struct udevice **out);
static unsigned long invoke_psci_fn(unsigned long id, unsigned long a, unsigned long b,
				    unsigned long c);
static int pmic_read(struct udevice *dev, unsigned int reg, unsigned char *value, int length);
static int pmic_write(struct udevice *dev, unsigned int reg, const unsigned char *value,
		      int length);
static int disable_interrupts(void);
static void enable_interrupts(void);
static efi_status_t efi_create_event(uint32_t type, unsigned long tpl,
				     void (*callback)(struct efi_event *, void *), void *context,
				     const efi_guid_t *group, struct efi_event **event);
static efi_status_t efi_add_protocol(efi_handle_t handle, const efi_guid_t *guid, void *protocol);
static efi_status_t efi_close_event(struct efi_event *event);
#endif
