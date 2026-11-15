/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_BOOTCONFIG_H
#define EG_BOOTCONFIG_H
#include <stddef.h>
/* Caller MUST supply only the initrd range returned by a successful FDT guard.
 * No FDT pointers are parsed here. No embedded kernel config fallback.
 * Result: 1 slot A, 2 slot B, 0 unknown/refused. Source is initrd bootconfig. */
enum eg_bootconfig_error {
    EG_BC_OK, EG_BC_RANGE, EG_BC_MAGIC, EG_BC_PADDING, EG_BC_SIZE,
    EG_BC_BOUNDS, EG_BC_CHECKSUM, EG_BC_NUL, EG_BC_KEY, EG_BC_ASSIGN,
    EG_BC_VALUE, EG_BC_DUPLICATE, EG_BC_SLOT, EG_BC_SEPARATOR,
    EG_BC_MISSING_SLOT
};
/* Read-only refusal telemetry. Offset is relative to the supplied initrd;
 * byte is zero when offset is outside it. Never conveys write authority. */
struct eg_bootconfig_report {
    unsigned error, byte;
    size_t offset;
};
unsigned eg_bootconfig_slot_report(const void *validated_initrd, size_t size,
                                  struct eg_bootconfig_report *report);
unsigned eg_bootconfig_slot(const void *validated_initrd, size_t size);
#endif
