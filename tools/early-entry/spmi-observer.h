/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_SPMI_OBSERVER_H
#define EG_SPMI_OBSERVER_H
#include <stdint.h>
/* Callbacks return 1 on success, 0 on fault/unsupported state. Counter uses
 * monotonically wrapping architectural ticks, frequency in Hz. No direct MMIO
 * defaults: platform supplies verified EE0/bus0 maps and safe access callbacks.
 * counter is optional only for find() and explicit bounded-poll read mode. */
struct eg_spmi_io {
    void *context;
    int (*read)(void *, uint64_t, uint32_t *);
    int (*write)(void *, uint64_t, uint32_t);
    int (*counter)(void *, uint64_t *);
    uint64_t frequency, core, config, observer;
};
/* APID map for v7 bus0, preferring EE0 write-owner, without requiring it. */
int eg_spmi_find(const struct eg_spmi_io *, uint16_t ppid, uint16_t *apid);
/* Only a single-byte EXT_READL command, never a PMIC value write. */
int eg_spmi_read_byte(const struct eg_spmi_io *, uint16_t apid,
                      uint16_t address, uint8_t *value);
/* Explicit poll-count policy: no counter sysregs, no wall-clock guarantee.
 * 1..100000 polls; each individual bus access must itself complete or abort. */
int eg_spmi_read_byte_bounded(const struct eg_spmi_io *, uint16_t, uint16_t,
                              uint8_t *, unsigned polls);
/* EL1h/MMU-off/little-endian/DAIF-masked only; synchronous precise abort only.
 * Caller MUST establish that asynchronous external abort/SError is not pending
 * or possible. Masking A is not a containment guarantee. No counter trap guard. */
int eg_mmio_read32(uint64_t address, uint32_t *value);
int eg_mmio_write32(uint64_t address, const uint32_t *value);
#endif
