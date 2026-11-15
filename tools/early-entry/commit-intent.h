/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_COMMIT_INTENT_H
#define EG_COMMIT_INTENT_H
#include <stddef.h>
#include <stdint.h>
#ifdef __UBOOT__
#include <linux/types.h>
#endif
#define EG_INTENT_BYTES 80U
#define EG_INTENT_READ_ONLY 2U
#define EG_INTENT_PROPERTY "android-devices,boot-choice-intent"
/* This is selection context, NEVER storage authority. Unknown booted slot is
 * deliberate: GPT active flags are not evidence of the slot actually booted. */
struct eg_choice_observation { uint64_t sequence; unsigned mode; };
enum eg_choice_route {
    EG_ORIGINAL_ANDROID = 0, EG_UBOOT_UNCHANGED = 1,
    EG_UBOOT_COMMIT_ANDROID = 2, EG_UBOOT_COMMIT_UBOOT = 3,
    EG_CHOICE_REFUSED = 4
};
/* Strict owned-image request semantics, unlike the legacy selector fallback.
 * None valid, equal sequences, generation mismatch and absent pages refuse. */
int eg_request_observe(const unsigned char *pages, const unsigned char *generation,
                       struct eg_choice_observation *out);
enum eg_choice_route eg_choice_route(const struct eg_choice_observation *, unsigned selected);
/* Encode changed selections or unchanged U-Boot (NOPREFWRITE, flag 0).
 * Slot/source are explicitly unavailable (0).
 * EFI must independently establish booted partition before permitting writes. */
int eg_intent_encode(unsigned char *out, const unsigned char *generation,
                     const struct eg_choice_observation *, unsigned selected);
/* Bind verified initrd bootconfig slot (1=A, 2=B), source wire value 1.
 * Legacy unknown context remains decodable but conveys no write authority. */
int eg_intent_bind_slot(unsigned char *, const unsigned char *, unsigned slot);
/* Early picker: selected Linux, observed stored mode unchanged, no writes.
 * Flag2 is explicit so older firmware/helpers refuse rather than commit. */
int eg_intent_encode_readonly(unsigned char *, const unsigned char *,
                             const struct eg_choice_observation *);
int eg_intent_decode(const unsigned char *in, const unsigned char *generation,
                     struct eg_choice_observation *, unsigned *selected);
/* Separate owned, 8-aligned destination, at most 2 MiB. Validates the complete
 * bounded canonical v17 stream before writing ANY destination byte. The caller
 * must additionally prove destination ownership/identity with its profile guard.
 * One existing /chosen is required; any preexisting intent property refuses.
 * Returns new totalsize, or zero. Original bytes are never written. */
size_t eg_fdt_copy_intent(const void *src, size_t mapped, void *dst, size_t capacity,
                          const unsigned char *token);
#endif
