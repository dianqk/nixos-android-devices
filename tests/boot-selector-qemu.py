#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Complete policy in system QEMU, fake SPMI callbacks, real precise abort.
Explicit caller FDT/device profile. Not Qualcomm controller emulation."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import importlib.util
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('builder',ROOT/'tools/build-boot-selector.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
QEMU=os.environ.get('QEMU_SYSTEM_AARCH64','qemu-system-aarch64')
BUNDLE=Path(os.environ['SELECTOR_BUNDLE'])
INTENT=bool(os.environ.get('INTENT_PROTOTYPE'))
TEMPLATE=bool(os.environ.get('SELECTOR_TEMPLATE'))
DIAGNOSTIC=False
if TEMPLATE:
    import struct
    DESC=json.loads((BUNDLE/'template.json').read_text())
    audit=json.loads((BUNDLE/'sources.json').read_text());BIND=audit['binding'];DIAGNOSTIC=audit.get('diagnostic_stages',False)
    for source in audit['sources']:assert b.selector.digest((ROOT/source['path']).read_bytes())==source['sha256']
    syms,pristine,start,_,_=b.selector.inspect((BUNDLE/'selector.elf').read_bytes())
    assert pristine==(BUNDLE/'selector.bin').read_bytes() and b.selector.digest(pristine)==DESC['selector_sha256']
    actual=Path(os.environ['UBOOT_IMAGE']).read_bytes()
    meta=4096+struct.unpack_from('<I',actual,8)[0]-4096
    BIND['request_generation']=actual[meta+128:meta+160].hex()
    parameter_at=4096+start+DESC['entry_parameters'];PARAMETERS=actual[parameter_at:parameter_at+32]
    BIND['symbols']['eg_android_entry']=struct.unpack_from('<Q',PARAMETERS,8)[0]
else:
    BIND=json.loads((BUNDLE/'manifest.json').read_text())['binding']
    b.selector.validate(BUNDLE,{'public':b.PUBLIC},BIND)
FDT=Path(os.environ['SELECTOR_FDT'])
MOCK='''
#include "spmi-observer.h"
unsigned calls;
static uint64_t ticks;
int eg_clock_read(uint64_t *hz,uint64_t *now) {
 *hz=MODE==17?0:1000;
 if(MODE!=18) ticks+=10;
 *now=ticks; return MODE!=19;
}
static int rd(void *c,uint64_t a,uint32_t *v) {
 (void)c; calls++;
 if(MODE==3) return eg_mmio_read32(0x20000000,v);
 if(a==0xc400000) *v=0x70000000;
 else if(a==0xc400004) *v=2;
 else if(a==0xc402000) *v=0x1301;
 else if(a==0xc402004) *v=0x18d01;
 else if(a==0xc42d000 || a==0xc42d004) *v=0;
 else if(a==0xc440008 || a==0xc440028) *v=MODE==2?0:1;
 else if(a==0xc440018) *v=MODE==20?0x80:MODE==21 && ticks<500?0xc0:
    ((MODE==0 || MODE==13 || MODE==14) && ticks>=500 && ticks<1000)?0x40:0;
 else if(a==0xc440038) *v=((MODE==12 || MODE==14 || MODE==24) && ticks>=500 && ticks<1000)?0:1;
 else return 0;
 return 1;
}
static int wr(void *c,uint64_t a,uint32_t v) { (void)c;(void)a;(void)v;calls++;return 1; }
extern unsigned dodge_select(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,const struct eg_spmi_io *);
unsigned eg_bootstrap_policy(uint64_t f,uint64_t i,uint64_t n,uint64_t w,uint64_t z) {
 struct eg_spmi_io io={.read=rd,.write=wr,.core=0xc400000,.config=0xc42d000,.observer=0xc440000};
 return dodge_select(f,i,n,w,z,&io);
}
'''
def run_case(mode,base):
    with tempfile.TemporaryDirectory() as d:
        w=Path(d);objects=b.compile_objects(w,extra=['-DEG_RUNTIME_TEMPLATE'] if TEMPLATE else [],policy_flags=['-Deg_bootstrap_policy=eg_hardware_policy']+(['-DDODGE_INTENT_PROTOTYPE'] if INTENT else [])+(['-DDODGE_DIAGNOSTIC_STAGES'] if DIAGNOSTIC else []),clock_flags=['-Deg_clock_read=eg_hardware_clock'])
        mock=MOCK
        if INTENT:
            mock=mock.replace('const struct eg_spmi_io *);','const struct eg_spmi_io *,uint64_t *);').replace('uint64_t z) {','uint64_t z,uint64_t *out) {').replace('w,z,&io);','''w,z,&io,out);
 unsigned first=result; uint64_t saved=*out;
 *out=0xdeadbeef;
 if(dodge_select(0,i,n,w,z,&io,out)!=0 || *out!=0)return 0;
 ticks=0;calls=0;*out=0xdeadbeef;
 unsigned second=dodge_select(f,i,n,w,z,&io,out);
 if(first!=second || saved!=*out)return 0;
 return second;''').replace('return dodge_select(f,i,n,w,z,&io,out);','unsigned result=dodge_select(f,i,n,w,z,&io,out);')
        (w/'mock.c').write_text(mock)
        subprocess.run(['cc',*b.FLAGS,'-DMODE='+str(mode),'-I'+str(b.PUBLIC/'tools/early-entry'),'-c',str(w/'mock.c'),'-o',str(w/'mock.o')],check=True)
        # No implicit BSS: materialize the mock's call counter for the raw loader.
        link=b.linker(BIND).replace('*(.data.*)','*(.bss*) *(COMMON) *(.data.*)')
        (w/'link.ld').write_text(link)
        subprocess.run(['ld','--emit-relocs','-T',str(w/'link.ld'),*objects,str(w/'mock.o'),'-o',str(w/'policy.elf')],check=True,stderr=subprocess.DEVNULL)
        tested_elf=(BUNDLE/'selector.elf').read_bytes() if mode==29 else (w/'policy.elf').read_bytes()
        syms,raw,start,end,_=b.selector.inspect(tested_elf)
        if mode==29: assert raw==(BUNDLE/'selector.bin').read_bytes(), 'production raw mismatch'
        if TEMPLATE:
            mutable=bytearray(raw)
            p=syms['eg_runtime_parameters']-start;g=syms['eg_request_generation']-start
            mutable[p:p+32]=PARAMETERS;mutable[g:g+32]=bytes.fromhex(BIND['request_generation'])
            fault=os.environ.get('RUNTIME_PARAMETER_FAULT')
            if fault:
                import struct
                if fault=='magic':mutable[p]^=1
                elif fault=='inverse':mutable[p+16]^=1
                elif fault=='stored':struct.pack_into('<Q',mutable,p+24,DESC['pages']+1)
                else:
                    value={'zero':0,'alignment':65,'outside':struct.unpack_from('<Q',PARAMETERS,24)[0]+4}[fault]
                    struct.pack_into('<QQ',mutable,p+8,value,(~value)&((1<<64)-1))
            raw=bytes(mutable)
            if mode==29 and not fault:assert raw==actual[4096+start:4096+start+len(raw)], 'native patch differs from allowed data fields'
        (w/'policy.bin').write_bytes(raw)
        blob=w/'fdt.dtb';blob.write_bytes(FDT.read_bytes())
        # Synthetic explicit descriptor for emulation only. The actual capture
        # lacks one; mode16 verifies actual untouched FDT falls back before I/O.
        if mode not in (16,25,26,27,28,29):
            def put(node,prop,*values,kind='x'):
                subprocess.run(['fdtput','-t',kind,str(blob),node,prop,*map(str,values)],check=True)
            subprocess.run(['fdtput','-c',str(blob),'/chosen/framebuffer@fc800000'],check=True)
            put('/chosen','#address-cells',2);put('/chosen','#size-cells',2)
            node='/chosen/framebuffer@fc800000'
            put(node,'compatible','simple-framebuffer',kind='s')
            put(node,'reg',0,f'{base+0x1000000:x}' if mode==23 else 'fc800000',0,'1167000')
            for prop,value in [('width','5a0'),('height','c60'),('stride','1680')]:put(node,prop,value)
            put(node,'format','a8r8g8b8',kind='s')
        if mode in (22,27,28):
            bootmode='recovery' if mode==22 else 'normal'
            args=subprocess.check_output(['fdtget','-t','s',str(blob),'/chosen','bootargs'],text=True).rstrip('\n')
            assert args.count('oplusboot.mode=reboot')==1
            args=args.replace('oplusboot.mode=reboot','oplusboot.mode='+bootmode)
            subprocess.run(['fdtput','-t','s',str(blob),'/chosen','bootargs',args],check=True)
        if mode==5:subprocess.run(['fdtput','-t','x',str(blob),'/memory','reg','0','0x81960000','0','0x1000'],check=True)
        if INTENT:
            import struct
            # Raw generic vendor build-time assignments; runtime slot append
            # and checksum/trailer remain SYNTHETIC, not an OEM initrd capture.
            text=(b.PUBLIC/'tests/fixtures/bootconfig-flat.conf').read_bytes()
            text+=b'androidboot.slot_suffix = '+(b'"_a"' if mode%2 else b'_a')+b'\n\0'
            if mode==34:
                # Linux stops at NUL; checksummed opaque tail must not supply
                # a conflicting slot or prevent an admitted U-Boot route.
                text+=b'\xb7androidboot.slot_suffix=_b\n'
            initrd=b'ramfs'+text+struct.pack('<II',len(text),sum(text))+b'#BOOTCONFIG\n'
            if mode==31:initrd=initrd[:-16]+bytes([initrd[-16]^1])+initrd[-15:]
            (w/'initrd').write_bytes(initrd)
            put('/chosen','linux,initrd-start',0,'be800000')
            put('/chosen','linux,initrd-end',0,f'{0xbe800000+len(initrd):x}')
        if INTENT and mode in (32,33):
            if mode==32:
                subprocess.run(['fdtput','-c',str(blob),'/reserved-memory/intent-workspace-collision'],check=True)
                put('/reserved-memory/intent-workspace-collision','reg',0,f'{base+BIND["symbols"]["eg_fdt_workspace"]:x}',0,'200000')
            else:
                put('/chosen','linux,initrd-start',0,f'{base+BIND["symbols"]["eg_fdt_workspace"]:x}')
                put('/chosen','linux,initrd-end',0,f'{base+BIND["symbols"]["eg_fdt_workspace"]+4096:x}')
        selected=mode in (0,1,7,11,13,16,21,25,27); expect_calls=mode not in (4,5,22,23)
        if INTENT:
            selected=mode in (0,1,13,34)
            if mode in (31,32,33):expect_calls=False
        offset=4096+BIND['symbols']['eg_request_pages']
        source=Path(os.environ.get('ANDROID_IMAGE', os.environ['UBOOT_IMAGE'])) if mode in (6,13,14,26,28) else Path(os.environ.get('UBOOT_IMAGE',os.environ['UBOOT_IMAGE']))
        if INTENT:
            import struct,zlib
            pages=bytearray(8192);pages[:8]=b'BOOTREQ1';struct.pack_into('<I',pages,8,1);pages[12:44]=bytes.fromhex(BIND['request_generation']);struct.pack_into('<QII',pages,44,7,0 if mode in (6,13) else 1,0);struct.pack_into('<I',pages,60,zlib.crc32(pages[:4096]))
        else:pages=bytearray(source.read_bytes()[offset:offset+8192])
        if mode==7:pages[:]=bytes(8192) # absent differs from corrupt
        if mode==8:pages[60]^=1 # CRC
        if mode==9:pages[12]^=1 # generation (recompute CRC)
        if mode==10:pages[44:52]=bytes(8) # zero sequence
        if mode==11: # corrupt newer page still preserves valid older U-Boot
            pages[4096:]=pages[:4096];pages[4096+60]^=1
        if mode==15: # equal sequence, different valid targets => Android
            import struct,zlib
            pages[4096:]=pages[:4096];struct.pack_into('<I',pages,4096+52,0)
            pages[4096+60:4096+64]=bytes(4);struct.pack_into('<I',pages,4096+60,zlib.crc32(pages[4096:]))
        if mode in (9,10):
            import zlib,struct
            pages[60:64]=bytes(4);struct.pack_into('<I',pages,60,zlib.crc32(pages[:4096]))
        (w/'pages.bin').write_bytes(pages)
        entry=base+start;android=base+BIND['symbols']['eg_android_entry'];uboot=base+BIND['symbols']['embedded_uboot'];stack=base+BIND['symbols']['uboot_stack_top'];calls=base+syms.get('calls',0)
        fb_check=''
        if mode in (0,1,6,7,8,9,10,11,12,13,14,15,16,21,24,25,26,27,28,34):
            pixel=0xfc800000+(1472+(0 if (mode in (0,1,13,34) if INTENT else selected) else 80))*5760+464*4
            fb_check=f'ldr x9,={pixel}\n ldr w9,[x9]\n cmn w9,#1\n b.ne fail\n ldr x9,=0xfc800000\n ldr w9,[x9]\n mov w10,#0x5a5a\n movk w10,#0x5a5a,lsl #16\n cmp w9,w10\n b.ne fail'
        if DIAGNOSTIC and mode in (2,17,19,29,31):
            # Admitted diagnostics dirty only the validated center; caller's
            # original x0/exception registers still checked below.
            pixel=0xfc800000+1563*5760+516*4
            fb_check=f'ldr x9,={pixel}\n ldr w9,[x9]\n cmn w9,#1\n b.ne fail'
        if DIAGNOSTIC and mode==31:
            # Corrupt checksum: detailed code06 begins with glyph0 at this
            # independently calculated pixel below the main marker. Original
            # Android x0/register restoration and no observer access still hold.
            pixel=0xfc800000+1627*5760+460*4
            fb_check+=f'\n ldr x9,={pixel}\n ldr w9,[x9]\n cmn w9,#1\n b.ne fail'
        if DIAGNOSTIC and mode in (22,32,33):
            pixel=0xfc800000+1563*5760+516*4
            fb_check=f'ldr x9,={pixel}\n ldr w9,[x9]\n mov w10,#0x5a5a\n movk w10,#0x5a5a,lsl #16\n cmp w9,w10\n b.ne fail'
        calls_check='' if mode==29 else f'ldr x9,={calls}\n ldr w9,[x9]\n {"cbz" if expect_calls else "cbnz"} w9,fail'
        token_check=''
        if INTENT and selected:
            # First chosen property is the inserted token. Verify every wire
            # field including CRC against independently generated expected bytes.
            import struct,zlib
            data=blob.read_bytes();at=data.index(b'chosen\0');token_at=((at+7+3)&~3)+12
            expected=bytearray(80);expected[:8]=b'BCINTENT';struct.pack_into('<II',expected,8,1,80);expected[16:48]=bytes.fromhex(BIND['request_generation'])
            stored=0 if mode==13 else 1;choice=0 if mode==12 else 1
            struct.pack_into('<QIIIII',expected,48,7,stored,choice,2,1,1);struct.pack_into('<I',expected,76,zlib.crc32(expected))
            for off in range(0,80,8):
                token_check+=f'ldr x9,={base+BIND["symbols"]["eg_fdt_workspace"]+token_at+off}\n ldr x9,[x9]\n ldr x10,={int.from_bytes(expected[off:off+8],"little")}\n cmp x9,x10\n b.ne fail\n'
        asm=f'''
.section .text.start,"ax"
.global _start
_start:
 msr daifset,#15
 ldr x9,=0xfc800000
 mov w10,#0x5a5a
 movk w10,#0x5a5a,lsl #16
 str w10,[x9]
 {"ldr x9,="+str(0xfc800000+1563*5760+516*4)+"; str w10,[x9]" if DIAGNOSTIC else ""}
 mov x9,#0x30000000
 mov sp,x9
 mov x9,#0x40000000
 msr vbar_el1,x9
 mov x9,#0x1200
 msr elr_el1,x9
 mov x9,#0x3c5
 msr spsr_el1,x9
 mov x9,#0x24
 msr esr_el1,x9
 mov x9,#0x1600
 msr far_el1,x9
 ldr x0,=0xbe400000
 mov x1,#0x11
 mov x2,#0x12
 mov x3,#0x13
 mov x19,#0x1919
 mov x9,#0xa0000000
 msr nzcv,x9
 ldr x9,={entry}
 br x9
.section .text.android,"ax"
 {'b fail' if selected else 'b check'}
.section .text.uboot,"ax"
 {'b check' if selected else 'b fail'}
.section .text.check,"ax"
check:
 mrs x9,nzcv
 mov x10,#0xa0000000
 cmp x9,x10
 b.ne fail
 ldr x9,={base+BIND['symbols'].get('eg_fdt_workspace',0) if INTENT and selected else 0xbe400000}
 cmp x0,x9
 b.ne fail
 cmp x1,#0x11
 b.ne fail
 cmp x2,#0x12
 b.ne fail
 cmp x3,#0x13
 b.ne fail
 mov x9,sp
 ldr x10,={stack if selected else 0x30000000}
 cmp x9,x10
 b.ne fail
 mrs x9,daif
 cmp x9,#0x3c0
 b.ne fail
 mov x10,#0x1919
 cmp x19,x10
 b.ne fail
 mrs x9,vbar_el1
 mov x10,#0x40000000
 cmp x9,x10
 b.ne fail
 mrs x9,elr_el1
 mov x10,#0x1200
 cmp x9,x10
 b.ne fail
 mrs x9,spsr_el1
 cmp x9,#0x3c5
 b.ne fail
 mrs x9,esr_el1
 cmp x9,#0x24
 b.ne fail
 mrs x9,far_el1
 mov x10,#0x1600
 cmp x9,x10
 b.ne fail
 {calls_check}
 {fb_check}
 {token_check}
 mov x1,#0
 b exit
fail:
 mov x1,#1
exit:
 adr x2,exit_block
 str x1,[x2,#8]
 mov x1,x2
 mov x0,#0x20
 hlt #0xf000
 b .
.balign 8
exit_block:.quad 0x20026,0
'''
        # Check routine near targets so branch ranges remain valid. Raw selector
        # is identical at both runtime bases; only loader/harness changes.
        (w/'test.S').write_text(asm)
        (w/'harness.ld').write_text(f'''ENTRY(_start)
SECTIONS {{ . = 0x40080000; .start : {{ *(.text.start) }}
 . = {android}; .android : {{ *(.text.android) }}
 . = {uboot}; .uboot : {{ *(.text.uboot) }}
 .check : {{ *(.text.check) }} }}''')
        subprocess.run(['as',str(w/'test.S'),'-o',str(w/'test.o')],check=True)
        subprocess.run(['ld','-T',str(w/'harness.ld'),str(w/'test.o'),'-o',str(w/'test.elf')],check=True)
        extra=['-device',f'loader,file={w}/initrd,addr=0xbe800000,force-raw=on'] if INTENT else []
        command=[QEMU,'-machine','virt','-cpu','cortex-a53','-m','3G','-nographic','-monitor','none','-serial','none','-semihosting-config','enable=on,target=native','-kernel',str(w/'test.elf'),'-device',f'loader,file={w}/policy.bin,addr={entry},force-raw=on','-device',f'loader,file={blob},addr=0xbe400000,force-raw=on','-device',f'loader,file={w}/pages.bin,addr={base+BIND["symbols"]["eg_request_pages"]},force-raw=on']+extra
        fault=os.environ.get('RUNTIME_PARAMETER_FAULT')
        if fault:
            import re
            trace=w/'trace.log'
            try:
                subprocess.run(command+['-d','in_asm','-D',str(trace)],capture_output=True,timeout=1)
                raise AssertionError('corrupt runtime parameters reached an exit')
            except subprocess.TimeoutExpired:
                text=trace.read_text()
                assert re.search(r'^0x0*'+format(base+syms['eg_bad_runtime_parameters'],'x')+':',text,re.M),text[-2000:]
                assert not re.search(r'^0x0*'+format(base+syms['eg_bootstrap_policy'],'x')+':',text,re.M), 'policy executed before parameter refusal'
                print(f'PASS runtime parameter {fault}: park before policy at {base:#x}')
                return
        result=subprocess.run(command,capture_output=True,timeout=12)
        assert result.returncode==0,(mode,hex(base),result.returncode,result.stderr.decode())
        print(f'PASS mode={mode} image_base={base:#x} raw={b.selector.digest(raw)}')
if __name__=='__main__':
    modes=([6] if os.environ.get('RUNTIME_PARAMETER_FAULT') else [0,1,6,12,13,31,32,33,34] if INTENT else [29] if os.environ.get('PRODUCTION_SELECTOR') else range(29))
    if os.environ.get('SELECTOR_TEST_MODES'): modes=[int(x) for x in os.environ['SELECTOR_TEST_MODES'].split(',')];assert all(0<=x<=34 for x in modes)
    for mode in modes:
        for base in ([0xb5000000] if mode==4 else [0xa5000000,0xa8000000]):run_case(mode,base)
