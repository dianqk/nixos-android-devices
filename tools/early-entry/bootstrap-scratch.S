/* SPDX-License-Identifier: GPL-2.0-only
 * This section MUST be retained inside the materialized expanded Image, after
 * existing Android data and outside U-Boot's independently resolved workspace.
 * It is PROGBITS, not NOBITS: the full stack is present in the raw output.
 */
.section .data.eg_scratch, "aw", %progbits
.balign 16
.global eg_scratch_start, eg_scratch_end
eg_scratch_start:
    .zero 16384
eg_scratch_end:
.section .note.GNU-stack,"",%progbits
