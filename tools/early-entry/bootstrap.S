/* SPDX-License-Identifier: GPL-2.0-only
 * Supported handoff: AArch64 EL1h, little endian, MMU off, DAIF masked.
 * Original Linux Image ABI x0-x3/SP/DAIF/NZCV are restored on EVERY return.
 * x4-x18 are caller scratch, including ADR scratch acquisition. x19-x29 are
 * preserved by AAPCS64. Entry is not a callable AAPCS64 function.
 * Only exact policy result 1 selects the separately linked U-Boot entry.
 */
#include "runtime-template.h"
.section .text.bootstrap, "ax"
.balign 4
.global eg_bootstrap
.type eg_bootstrap, %function
eg_bootstrap:
    mrs x17, nzcv
#ifdef EG_RUNTIME_TEMPLATE
    adrp x13, eg_runtime_parameters
    add x13, x13, :lo12:eg_runtime_parameters
    ldr x14, [x13]
    ldr x12, =0x3130304e55524342
    cmp x14, x12
    b.ne .Lbad_parameters
    ldr x16, [x13, #EG_RUNTIME_ENTRY]
    ldr x14, [x13, #EG_RUNTIME_INVERSE]
    eor x14, x14, x16
    cmn x14, #1
    b.ne .Lbad_parameters
    tst x16, #3
    b.ne .Lbad_parameters
    cmp x16, #64
    b.lo .Lbad_parameters
    ldr x14, [x13, #EG_RUNTIME_STORED]
    cmp x16, x14
    b.hs .Lbad_parameters
    adrp x12, eg_request_pages
    add x12, x12, :lo12:eg_request_pages
    adrp x13, eg_image_start
    add x13, x13, :lo12:eg_image_start
    sub x12, x12, x13
    cmp x14, x12
    b.hi .Lbad_parameters
    add x16, x13, x16
#endif
    mrs x16, CurrentEL
    cmp x16, #4
    b.ne .Lunsupported
    mrs x16, SPSel
    cbz x16, .Lunsupported
    mrs x16, sctlr_el1
    tbnz x16, #0, .Lunsupported
    tbnz x16, #25, .Lunsupported
    mrs x11, daif
    cmp x11, #0x3c0
    b.ne .Lunsupported
    /* Standard Image boot contract guarantees the advertised, materialized
     * footprint. This is not a guard against collisions during OEM loading. */
    mov x10, sp
    adrp x16, eg_scratch_end
    add x16, x16, :lo12:eg_scratch_end
    mov sp, x16
    sub sp, sp, #80
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x10, x11, [sp, #32]
    stp x17, x30, [sp, #48]
    adrp x1, eg_image_start
    add x1, x1, :lo12:eg_image_start
    adrp x2, eg_image_end
    add x2, x2, :lo12:eg_image_end
    sub x2, x2, x1
    adrp x3, eg_workspace_start
    add x3, x3, :lo12:eg_workspace_start
    adrp x4, eg_workspace_end
    add x4, x4, :lo12:eg_workspace_end
    sub x4, x4, x3
    /* Optional sixth argument. Old five-argument policies ignore it. Always
     * zero on each invocation; only exact U-Boot result may consume it. */
    stp xzr, xzr, [sp, #64]
    add x5, sp, #64
    bl eg_bootstrap_policy
    /* Validate before restoring incoming argument registers. No other result
     * can select U-Boot, including arbitrary/corrupt nonzero results. */
    cmp w0, #1
    b.eq .Luboot_restore
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x10, x11, [sp, #32]
    ldp x17, x30, [sp, #48]
    mov sp, x10
    msr daif, x11
.Lunsupported:
#ifdef EG_RUNTIME_TEMPLATE
    /* The compiler-free installer supplies bounded DATA, never branch fixups.
     * Corrupt entry parameters cannot safely identify original Android: park,
     * rather than branch to a guessed target or touch hardware. */
    adrp x13, eg_runtime_parameters
    add x13, x13, :lo12:eg_runtime_parameters
    ldr x16, [x13, #EG_RUNTIME_ENTRY]
    adrp x13, eg_image_start
    add x13, x13, :lo12:eg_image_start
    add x16, x13, x16
    msr nzcv, x17
    br x16
.global eg_bad_runtime_parameters
eg_bad_runtime_parameters:
.Lbad_parameters:
    wfe
    b .Lbad_parameters
#else
    msr nzcv, x17
    b eg_android_entry
#endif
.Luboot_restore:
    ldp x0, x1, [sp, #0]
    ldr x9, [sp, #64]
    cmp x9, #0
    csel x0, x0, x9, eq
    ldp x2, x3, [sp, #16]
    ldp x10, x11, [sp, #32]
    ldp x17, x30, [sp, #48]
    msr daif, x11
    msr nzcv, x17
    mov sp, x10
    /* Platform entry supplies its independently resolved image-owned stack.
     * Incoming x0 is the original FDT, as save_boot_params expects. */
    b eg_uboot_entry
.size eg_bootstrap, . - eg_bootstrap
.section .note.GNU-stack,"",%progbits

#ifdef EG_RUNTIME_TEMPLATE
.section .data.eg_runtime,"aw",%progbits
.balign 8
.global eg_runtime_parameters
eg_runtime_parameters:
    .ascii "BCRUN001"
    .quad 0, 0, 0
#endif
