/* SPDX-License-Identifier: GPL-2.0-only */
#include <stdint.h>
/* No device profile is selected. In particular, do NOT manufacture independent
 * RAM-bank trust by rereading the incoming FDT. No FDT or MMIO dereference is
 * permitted here until a separately reviewed profile/transport is connected.
 * Arguments describe a mapping supplied by the standard ARM64 boot contract,
 * not independently verified physical memory ownership. */
unsigned eg_bootstrap_policy(uint64_t fdt, uint64_t image, uint64_t image_size,
                             uint64_t workspace, uint64_t workspace_size)
{
    (void)fdt; (void)image; (void)image_size;
    (void)workspace; (void)workspace_size;
    return 0;
}
