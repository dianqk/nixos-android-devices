/* SPDX-License-Identifier: GPL-2.0-only */
/* Exact Android kernel-exported geometry, NOT unmodified ABL provenance.
 * This is explicit device geometry, not a generic SoC fallback. No generic fallback geometry. */
#ifndef DODGE_EARLY_PROFILE_H
#define DODGE_EARLY_PROFILE_H
#include "fdt-guard.h"
#include "spmi-observer.h"
#include "dynamic.h"
static const struct eg_range dodge_observed_banks[] = {
    {0x81960000ULL, 0xa0000ULL},
    {0x81a40000ULL, 0x1c0000ULL},
    {0x81cf4000ULL, 0xc000ULL},
    {0x82460000ULL, 0x40000ULL},
    {0xbe360000ULL, 0x16ac3000ULL},
    {0xd5100000ULL, 0x2f00000ULL},
    {0xe3720000ULL, 0x1c0e0000ULL},
    {0x880000000ULL, 0x2f2fc000ULL},
    {0x8b0000000ULL, 0x1500000ULL},
    {0xa00000000ULL, 0x400000000ULL},
    {0x8c0000000ULL, 0x140000000ULL},
    {0x82800000ULL, 0x2200000ULL},
    {0x89d80000ULL, 0x1c80000ULL},
    {0xa3e80000ULL, 0x14180000ULL},
    {0xb81c0000ULL, 0x5770000ULL},
};
/* Caller supplies expanded image and full appended writable+payload suffix,
 * not just scratch. Any additional live allocations must be in in->live.
 * Incoming FDT is used only after its <=2MiB mapping lies in one known bank. */
static inline int dodge_profile_guard(struct eg_input *in)
{
    const uint64_t limit=2U*1024U*1024U;
    int mapped=0;
    if (!in || !in->blob || (in->fdt_pa&7) || !in->mapped || in->mapped>limit)
        return 0;
    for (unsigned i=0;i<sizeof(dodge_observed_banks)/sizeof(*dodge_observed_banks);i++) {
        struct eg_range b=dodge_observed_banks[i];
        if (in->fdt_pa>=b.base && in->fdt_pa-b.base<b.size &&
            in->mapped<=b.size-(in->fdt_pa-b.base)) mapped=1;
    }
    if (!mapped) return 0;
    in->allow_dynamic=dodge_allow_dynamic; /* Exact original allocator audit. */
    in->banks=dodge_observed_banks;
    in->bank_count=sizeof(dodge_observed_banks)/sizeof(*dodge_observed_banks);
    return eg_fdt_guard_exact(in);
}
/* Explicit Dodge bus0/EE0 maps. Does not install callbacks or execute I/O. */
static inline void dodge_spmi_maps(struct eg_spmi_io *io)
{ io->core=0xc400000; io->config=0xc42d000; io->observer=0xc440000; }
/* Up selects U-Boot; Down/both/error select Android; no-key uses request.
 * Caller must first pass guard and prove supported synchronous-only I/O state.
 * Bounded sample; no debouncing/hold or hardware validation claimed. */
static inline int dodge_key_select(const struct eg_spmi_io *io)
{
    uint16_t pon,gpio; uint8_t up,down;
    if (!eg_spmi_find(io,0x013,&pon) || !eg_spmi_find(io,0x18d,&gpio) ||
        !eg_spmi_read_byte_bounded(io,pon,0x1310,&up,1000) ||
        !eg_spmi_read_byte_bounded(io,gpio,0x8d10,&down,1000)) return -1;
    if(!(down&1)) return 2; /* Down (including both) => Android */
    if(up&0x40) return 1;
    return 0; /* successful no-key => persistent preference */
}
#endif
