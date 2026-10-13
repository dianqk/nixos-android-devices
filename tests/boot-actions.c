/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Actual helper and PON transaction code, with isolated EFI/PMIC mocks.
 * Compile with GNU EFI headers and -fshort-wchar. No hardware access. */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "../pkgs/mobile-boot-action/main.c"
#include "../pkgs/mobile-boot-action/pon-transaction.h"

static unsigned int cases;
static EFI_INPUT_KEY keys[8];
static unsigned int key_count, key_index, executes, waits, watchdog_calls;
static unsigned int not_ready_remaining;
static EFI_STATUS wait_status;
static EFI_STATUS disable_status, restore_status, image_status, locate_status;
static EFI_STATUS input_reset_status, capability_status;
static UINT32 capability_mask, executed_action;
static struct mobile_boot_action_protocol mock_protocol;
static EFI_LOADED_IMAGE mock_image;
static EFI_BOOT_SERVICES services;
static SIMPLE_INPUT_INTERFACE input;
static EFI_SYSTEM_TABLE table;

VOID InitializeLib(EFI_HANDLE handle, EFI_SYSTEM_TABLE *systab) {}
UINTN Print(CONST CHAR16 *format, ...) { return 0; }
UINTN StrLen(CONST CHAR16 *text)
{
	UINTN length = 0;
	while (text[length])
		length++;
	return length;
}

static EFI_STATUS EFIAPI watchdog(UINTN timeout, UINT64 code, UINTN size, CHAR16 *data)
{
	watchdog_calls++;
	if (!timeout) {
		assert(watchdog_calls == 1 && code == 0 && size == 0 && !data);
		return disable_status;
	}
	assert(timeout == 300 && code == 0x10000 && watchdog_calls == 2);
	return restore_status;
}

static EFI_STATUS EFIAPI handle_protocol(EFI_HANDLE handle, EFI_GUID *guid, VOID **out)
{
	*out = &mock_image;
	return image_status;
}

static EFI_STATUS EFIAPI locate_protocol(EFI_GUID *guid, VOID *registration, VOID **out)
{
	*out = &mock_protocol;
	return locate_status;
}

static EFI_STATUS EFIAPI input_reset(SIMPLE_INPUT_INTERFACE *self, BOOLEAN extended)
{
	assert(executes == 0);
	return input_reset_status;
}

static EFI_STATUS EFIAPI input_read(SIMPLE_INPUT_INTERFACE *self, EFI_INPUT_KEY *key)
{
	assert(watchdog_calls == 1 && !disable_status);
	if (not_ready_remaining) {
		not_ready_remaining--;
		return EFI_NOT_READY;
	}
	if (key_index >= key_count)
		return EFI_DEVICE_ERROR;
	*key = keys[key_index++];
	return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI wait_event(UINTN count, EFI_EVENT *events, UINTN *index)
{
	waits++;
	assert(!disable_status && watchdog_calls == 1);
	return wait_status;
}

static EFI_STATUS EFIAPI capabilities(struct mobile_boot_action_protocol *self, UINT32 *mask)
{
	*mask = capability_mask;
	return capability_status;
}

static EFI_STATUS EFIAPI execute_action(struct mobile_boot_action_protocol *self, UINT32 action,
					struct mobile_action_result *result)
{
	assert(result->size == sizeof(*result));
	executes++;
	executed_action = action;
	result->stage = MOBILE_STAGE_RESET;
	result->operation_status = -1;
	result->restore_attempted = 1;
	return EFI_DEVICE_ERROR;
}

static void prepare(CHAR16 *options)
{
	memset(&table, 0, sizeof(table));
	memset(&services, 0, sizeof(services));
	memset(&input, 0, sizeof(input));
	memset(&mock_image, 0, sizeof(mock_image));
	memset(keys, 0, sizeof(keys));
	executes = waits = watchdog_calls = key_count = key_index = 0;
	not_ready_remaining = 0;
	wait_status = EFI_SUCCESS;
	disable_status = restore_status = image_status = locate_status = EFI_SUCCESS;
	input_reset_status = capability_status = EFI_SUCCESS;
	capability_mask = MOBILE_ACTION_MASK | MOBILE_ACTION_AB_MASK;
	mock_protocol = (struct mobile_boot_action_protocol){
	    MOBILE_BOOT_ACTION_REVISION, sizeof(mock_protocol), capabilities, execute_action};
	mock_image.LoadOptions = options;
	mock_image.LoadOptionsSize = options ? (StrLen(options) + 1) * 2 : 0;
	services.SetWatchdogTimer = watchdog;
	services.HandleProtocol = handle_protocol;
	services.LocateProtocol = locate_protocol;
	services.WaitForEvent = wait_event;
	input.Reset = input_reset;
	input.ReadKeyStroke = input_read;
	table.BootServices = &services;
	table.ConIn = &input;
	keys[0].UnicodeChar = CHAR_CARRIAGE_RETURN;
	key_count = 1;
}

static void run_helper(unsigned int expected)
{
	assert(efi_main(NULL, &table) == EFI_SUCCESS);
	assert(executes == expected);
	assert(watchdog_calls == (disable_status ? 1 : 2));
	cases++;
}

struct pmic_mock {
	unsigned char byte, writes[3];
	int reads, write_count, reset_count;
	int read_error_at, read_mismatch_at, write_error_at;
	int reset_result;
};

static int pmic_read_mock(void *context, unsigned char *value)
{
	struct pmic_mock *p = context;
	p->reads++;
	if (p->reads == p->read_error_at)
		return -EACCES;
	*value = p->byte ^ (p->reads == p->read_mismatch_at ? 1 : 0);
	return 0;
}

static int pmic_write_mock(void *context, unsigned char value)
{
	struct pmic_mock *p = context;
	p->writes[p->write_count++] = value;
	/* A write error may occur after changing hardware: always restore. */
	p->byte = value;
	return p->write_count == p->write_error_at ? -EACCES : 0;
}

static int reset_mock(void *context)
{
	struct pmic_mock *p = context;
	p->reset_count++;
	assert(p->reads == 2 && p->write_count == 1);
	return p->reset_result;
}

static void transactions(void)
{
	unsigned int old, action, fault;
	for (old = 0; old < 256; old++) {
		for (action = 1; action <= 2; action++) {
			for (fault = 0; fault < 9; fault++) {
				struct pmic_mock p = {.byte = old,
						      .reset_result = fault == 7 ? -1 : 0};
				struct mobile_pon_ops ops = {pmic_read_mock, pmic_write_mock,
							     reset_mock, &p};
				struct mobile_action_result result = {.size = sizeof(result)};
				if (fault == 1)
					p.read_error_at = 1;
				if (fault == 2)
					p.write_error_at = 1;
				if (fault == 3)
					p.read_error_at = 2;
				if (fault == 4)
					p.read_mismatch_at = 2;
				if (fault == 5)
					p.write_error_at = 2;
				if (fault == 6)
					p.read_mismatch_at = 3;
				if (fault == 8)
					p.read_error_at = 3;
				assert(mobile_pon_execute(&ops, action, &result) < 0);
				assert(p.byte == old);
				if (fault == 1) {
					assert(!p.write_count && !p.reset_count &&
					       !result.restore_attempted);
				} else {
					assert(p.writes[0] == ((old & 1) | (action == 1 ? 4 : 2)));
					assert(p.write_count == 2 && p.writes[1] == old &&
					       result.restore_attempted);
					assert((result.restore_status != 0) ==
					       (fault == 5 || fault == 6 || fault == 8));
					assert(p.reset_count == (fault == 0 || fault >= 5));
				}
				cases++;
			}
		}
	}
	{
		struct pmic_mock p = {.byte = 0x81};
		struct mobile_pon_ops ops = {pmic_read_mock, pmic_write_mock, reset_mock, &p};
		struct mobile_action_result result = {.size = sizeof(result)};
		assert(mobile_pon_execute(&ops, 3, &result) == -EINVAL);
		assert(!p.reads && !p.write_count && !p.reset_count);
		cases++;
	}
}

int main(void)
{
	unsigned int action, fault;
	CHAR16 *names[] = {L"bootloader", L"recovery", L"android", L"recovery-b"};
	UINT32 actions[] = {MOBILE_ACTION_BOOTLOADER, MOBILE_ACTION_RECOVERY, MOBILE_ACTION_ANDROID, MOBILE_ACTION_RECOVERY_B};
	for (action = 0; action < 4; action++) {
		prepare(names[action]);
		run_helper(0); /* Enter defaults to Cancel. */
		prepare(names[action]);
		keys[0].ScanCode = SCAN_ESC;
		run_helper(0);
		prepare(names[action]);
		keys[0] = (EFI_INPUT_KEY){.ScanCode = SCAN_DOWN};
		keys[1].UnicodeChar = CHAR_CARRIAGE_RETURN;
		key_count = 2;
		run_helper(1);
		assert(executed_action == actions[action]);
		prepare(names[action]);
		keys[0] = (EFI_INPUT_KEY){.ScanCode = SCAN_DOWN};
		keys[1] = (EFI_INPUT_KEY){.ScanCode = SCAN_UP};
		keys[2].UnicodeChar = CHAR_CARRIAGE_RETURN;
		key_count = 3;
		run_helper(0);
		prepare(names[action]);
		mock_image.LoadOptionsSize -= 2;
		run_helper(0);
	}
	for (fault = 0; fault < 13; fault++) {
		prepare(L"bootloader");
		switch (fault) {
		case 0:
			disable_status = EFI_DEVICE_ERROR;
			break;
		case 1:
			restore_status = EFI_DEVICE_ERROR;
			break;
		case 2:
			image_status = EFI_NOT_FOUND;
			break;
		case 3:
			locate_status = EFI_NOT_FOUND;
			break;
		case 4:
			mock_protocol.revision++;
			break;
		case 5:
			mock_protocol.size--;
			break;
		case 6:
			mock_protocol.execute = NULL;
			break;
		case 7:
			capability_status = EFI_UNSUPPORTED;
			break;
		case 8:
			capability_mask = MOBILE_ACTION_RECOVERY;
			break;
		case 9:
			input_reset_status = EFI_DEVICE_ERROR;
			break;
		case 10:
			mock_image.LoadOptionsSize = 3;
			break;
		case 11:
			mock_image.LoadOptionsSize = 100;
			break;
		case 12:
			mock_image.LoadOptions = NULL;
			break;
		}
		run_helper(0);
	}
	prepare(L"bootloader\0junk");
	mock_image.LoadOptionsSize = 32;
	run_helper(0);
	prepare(L"BOOTLOADER");
	run_helper(0);
	prepare(L"recovery extra");
	run_helper(0);
	prepare(L"bootloader");
	not_ready_remaining = 4;
	run_helper(0);
	assert(waits == 4);
	prepare(L"bootloader");
	not_ready_remaining = 1;
	wait_status = EFI_DEVICE_ERROR;
	run_helper(0);
	assert(waits == 1);
	transactions();
	printf("PASS %u isolated helper/PMIC cases\n", cases);
	return 0;
}
