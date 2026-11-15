#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Real AArch64 system emulation; no device, boot image or MMIO operations."""
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QEMU = os.environ.get('QEMU_SYSTEM_AARCH64', shutil.which('qemu-system-aarch64'))


@unittest.skipUnless(QEMU and shutil.which('as') and platform.machine() == 'aarch64', 'needs system QEMU and AArch64 GNU binutils')
class Bootstrap(unittest.TestCase):
    def run_case(self, mode, policy):
        # A bare-metal ELF at QEMU virt RAM; these are emulator addresses ONLY.
        setup = {'supported': '', 'sp0': 'msr spsel, #0',
                 'interrupts': 'msr daifclr, #2', 'el2': '',
                 'endian': 'mrs x9, sctlr_el1; orr x9, x9, #(1 << 25); msr sctlr_el1, x9; isb',
                 'mmu': '''adrp x9, page_table
                 add x9, x9, :lo12:page_table
                 msr ttbr0_el1, x9
                 mov x9, #0xff
                 msr mair_el1, x9
                 mov x9, #0x3519
                 msr tcr_el1, x9
                 dsb sy
                 isb
                 mrs x9, sctlr_el1
                 orr x9, x9, #1
                 msr sctlr_el1, x9
                 isb'''}[mode]
        expected_calls = int(mode == 'supported')
        helper = '''
    // Check actual image-relative mapping arguments, not just call occurrence.
    cmp x0, #0x10
    b.ne fail
    adrp x5, eg_image_start
    add x5, x5, :lo12:eg_image_start
    cmp x1, x5
    b.ne fail
    adrp x6, eg_image_end
    add x6, x6, :lo12:eg_image_end
    sub x6, x6, x5
    cmp x2, x6
    b.ne fail
    adrp x5, eg_scratch_start
    add x5, x5, :lo12:eg_scratch_start
    cmp x3, x5
    b.ne fail
    cmp x4, #16384
    b.ne fail
    mov x5, sp
    cmp x5, x3
    b.lo fail
    add x6, x3, x4
    cmp x5, x6
    b.hs fail
    adr x5, calls
    mov x6, #1
    str x6, [x5]
    // Clobber ABI caller scratch, LR and flags through a nested call.
    bl clobber
    mov x0, #0xdead
    mov x1, #0xbeef
    mov x2, #0xabcd
    mov x3, #0xeeee
    mov x10, #0
    mov x11, #0
    mov x17, #0
    mov x18, #0
    cmp x0, x0
''' if policy in ('clobber','select','invalid') else ''
        # Nested call helper uses its own AAPCS64 frame, preserving return PC.
        if policy in ('clobber','select','invalid'):
            helper += 'mov w0, #'+('1' if policy == 'select' else '2' if policy == 'invalid' else '0')+'\n'
            helper = 'stp x29, x30, [sp, #-16]!\n' + helper + 'ldp x29, x30, [sp], #16\nret\n'
        else:
            helper = 'b eg_default_policy\n'
            expected_calls = 0
        assembly = f'''
.section .text.start,"ax"
.global _start, eg_android_entry, eg_bootstrap_policy, eg_uboot_entry
_start:
    // QEMU starts at EL1h (or EL2h with virtualization enabled).
    msr daifset, #15
    // Deliberately unmapped incoming SP: Linux boot ABI grants no stack.
    mov x9, #0x60000000
    msr sp_el0, x9
    mov sp, x9
    {setup}
    mov x0, #0x10
    mov x1, #0x11
    mov x2, #0x12
    mov x3, #0x13
    mov x19, #0x1919
    adr x30, fail
    mov x9, #0xa0000000
    msr nzcv, x9
    mrs x20, daif
    mov x21, sp
    b eg_bootstrap
eg_bootstrap_policy:
    {helper}
clobber:
    ret
eg_uboot_entry:
    {'b fail' if policy != 'select' else 'b check_abi'}
eg_android_entry:
    {'b fail' if policy == 'select' else 'b check_abi'}
check_abi:
    mrs x9, nzcv
    mov x10, #0xa0000000
    cmp x9, x10
    b.ne fail
    mrs x9, CurrentEL
    cmp x9, #4
    b.ne 1f
    mrs x9, sctlr_el1
    bic x9, x9, #1
    bic x9, x9, #(1 << 25)
    msr sctlr_el1, x9
    isb
1:
    cmp x0, #0x10
    b.ne fail
    cmp x1, #0x11
    b.ne fail
    cmp x2, #0x12
    b.ne fail
    cmp x3, #0x13
    b.ne fail
    mov x9, sp
    cmp x9, x21
    b.ne fail
    mrs x9, daif
    cmp x9, x20
    b.ne fail
    adr x9, fail
    cmp x30, x9
    b.ne fail
    mov x9, #0x1919
    cmp x19, x9
    b.ne fail
    adr x9, calls
    ldr x9, [x9]
    cmp x9, #{expected_calls}
    b.ne fail
    mov x1, #0
    b exit
fail:
    mov x1, #1
exit:
    adr x2, exit_block
    str x1, [x2, #8]
    mov x1, x2
    mov x0, #0x20
    hlt #0xf000
    b .
.balign 16
calls: .quad 0
exit_block: .quad 0x20026, 0
.balign 4096
page_table: .quad 0, 0x40000701
.space 4080
'''
        linker = '''ENTRY(_start)
SECTIONS {
 . = 0x40080000; eg_image_start = .;
 .text : { *(.text.start) *(.text*) }
 .rodata : { *(.rodata*) }
 .data : { *(.data) }
 .bss : { *(.bss*) *(COMMON) }
 . = ALIGN(4096);
 /* PROGBITS is materialized, never an assumed NOBITS tail. */
 .scratch : { *(.data.eg_scratch) }
 eg_image_end = .;
 eg_workspace_start = eg_scratch_start;
 eg_workspace_end = eg_scratch_end;
 ASSERT(eg_scratch_end - eg_scratch_start == 16384, "scratch size")
 /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / 'test.S').write_text(assembly)
            (work / 'link.ld').write_text(linker)
            for source, name in ((work / 'test.S', 'test'),
                                 (ROOT / 'tools/early-entry/bootstrap.S', 'bootstrap'),
                                 (ROOT / 'tools/early-entry/bootstrap-scratch.S', 'scratch')):
                subprocess.run(['as', str(source), '-o', str(work / (name + '.o'))], check=True)
            subprocess.run(['clang', '-ffreestanding', '-mgeneral-regs-only', '-fno-stack-protector',
                            '-O2', '-Deg_bootstrap_policy=eg_default_policy', '-c',
                            str(ROOT / 'tools/early-entry/bootstrap-policy.c'),
                            '-o', str(work / 'policy.o')], check=True)
            elf = work / 'test.elf'
            subprocess.run(['ld', '-T', str(work / 'link.ld'), str(work / 'test.o'),
                            str(work / 'bootstrap.o'), str(work / 'scratch.o'), str(work / 'policy.o'), '-o', str(elf)], check=True)
            listing = subprocess.check_output(['objdump', '-d', str(elf)], text=True)
            self.assertIn('sctlr_el1', listing)
            self.assertIn('msr\tnzcv', listing)
            sections = subprocess.check_output(['objdump', '-h', str(elf)], text=True)
            self.assertIn('.scratch', sections)
            self.assertEqual(subprocess.check_output(['nm', '-u', str(elf)], text=True), '')
            raw = work / 'test.bin'
            subprocess.run(['objcopy', '-O', 'binary', str(elf), str(raw)], check=True)
            # A real byte-backed suffix, not merely an advertised NOBITS extent.
            self.assertEqual(raw.read_bytes()[-16384:], bytes(16384))
            machine = 'virt,virtualization=on' if mode == 'el2' else 'virt'
            result = subprocess.run([QEMU, '-machine', machine, '-cpu', 'cortex-a53',
                                     '-m', '128M', '-nographic', '-monitor', 'none',
                                     '-serial', 'none', '-semihosting-config', 'enable=on,target=native',
                                     '-kernel', str(elf)], timeout=10, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_supported_clobber_restore(self):
        self.run_case('supported', 'clobber')

    def test_explicit_selection_reachable(self):
        self.run_case('supported', 'select')

    def test_invalid_nonzero_result_rejected(self):
        self.run_case('supported', 'invalid')

    def test_no_profile_policy(self):
        self.run_case('supported', 'default')

    def test_sp0_rejected_without_stack_write(self):
        self.run_case('sp0', 'clobber')

    def test_unmasked_interrupts_rejected(self):
        self.run_case('interrupts', 'clobber')

    def test_mmu_on_rejected(self):
        self.run_case('mmu', 'clobber')

    def test_big_endian_data_rejected(self):
        self.run_case('endian', 'clobber')

    def test_el2_rejected(self):
        self.run_case('el2', 'clobber')


if __name__ == '__main__':
    unittest.main()
