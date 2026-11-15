/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_RUNTIME_TEMPLATE_H
#define EG_RUNTIME_TEMPLATE_H
/* Fixed data ABI. No instruction relocation/patch table is accepted at runtime. */
#define EG_RUNTIME_BYTES 32
#define EG_RUNTIME_ENTRY 8
#define EG_RUNTIME_INVERSE 16
#define EG_RUNTIME_STORED 24
#ifndef __ASSEMBLER__
#include <stdint.h>
#include <stddef.h>
struct eg_runtime_parameters {
    unsigned char magic[8];
    uint64_t android_entry, android_entry_inverse, stored_kernel;
};
_Static_assert(sizeof(struct eg_runtime_parameters)==EG_RUNTIME_BYTES, "runtime size");
_Static_assert(offsetof(struct eg_runtime_parameters,android_entry)==EG_RUNTIME_ENTRY, "entry offset");
_Static_assert(offsetof(struct eg_runtime_parameters,android_entry_inverse)==EG_RUNTIME_INVERSE, "inverse offset");
_Static_assert(offsetof(struct eg_runtime_parameters,stored_kernel)==EG_RUNTIME_STORED, "stored offset");
#endif
#endif
