/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EARLY_FDT_GUARD_H
#define EARLY_FDT_GUARD_H
#include <stdint.h>
#include <stddef.h>
struct eg_range { uint64_t base, size; };
/* Trusted, independently established readable RAM banks; never derived from FDT.
 * blob must map fdt_pa; mapped bounds the accessible bytes (including header).
 * image is the entire selected load envelope; workspace is its writable suffix.
 * live enumerates additional firmware-owned incoming allocations. */
/* Audited pre-entry dynamic allocation exception. Strings/data are bounded FDT
 * slices, not NUL-terminated. Callback must reject unknown names/bindings/sizes.
 * It proves allocation occurs after original entry, NOT a firmware live pool. */
struct eg_dynamic {
    const unsigned char *name, *compatible;
    size_t name_len, compatible_len;
    uint64_t size;
    unsigned no_map, reusable;
    /* Raw bounded BE tuples preserve absence versus explicit zero. */
    const unsigned char *alignment, *alloc_ranges;
    size_t alignment_len, alloc_ranges_len;
};
struct eg_framebuffer {
    uint64_t base, size;
    uint32_t width, height, stride;
    /* Four-byte RGB layouts only. All-zero/all-one RGB is order independent. */
    unsigned rgb32;
};
struct eg_handoff {
    struct eg_range initrd; /* validated readable range; zero if absent */
    struct eg_framebuffer fb;
    const unsigned char *model, *compatible, *board_id;
    size_t model_len, compatible_len, board_id_len;
    const unsigned char *bootargs;
    size_t bootargs_len;
};
/* Optional explicit inherited-display contract. No implicit board selection.
 * matches binds caller-owned board/panel identity; reservation must match exactly.
 * rgb32 identifies a8r8g8b8=1,x8r8g8b8=2,a8b8g8r8=3,x8b8g8r8=4. */
struct eg_display_profile {
    struct eg_framebuffer fb;
    struct eg_range reservation;
    const char *reservation_name;
    int (*matches)(const struct eg_handoff *);
};
struct eg_input {
    const void *blob;
    size_t mapped;
    uint64_t fdt_pa;
    const struct eg_range *banks;
    size_t bank_count;
    struct eg_range image, workspace;
    const struct eg_range *live;
    size_t live_count;
    int (*allow_dynamic)(const struct eg_dynamic *);
    const struct eg_display_profile *display;
    struct eg_handoff *handoff; /* Optional, written only on success. */
};
/* 1 admits envelope only; 0 means Android fallback, NOT permission to boot. */
int eg_fdt_guard(const struct eg_input *in);
/* Also require ordered incoming memory tuples to exactly match the profile. */
int eg_fdt_guard_exact(const struct eg_input *in);
#endif
