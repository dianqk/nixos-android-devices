/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compile the actual EFI firmware adapter against DM/SPMI/PSCI mocks. */
#include <assert.h>
#include <stdio.h>
#include "../pkgs/mobile-boot-action/firmware.c"

static struct mock_node node, second_node;
static struct udevice pmic, second_pmic, psci;
static struct uclass pmics;
static int class_error, probe_error, psci_error, read_error;
static unsigned long version, features, reset_return;
static unsigned int reads, writes, resets, interrupt_restores, cases;
static unsigned char byte;
static efi_status_t event_status, add_status;
static unsigned int closes;
static struct efi_event mock_event;
static void (*exit_callback)(struct efi_event *, void *);

static int uclass_get(int id, struct uclass **out)
{
	assert(id == UCLASS_PMIC);
	*out = &pmics;
	return class_error;
}
static int device_is_compatible(struct udevice *dev, const char *compatible)
{
	return !strcmp(dev->compatible, compatible);
}
static int ofnode_is_enabled(ofnode n) { return n->enabled; }
static int ofnode_device_is_compatible(ofnode n, const char *compatible)
{
	return !strcmp(n->compatible, compatible);
}
static int ofnode_read_u32(ofnode n, const char *name, u32 *out)
{
	if (!strcmp(name, "reg"))
		*out = n->base;
	else if (!strcmp(name, "mode-recovery"))
		*out = n->recovery;
	else if (!strcmp(name, "mode-bootloader"))
		*out = n->bootloader;
	else
		return -EINVAL;
	return 0;
}
static int device_probe(struct udevice *dev)
{
	assert(dev == &pmic);
	return probe_error;
}
static int uclass_get_device_by_name(int id, const char *name, struct udevice **out)
{
	assert(id == UCLASS_FIRMWARE && !strcmp(name, "psci"));
	*out = &psci;
	return psci_error;
}
static unsigned long invoke_psci_fn(unsigned long id, unsigned long a, unsigned long b,
				    unsigned long c)
{
	if (id == PSCI_0_2_FN_PSCI_VERSION)
		return version;
	if (id == PSCI_1_0_FN_PSCI_FEATURES) {
		assert(a == PSCI_0_2_FN_SYSTEM_RESET);
		return features;
	}
	assert(id == PSCI_0_2_FN_SYSTEM_RESET);
	assert(writes == 1 && reads >= 2);
	resets++;
	return reset_return;
}
static int pmic_read(struct udevice *dev, unsigned int reg, unsigned char *value, int length)
{
	assert(dev == &pmic && reg == 0x88f && length == 1);
	reads++;
	*value = byte;
	return read_error;
}
static int pmic_write(struct udevice *dev, unsigned int reg, const unsigned char *value, int length)
{
	assert(dev == &pmic && reg == 0x88f && length == 1);
	writes++;
	byte = *value;
	return 0;
}
static int disable_interrupts(void) { return 1; }
static void enable_interrupts(void) { interrupt_restores++; }
static efi_status_t efi_create_event(uint32_t type, unsigned long tpl,
				     void (*callback)(struct efi_event *, void *), void *context,
				     const efi_guid_t *group, struct efi_event **event)
{
	assert(type == EVT_NOTIFY_SIGNAL && tpl == TPL_CALLBACK);
	exit_callback = callback;
	*event = &mock_event;
	return event_status;
}
static efi_status_t efi_add_protocol(efi_handle_t handle, const efi_guid_t *guid, void *value)
{
	const unsigned char expected[] = {0xaa, 0xa5, 0x99, 0x9d, 0x04, 0x7b, 0x4f, 0x4d,
					  0xa8, 0x4c, 0x70, 0xe8, 0xf2, 0x35, 0x81, 0x30};
	assert(handle == efi_root && value == &protocol && !memcmp(guid->b, expected, 16));
	return add_status;
}
static efi_status_t efi_close_event(struct efi_event *event)
{
	assert(event == &mock_event);
	closes++;
	return EFI_SUCCESS;
}

static void prepare(void)
{
	node = (struct mock_node){true, "qcom,pm8998-pon", 0x800, 1, 2, NULL};
	second_node = node;
	pmic = (struct udevice){"qcom,spmi-pmic", &node, NULL};
	second_pmic = (struct udevice){"qcom,spmi-pmic", &second_node, NULL};
	psci = (struct udevice){"arm,psci-1.0", NULL, NULL};
	pmics.first = &pmic;
	class_error = probe_error = psci_error = read_error = 0;
	version = 0x10000;
	features = reset_return = 0;
	reads = writes = resets = interrupt_restores = closes = 0;
	event_status = add_status = EFI_SUCCESS;
	byte = 0x81;
	active = true;
}

int main(void)
{
	unsigned int fault;
	u32 mask;
	struct mobile_action_result result;
	for (fault = 0; fault < 14; fault++) {
		prepare();
		switch (fault) {
		case 0:
			class_error = -ENODEV;
			break;
		case 1:
			pmics.first = NULL;
			break;
		case 2:
			node.enabled = false;
			break;
		case 3:
			node.compatible = "qcom,pm8916-pon";
			break;
		case 4:
			node.base++;
			break;
		case 5:
			node.recovery++;
			break;
		case 6:
			node.bootloader++;
			break;
		case 7:
			pmic.next = &second_pmic;
			break;
		case 8:
			probe_error = -EACCES;
			break;
		case 9:
			psci_error = -ENODEV;
			break;
		case 10:
			psci.compatible = "arm,psci";
			break;
		case 11:
			version = 1;
			break;
		case 12:
			version = 0xffffffffUL;
			break; /* Zero-extended SMC32 -1. */
		case 13:
			features = 0xffffffffUL;
			break;
		}
		assert(protocol.get_capabilities(&protocol, &mask) == EFI_UNSUPPORTED && !mask);
		result = (struct mobile_action_result){.size = sizeof(result)};
		assert(protocol.execute(&protocol, MOBILE_ACTION_BOOTLOADER, &result) ==
		       EFI_UNSUPPORTED);
		assert(!writes && !resets && result.stage == MOBILE_STAGE_PROBE);
		cases++;
	}
	prepare();
	version = 2;
	assert(protocol.get_capabilities(&protocol, &mask) == EFI_SUCCESS && mask == 3 && !writes);
	cases++;
	prepare();
	read_error = -EACCES;
	assert(protocol.get_capabilities(&protocol, &mask) == EFI_UNSUPPORTED && !mask && !writes);
	cases++;
	for (fault = 0; fault < 2; fault++) {
		prepare();
		reset_return = fault ? 0xffffffffUL : 0;
		result = (struct mobile_action_result){.size = sizeof(result)};
		assert(protocol.execute(&protocol, MOBILE_ACTION_RECOVERY, &result) ==
		       EFI_DEVICE_ERROR);
		assert(resets == 1 && writes == 2 && byte == 0x81 && interrupt_restores == 1);
		assert(result.operation_status == (fault ? -1 : 0) && result.restore_attempted &&
		       !result.restore_status);
		cases++;
	}
	prepare();
	assert(protocol.get_capabilities(NULL, &mask) == EFI_INVALID_PARAMETER);
	assert(protocol.get_capabilities(&protocol, NULL) == EFI_INVALID_PARAMETER);
	result = (struct mobile_action_result){.size = sizeof(result)};
	assert(protocol.execute(&protocol, 3, &result) == EFI_INVALID_PARAMETER);
	result.size--;
	assert(protocol.execute(&protocol, 1, &result) == EFI_INVALID_PARAMETER && !writes);
	assert(efi_mobile_boot_action_register() == EFI_SUCCESS);
	exit_callback(&mock_event, NULL);
	assert(protocol.get_capabilities(&protocol, &mask) == EFI_UNSUPPORTED && !mask);
	result.size = sizeof(result);
	assert(protocol.execute(&protocol, 1, &result) == EFI_UNSUPPORTED && !writes);
	cases++;
	prepare();
	event_status = EFI_DEVICE_ERROR;
	assert(efi_mobile_boot_action_register() == EFI_DEVICE_ERROR);
	prepare();
	add_status = EFI_DEVICE_ERROR;
	assert(efi_mobile_boot_action_register() == EFI_DEVICE_ERROR && closes == 1);
	cases++;
	printf("PASS %u actual firmware backend/protocol cases\n", cases);
	return 0;
}
