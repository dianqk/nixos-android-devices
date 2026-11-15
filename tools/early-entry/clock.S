/* SPDX-License-Identifier: BSD-2-Clause-Patent */
// Adapted from slwyts/Project-SunUEFI 018634f18c74704e6668ee5d816d038bc6591849
// uefi/handoff/bootselect/EarlyMmio.S; see provenance.md.
// Guard only the two counter MRS instructions, restoring ABL's vector and
// exception registers before returning. No MMU/cache/interrupt setup.
// Only synchronous system-register traps routed to EL1 are recoverable.
// EL2/EL3 interception must be excluded by a firmware counter-access contract.
// SError/asynchronous external abort is NOT contained; the caller must exclude
// such platforms/states BEFORE calling. Unexpected exceptions halt, not fallback.
.text
.p2align 2
.global eg_clock_read
.type eg_clock_read,%function
eg_clock_read:
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
  tbnz x9, #2, .Lunsupported // no data-cache ownership/clean contract
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
  isb
.Lfrequency:
  mrs x3, cntfrq_el0
.Lcounter:
  mrs x4, cntpct_el0
  str x3, [x0]
  str x4, [x1]
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
  lsr x7, x5, #26
  cbz x7, .Lcheckpc // UNDEFINED at exact MRS only
  cmp x7, #0x18 // trapped system register, routed to this EL only
  b.ne .Lsavedunexpected
.Lcheckpc:
  adr x7, .Lfrequency
  cmp x4, x7
  b.eq .Lrecover
  adr x7, .Lcounter
  cmp x4, x7
  b.ne .Lsavedunexpected
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
