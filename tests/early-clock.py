#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""QEMU EL1 counter success/trap/unsupported state and exception-register restoration."""
import os
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
QEMU=os.environ.get('QEMU_SYSTEM_AARCH64','qemu-system-aarch64')
assembly='''
.global _start
_start:
 msr daifset, #15
 adr x9, stack_end
 mov sp, x9
 adr x9, original_vectors
 msr vbar_el1, x9
 mov x9, #0x1234
 msr elr_el1, x9
 msr spsr_el1, x9
 msr far_el1, x9
 msr esr_el1, x9
 // Record architectural readback (some fields RES0).
 mrs x22, elr_el1
 mrs x23, spsr_el1
 mrs x24, esr_el1
 mrs x25, far_el1
 mov x19, #0x1919
 mov x20, #0x2020
 adr x0, value
 adr x1, result
 bl eg_clock_read
 cmp w0, #EXPECTED
 b.ne fail
 mrs x9, elr_el1
 cmp x9, x22
 b.ne fail
 mrs x9, spsr_el1
 cmp x9, x23
 b.ne fail
 mrs x9, esr_el1
 cmp x9, x24
 b.ne fail
 mrs x9, far_el1
 cmp x9, x25
 b.ne fail
 mrs x9, vbar_el1
 adr x10, original_vectors
 cmp x9, x10
 b.ne fail
 mrs x9, daif
 cmp x9, #0x3c0
 b.ne fail
 mov x9, #0x1919
 cmp x19, x9
 b.ne fail
 mov x9, #0x2020
 cmp x20, x9
 b.ne fail
 mov x9, sp
 adr x10, stack_end
 cmp x9, x10
 b.ne fail
 mov x1, #0
 b exit
fail: mov x1, #1
exit:
 adr x2, block
 str x1, [x2, #8]
 mov x1, x2
 mov x0, #0x20
 hlt #0xf000
 b .
.balign 8
value: .quad 0x55
result: .quad 0
block: .quad 0x20026, 0
.balign 2048
original_vectors: .space 2048
.balign 16
.space 4096
stack_end:
'''
for case in ('normal','frequency-trap','counter-trap','cache-on'):
 with tempfile.TemporaryDirectory() as d:
    w=Path(d)
    code=assembly.replace('EXPECTED','1' if case=='normal' else '0')
    if case=='cache-on':
        code=code.replace(' adr x0, value',' mrs x9,sctlr_el1\n orr x9,x9,#4\n msr sctlr_el1,x9\n isb\n adr x0, value',1)
    (w/'test.S').write_text(code)
    clock=(ROOT/'tools/early-entry/clock.S').read_text()
    if case=='frequency-trap':clock=clock.replace('mrs x3, cntfrq_el0','.inst 0')
    if case=='counter-trap':clock=clock.replace('mrs x4, cntpct_el0','.inst 0')
    (w/'clock.S').write_text(clock)
    (w/'link.ld').write_text('ENTRY(_start) SECTIONS { . = 0x40080000; .text : { *(.text*) } }')
    for src,name in [(w/'test.S','test'),(w/'clock.S','clock')]:
        subprocess.run(['as',str(src),'-o',str(w/(name+'.o'))],check=True)
    subprocess.run(['ld','-T',str(w/'link.ld'),str(w/'test.o'),str(w/'clock.o'),'-o',str(w/'test.elf')],check=True)
    assert subprocess.check_output(['nm','-u',str(w/'test.elf')])==b''
    subprocess.run([QEMU,'-machine','virt','-cpu','cortex-a53','-m','128M','-nographic','-monitor','none','-serial','none','-semihosting-config','enable=on,target=native','-kernel',str(w/'test.elf')],check=True,timeout=10)
print('Counter success, exact-instruction EL1 traps, cache-on refusal and ABI/exception restoration: 4 passed')
