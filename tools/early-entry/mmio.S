/* SPDX-License-Identifier: BSD-2-Clause-Patent */
// Adapted from slwyts/Project-SunUEFI 018634f18c74704e6668ee5d816d038bc6591849
// uefi/handoff/bootselect/EarlyMmio.S; see provenance.md.
// Guard only the specified MMIO instruction, restoring ABL's vector and
// exception registers before returning. No MMU/cache/interrupt setup.
// Only precise synchronous abort at the exact MMIO instruction is recoverable.
// SError/asynchronous external abort is NOT contained; the caller must exclude
// such platforms/states BEFORE calling. Unexpected exceptions halt, not fallback.
.text
.p2align 2
.global eg_mmio_read32
.type eg_mmio_read32,%function
eg_mmio_read32:
  mov w2, #0
  b .Laccess
.global eg_mmio_write32
.type eg_mmio_write32,%function
eg_mmio_write32:
  mov w2, #1
.Laccess:
  mrs x9, CurrentEL
  cmp x9, #4
  b.ne .Lunsupported
  mrs x9, SPSel
  cmp x9, #1
  b.ne .Lunsupported
  mrs x9, sctlr_el1
  tst x9, #1
  b.ne .Lunsupported
  tbnz x9, #25, .Lunsupported
  mrs x9, daif
  cmp x9, #0x3c0
  b.ne .Lunsupported
  stp x19, x20, [sp, #-64]!
  mrs x19, vbar_el1
  mrs x20, daif
  mrs x9, elr_el1
  mrs x10, spsr_el1
  stp x9, x10, [sp, #16]
  mrs x9, esr_el1
  mrs x10, far_el1
  stp x9, x10, [sp, #32]
  msr daifset, #15
  adr x9, .Lvectors
  msr vbar_el1, x9
  isb
  cbnz w2, .Lwrite
.Lload:
  ldr w3, [x0]
  dsb sy
  str w3, [x1]
  b .Lsuccess
.Lwrite:
  ldr w3, [x1]
.Lstore:
  str w3, [x0]
  dsb sy
.Lsuccess:
  mov w0, #1
  b .Lrestore
.Lfailed:
  mov w0, #0
.Lrestore:
  msr daifset, #15
  ldp x9, x10, [sp, #16]
  msr elr_el1, x9
  msr spsr_el1, x10
  ldp x9, x10, [sp, #32]
  msr esr_el1, x9
  msr far_el1, x10
  msr vbar_el1, x19
  isb
  msr daif, x20
  ldp x19, x20, [sp], #64
  ret
.Lunsupported:
  mov w0, #0
  ret

.macro SLOT handler
  b \handler
  .space 124
.endm
.p2align 11
.Lvectors:
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lsync
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
  SLOT .Lunexpected
.Lsync:
  stp x4, x5, [sp, #-32]!
  stp x6, x7, [sp, #16]
  mrs x4, elr_el1
  mrs x5, esr_el1
  mrs x6, far_el1
  lsr x7, x5, #26
  cmp x7, #0x25
  b.ne .Lsavedunexpected
  tbz x5, #25, .Lsavedunexpected
  tbnz x5, #10, .Lsavedunexpected
  cmp x6, x0
  b.ne .Lsavedunexpected
  cbnz w2, .Lcheckstore
  adr x7, .Lload
  cmp x4, x7
  b.ne .Lsavedunexpected
  tbnz x5, #6, .Lsavedunexpected
  b .Lrecover
.Lcheckstore:
  adr x7, .Lstore
  cmp x4, x7
  b.ne .Lsavedunexpected
  tbz x5, #6, .Lsavedunexpected
.Lrecover:
  adr x7, .Lfailed
  msr elr_el1, x7
  ldp x6, x7, [sp, #16]
  ldp x4, x5, [sp], #32
  eret
.Lsavedunexpected:
  ldp x6, x7, [sp, #16]
  ldp x4, x5, [sp], #32
.Lunexpected:
  wfe
  b .Lunexpected
.section .note.GNU-stack,"",%progbits
