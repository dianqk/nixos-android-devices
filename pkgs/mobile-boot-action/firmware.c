// SPDX-License-Identifier: GPL-2.0-or-later
/* EFI boot-services adapter for explicitly selected Qualcomm reboot backends. */
#include <asm/system.h>
#include <dm.h>
#include <dm/device-internal.h>
#include <irq_func.h>
#include <linux/errno.h>
#include <linux/psci.h>
#include <power/pmic.h>
#define MOBILE_BOOT_ACTION_FIRMWARE
#include <mobile_boot_action.h>
#include "mobile_pon_transaction.h"

static bool active = true;
static struct udevice *pon_pmic;
static const efi_guid_t protocol_guid = MOBILE_BOOT_ACTION_GUID;
static struct mobile_boot_action_protocol protocol;

#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
static int check_reason_backend(void)
{
	struct uclass *pmics;
	struct udevice *dev;
	ofnode mode, cell, provider, pmic_node;
	u32 value, pair[2];
	int ret, matches = 0;
	pon_pmic = NULL;
	mode = ofnode_path("/reboot-mode");
	if (!ofnode_valid(mode) || !ofnode_is_enabled(mode) ||
	    !ofnode_device_is_compatible(mode, "nvmem-reboot-mode") ||
	    ofnode_read_u32(mode, "mode-recovery", &value) || value != 1 ||
	    ofnode_read_u32(mode, "mode-bootloader", &value) || value != 2)
		return -EINVAL;
	cell = ofnode_parse_phandle(mode, "nvmem-cells", 0);
	if (!ofnode_valid(cell) || ofnode_valid(ofnode_parse_phandle(mode, "nvmem-cells", 1)) ||
	    !ofnode_is_enabled(cell) || ofnode_read_u32_array(cell, "reg", pair, 2) ||
	    pair[0] != 0x48 || pair[1] != 1 ||
	    ofnode_read_u32_array(cell, "bits", pair, 2) || pair[0] != 1 || pair[1] != 7)
		return -EINVAL;
	provider = ofnode_get_parent(cell);
	pmic_node = ofnode_get_parent(provider);
	if (!ofnode_is_enabled(provider) || !ofnode_is_enabled(pmic_node) ||
	    !ofnode_device_is_compatible(provider, "qcom,spmi-sdam") ||
	    ofnode_read_u32(provider, "reg", &value) || value != 0x7100 ||
	    !ofnode_device_is_compatible(pmic_node, "qcom,spmi-pmic"))
		return -EINVAL;
	ret = uclass_get(UCLASS_PMIC, &pmics);
	if (ret)
		return ret;
	uclass_foreach_dev(dev, pmics) {
		if (ofnode_equal(dev_ofnode(dev), pmic_node)) {
			pon_pmic = dev;
			matches++;
		}
	}
	return matches == 1 ? device_probe(pon_pmic) : -ENODEV;
}
#endif

static int check_backend(void)
{
	struct udevice *psci;
	u32 version;
	int ret;
#ifndef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	struct udevice *dev;
	struct uclass *pmics;
	ofnode node;
	u32 base, recovery, bootloader;
	int matches = 0;
#endif

#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	ret = check_reason_backend();
	if (ret)
		return ret;
#else
	pon_pmic = NULL;
	ret = uclass_get(UCLASS_PMIC, &pmics);
	if (ret)
		return ret;
	/* Locate hardware by compatible, not by a board name or a hardcoded SID. */
	uclass_foreach_dev(dev, pmics)
	{
		if (!device_is_compatible(dev, "qcom,spmi-pmic"))
			continue;
		dev_for_each_subnode(node, dev)
		{
			if (!ofnode_is_enabled(node) ||
			    !ofnode_device_is_compatible(node, "qcom,pm8998-pon"))
				continue;
			if (ofnode_read_u32(node, "reg", &base) || base != 0x800 ||
			    ofnode_read_u32(node, "mode-recovery", &recovery) || recovery != 1 ||
			    ofnode_read_u32(node, "mode-bootloader", &bootloader) ||
			    bootloader != 2)
				return -EINVAL;
			pon_pmic = dev;
			matches++;
		}
	}
	if (matches != 1)
		return -ENODEV;
	ret = device_probe(pon_pmic);
	if (ret)
		return ret;
#endif
	ret = uclass_get_device_by_name(UCLASS_FIRMWARE, "psci", &psci);
	if (ret)
		return ret;
	if (!device_is_compatible(psci, "arm,psci-0.2") &&
	    !device_is_compatible(psci, "arm,psci-1.0"))
		return -ENOTSUPP;
	version = invoke_psci_fn(PSCI_0_2_FN_PSCI_VERSION, 0, 0, 0);
	if ((s32)version < 0 || (!PSCI_VERSION_MAJOR(version) && PSCI_VERSION_MINOR(version) < 2))
		return -ENOTSUPP;
	if (PSCI_VERSION_MAJOR(version) >= 1 &&
	    (s32)invoke_psci_fn(PSCI_1_0_FN_PSCI_FEATURES, PSCI_0_2_FN_SYSTEM_RESET, 0, 0) < 0)
		return -ENOTSUPP;
	return 0;
}

static int pon_read(void *context, unsigned char *value)
{
	#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	return pmic_read(context, 0x7148, value, 1);
#else
	return pmic_read(context, 0x88f, value, 1);
#endif
}

static int pon_write(void *context, unsigned char value)
{
	#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	return pmic_write(context, 0x7148, &value, 1);
#else
	return pmic_write(context, 0x88f, &value, 1);
#endif
}

static int pon_reset(void *context)
{
	int enabled = disable_interrupts();
	s32 ret = invoke_psci_fn(PSCI_0_2_FN_SYSTEM_RESET, 0, 0, 0);

	if (enabled)
		enable_interrupts();
	return ret;
}

#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
#include "mobile_qcom_ab_firmware.h"
#ifdef CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM
#include "mobile_qcom_ab_confirm.h"
#endif
#endif

static efi_status_t EFIAPI get_capabilities(struct mobile_boot_action_protocol *self, u32 *mask)
{
	unsigned char value;
	efi_status_t status = EFI_UNSUPPORTED;

	EFI_ENTRY("%p, %p", self, mask);
	if (self != &protocol || !mask)
		return EFI_EXIT(EFI_INVALID_PARAMETER);
	*mask = 0;
	if (active && !check_backend() && !pon_read(pon_pmic, &value)) {
#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
		struct ab_state state;
		*mask = MOBILE_ACTION_BOOTLOADER;
		if (!ab_open(&state, AB_RECOVERY))
			*mask |= MOBILE_ACTION_RECOVERY_B;
		ab_free(&state);
		if (!ab_open(&state, AB_ANDROID))
			*mask |= MOBILE_ACTION_ANDROID;
		ab_free(&state);
#else
		*mask = MOBILE_ACTION_MASK;
#endif
		status = EFI_SUCCESS;
	}
	return EFI_EXIT(status);
}

static efi_status_t EFIAPI execute(struct mobile_boot_action_protocol *self, u32 action,
				   struct mobile_action_result *result)
{
	struct mobile_pon_ops ops = {pon_read, pon_write, pon_reset, NULL};
	int ret;

	EFI_ENTRY("%p, %u, %p", self, action, result);
	if (self != &protocol || !result || result->size != sizeof(*result) ||
	    (action != MOBILE_ACTION_BOOTLOADER &&
#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	     action != MOBILE_ACTION_ANDROID && action != MOBILE_ACTION_RECOVERY_B
#else
	     action != MOBILE_ACTION_RECOVERY
#endif
	    ))
		return EFI_EXIT(EFI_INVALID_PARAMETER);
	memset(result, 0, sizeof(*result));
	result->size = sizeof(*result);
	if (!active)
		return EFI_EXIT(EFI_UNSUPPORTED);
	result->stage = MOBILE_STAGE_PROBE;
	ret = check_backend();
	if (ret) {
		result->operation_status = ret;
		return EFI_EXIT(EFI_UNSUPPORTED);
	}
#ifdef CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB
	if (action == MOBILE_ACTION_ANDROID) {
		ab_execute_android(result);
		return EFI_EXIT(EFI_DEVICE_ERROR);
	}
	if (action == MOBILE_ACTION_RECOVERY_B) {
		struct ab_state state;
		result->stage = MOBILE_STAGE_STORAGE;
		ret = ab_open(&state, AB_RECOVERY);
		ab_free(&state);
		if (ret) {
			result->operation_status = ret;
			return EFI_EXIT(EFI_UNSUPPORTED);
		}
		action = MOBILE_ACTION_RECOVERY;
	}
#endif
	ops.context = pon_pmic;
	mobile_pon_execute(&ops, action, result);
	if (result->restore_attempted && result->restore_status)
		active = false;
	return EFI_EXIT(EFI_DEVICE_ERROR);
}

static struct mobile_boot_action_protocol protocol = {MOBILE_BOOT_ACTION_REVISION, sizeof(protocol),
						      get_capabilities, execute};

static void EFIAPI exit_boot_services(struct efi_event *event, void *context)
{
	EFI_ENTRY("%p, %p", event, context);
	active = false;
	EFI_EXIT(EFI_SUCCESS);
}

efi_status_t efi_mobile_boot_action_register(void)
{
	struct efi_event *event;
	efi_status_t ret;

	ret = efi_create_event(EVT_NOTIFY_SIGNAL, TPL_CALLBACK, exit_boot_services, NULL,
			       &efi_guid_event_group_exit_boot_services, &event);
	if (ret != EFI_SUCCESS)
		return ret;
	ret = efi_add_protocol(efi_root, &protocol_guid, &protocol);
	if (ret != EFI_SUCCESS)
		efi_close_event(event);
	return ret;
}
