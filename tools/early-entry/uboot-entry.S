/* SPDX-License-Identifier: GPL-2.0-only
 * Only reached for policy result exactly 1 after incoming x0-x3 restored.
 * Symbols MUST come from exact selected ELF/config, never fixed addresses. */
.section .text.uboot_entry,"ax"
.global eg_uboot_entry
eg_uboot_entry:
    adrp x9, uboot_stack_top
    add x9, x9, :lo12:uboot_stack_top
    mov sp, x9
    b embedded_uboot
.section .note.GNU-stack,"",%progbits
