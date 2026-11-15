/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_BOOT_CHOICE_H
#define EG_BOOT_CHOICE_H
#include <stdint.h>
/* 0 Android, 1 U-Boot. All zero pages: absent => U-Boot. Invalid
 * nonzero pages, conflicts: Android unless another valid page survives. */
unsigned eg_request_select(const unsigned char *, const unsigned char *);
#endif
