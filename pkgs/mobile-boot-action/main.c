// SPDX-License-Identifier: GPL-2.0-or-later
#include "protocol.h"
#include <efi.h>
#include <efilib.h>

static EFI_SYSTEM_TABLE *system_table;
static EFI_GUID action_guid = MOBILE_BOOT_ACTION_GUID;

/* Parse exactly one bounded UTF-16 load option. Reject embedded NUL/trailing
 * data and do not silently select a target when options are missing. */
static UINT32 parse_action(EFI_LOADED_IMAGE *image)
{
	CHAR16 *options = image->LoadOptions;
	UINTN length = image->LoadOptionsSize / sizeof(CHAR16);
	UINTN i;
	CHAR16 *name;
	UINT32 action;

	if (!options || !length || length > 32 || image->LoadOptionsSize % 2)
		return 0;
	if (options[length - 1] == 0)
		length--;
	if (length == 10) {
		action = MOBILE_ACTION_BOOTLOADER;
		name = L"bootloader";
	} else if (length == 7) {
		action = MOBILE_ACTION_ANDROID;
		name = L"android";

	} else {
		action = MOBILE_ACTION_RECOVERY;
		name = L"recovery";
	}
	/* recovery-b and bootloader have the same length. */
	if (length == 10 && options[0] == L'r') {
		action = MOBILE_ACTION_RECOVERY_B;
		name = L"recovery-b";
	}
	if (length != StrLen(name))
		return 0;
	for (i = 0; i < length; i++)
		if (options[i] != name[i])
			return 0;
	return action;
}

static EFI_STATUS read_key(EFI_INPUT_KEY *key)
{
	UINTN index;
	EFI_STATUS status;

	for (;;) {
		status = system_table->ConIn->ReadKeyStroke(system_table->ConIn, key);
		if (status != EFI_NOT_READY)
			return status;
		status = system_table->BootServices->WaitForEvent(
		    1, &system_table->ConIn->WaitForKey, &index);
		if (EFI_ERROR(status))
			return status;
	}
}

static BOOLEAN confirm(UINT32 action)
{
	EFI_INPUT_KEY key;
	BOOLEAN execute = FALSE;

	/* Drop the selection key left by the parent menu. A saved/default entry
	 * always stops here, with Cancel selected and no automatic execution. */
	if (EFI_ERROR(system_table->ConIn->Reset(system_table->ConIn, FALSE)))
		return FALSE;
	for (;;) {
		Print(L"\r\nReboot to %s?\r\n%s Cancel\r\n%s Reboot\r\n"
		      L"Volume: select; Power/Enter: confirm; Escape: cancel.\r\n",
		      action == MOBILE_ACTION_BOOTLOADER ? L"OEM bootloader" :
		      action == MOBILE_ACTION_ANDROID ? L"Android (slot A)" :
		      action == MOBILE_ACTION_RECOVERY_B ? L"NixOS recovery (slot B)" : L"recovery",
		      execute ? L" " : L">", execute ? L">" : L" ");
		if (EFI_ERROR(read_key(&key)))
			return FALSE;
		if (key.ScanCode == SCAN_ESC)
			return FALSE;
		if (key.ScanCode == SCAN_UP || key.ScanCode == SCAN_DOWN)
			execute = !execute;
		else if (key.UnicodeChar == CHAR_CARRIAGE_RETURN)
			return execute;
	}
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE image_handle, EFI_SYSTEM_TABLE *table)
{
	EFI_GUID loaded_image_guid = LOADED_IMAGE_PROTOCOL;
	EFI_LOADED_IMAGE *image;
	struct mobile_boot_action_protocol *protocol;
	struct mobile_action_result result = {.size = sizeof(result)};
	EFI_STATUS status;
	EFI_INPUT_KEY key;
	UINT32 action, mask;

	InitializeLib(image_handle, table);
	system_table = table;
	/* When the watchdog cannot be disabled, never enter an unbounded wait. */
	status = table->BootServices->SetWatchdogTimer(0, 0, 0, NULL);
	if (EFI_ERROR(status)) {
		Print(L"Cannot disable EFI watchdog: %r. Returning to menu.\r\n", status);
		return EFI_SUCCESS;
	}
	status =
	    table->BootServices->HandleProtocol(image_handle, &loaded_image_guid, (VOID **)&image);
	if (EFI_ERROR(status) || !(action = parse_action(image))) {
		Print(L"Invalid boot action options.\r\n");
		goto error;
	}
	status = table->BootServices->LocateProtocol(&action_guid, NULL, (VOID **)&protocol);
	if (EFI_ERROR(status)) {
		Print(L"Firmware has no mobile boot-action interface. Update U-Boot first.\r\n");
		goto error;
	}
	if (protocol->revision != MOBILE_BOOT_ACTION_REVISION ||
	    protocol->size != sizeof(*protocol) || !protocol->get_capabilities ||
	    !protocol->execute) {
		Print(L"Incompatible mobile boot-action interface.\r\n");
		goto error;
	}
	mask = 0;
	status = protocol->get_capabilities(protocol, &mask);
	if (EFI_ERROR(status) || !(mask & action)) {
		Print(L"Firmware cannot perform this action.\r\n");
		if (action == MOBILE_ACTION_ANDROID || action == MOBILE_ACTION_RECOVERY_B)
			Print(L"Check slot B, boot LUN mapping, GPT copies, BCB and snapshot state.\r\n");
		else
			Print(L"Check the firmware reboot backend: %r.\r\n", status);
		goto error;
	}
	if (!confirm(action))
		goto back;
	status = protocol->execute(protocol, action, &result);
	Print(L"Reboot returned: %r; stage %u; code %d.\r\n", status, result.stage,
	      result.operation_status);
	if (result.restore_attempted)
		Print(L"Original boot state restore code: %d.\r\n", result.restore_status);
error:
	Print(L"Press a key to return to the boot menu.\r\n");
	read_key(&key);
back:
	/* Match systemd-boot's child-image watchdog contract. The original timer
	 * cannot be queried through UEFI; this is the parent's known setting. */
	status = table->BootServices->SetWatchdogTimer(300, 0x10000, 0, NULL);
	if (EFI_ERROR(status))
		Print(L"Cannot reinstall EFI watchdog: %r. Returning to menu.\r\n", status);
	/* Error/Cancel returns success so reboot-on-error cannot turn it into reset. */
	return EFI_SUCCESS;
}
