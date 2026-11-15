#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build a complete offline source-bound selector; no device operations."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
PUBLIC=ROOT
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
experiment=load('experiment',PUBLIC/'tools/boot-image-experiment.py')
selector=load('selector',PUBLIC/'tools/early-entry/selector.py')
FLAGS=['-O2','-ffreestanding','-fpie','-fvisibility=hidden','-fno-builtin','-fno-stack-protector','-fno-asynchronous-unwind-tables','-fno-unwind-tables','-fno-jump-tables','-mgeneral-regs-only','-mstrict-align','-Wall','-Wextra','-Werror']
SOURCES=[('public','tools/early-entry/'+p) for p in ['bootstrap.S','bootstrap-scratch.S','fdt-guard.c','spmi-observer.c','mmio.S','memory.c','boot-choice.c','draw.c','clock.S','request-observe.c','commit-intent.c','fdt-intent.c','bootconfig.c','menu.c','intent-selection.c','uboot-entry.S']]+[('public','tools/early-entry/adapters/dodge/policy.c')]
HEADERS=[('public','tools/early-entry/'+p) for p in ['fdt-guard.h','spmi-observer.h','boot-choice.h','draw.h','commit-intent.h','bootconfig.h','menu.h','intent-selection.h','runtime-template.h']]+[('public','tools/early-entry/adapters/dodge/'+p) for p in ['profile.h','dynamic.h','display.h','paint.h']]+[('public',p) for p in ['tools/build-boot-selector.py','tools/boot-image-experiment.py','tools/early-entry/selector.py','tools/owned-layout.py']]
CC=os.environ.get('CC','cc');LD=os.environ.get('LD','ld');OBJCOPY=os.environ.get('OBJCOPY','objcopy')
def compile_objects(work, extra=(), policy_flags=(), clock_flags=()):
    objects=[]
    for i,(root,path) in enumerate(SOURCES):
        source=PUBLIC/path;out=work/f'{i}.o'
        flags=FLAGS+list(extra)+(list(policy_flags) if path.endswith('/policy.c') else list(clock_flags) if path.endswith('/clock.S') else [])
        if path.endswith('/draw.c') and '-DDODGE_DIAGNOSTIC_STAGES' in policy_flags: flags+=['-DDODGE_DIAGNOSTIC_STAGES']
        subprocess.run([CC,*flags,'-I'+str(PUBLIC/'tools/early-entry'),'-I'+str(PUBLIC/'tools/early-entry/adapters/dodge'),'-c',str(source),'-o',str(out)],check=True);objects.append(str(out))
    return objects

def linker(binding):
    s=binding['symbols']; assignments='\n'.join(f'{k} = {v};' for k,v in s.items())
    return f'''ENTRY(eg_bootstrap)
{assignments}
SECTIONS {{
 . = eg_request_pages + 8192;
 .text : {{ KEEP(*(.text.bootstrap)) *(.text*) }}
 .rodata : {{ *(.rodata*) . = ALIGN(16); eg_request_generation = .; {''.join('BYTE('+str(v)+');' for v in bytes.fromhex(binding['request_generation']))} }}
 .data : {{ *(.data) *(.data.*) }}
 .bss : {{ *(.bss*) *(COMMON) }}
 ASSERT(SIZEOF(.bss)==0, "implicit bss forbidden")
 /DISCARD/ : {{ *(.comment) *(.note*) *(.eh_frame*) }}
 ASSERT(eg_scratch_end <= embedded_uboot, "selector too large")
 ASSERT(eg_scratch_end-eg_scratch_start == 16384, "scratch size")
}}
'''

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adapter',choices=['dodge'],required=True,help='explicit device admission adapter')
    p.add_argument('--original',type=Path)
    p.add_argument('--export-template',action='store_true',help='export a compiler-free bounded native installation template (no baseline image)')
    for name in ('payload','elf','config','output-dir'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--diagnostic-stages',action='store_true',help='Dodge diagnostic-only visible admitted-stage errors; requires intent prototype')
    p.add_argument('--intent-prototype',action='store_true',help='host-only connected producer; no consumer/deployment authority')
    p.add_argument('--efi-helper',type=Path,help='matched host-built transactional EFI application; records digest, does not approve hardware')
    p.add_argument('--owned-runnable',action='store_true')
    a=p.parse_args()
    if a.diagnostic_stages and not a.intent_prototype:p.error("diagnostic stages require intent prototype")
    if a.export_template:
        export_template(a);return
    if not a.original:p.error('--original required unless --export-template')
    original,raw,elf,config=[experiment.c.read_regular(getattr(a,n),experiment.c.LIMIT) for n in ('original','payload','elf','config')]
    if a.efi_helper and not a.intent_prototype:p.error('--efi-helper requires --intent-prototype')
    helper=experiment.c.read_regular(a.efi_helper,experiment.c.LIMIT) if a.efi_helper else None
    info=experiment.c.boot4(original);abi=experiment.elf_layout(elf,raw,config)
    binding=experiment.selector_binding(original,raw,elf,config,info,abi,'intent' if a.intent_prototype else a.owned_runnable)
    with tempfile.TemporaryDirectory() as d:
        w=Path(d);objects=compile_objects(w,policy_flags=(['-DDODGE_INTENT_PROTOTYPE'] if a.intent_prototype else [])+(['-DDODGE_DIAGNOSTIC_STAGES'] if a.diagnostic_stages else []));(w/'link.ld').write_text(linker(binding))
        out=w/'selector.elf';subprocess.run([LD,'--emit-relocs','-T',str(w/'link.ld'),*objects,'-o',str(out)],check=True)
        subprocess.run([OBJCOPY,'-O','binary',str(out),str(w/'selector.bin')],check=True)
        syms,reconstructed,_,_,_=selector.inspect(out.read_bytes());assert reconstructed==(w/'selector.bin').read_bytes()
        tracked={}
        try:
            revision=subprocess.run(['git','-C',str(PUBLIC),'rev-parse','HEAD'],capture_output=True,text=True)
            tracked['public']=revision.stdout.strip() if revision.returncode==0 else None
        except OSError:
            tracked['public']=None # installed tool has source hashes, not a .git checkout
        sources=[{'root':r,'path':path,'sha256':selector.digest((PUBLIC/path).read_bytes())} for r,path in SOURCES+HEADERS]
        manifest={'deployment':('host validated candidate: requires matched EFI helper on ESP and controlled deployment trial' if helper else 'forbidden: missing transactional EFI adapter on ESP') if a.intent_prototype else 'legacy selector', 'efi_helper_sha256':selector.digest(helper) if helper else None, 'format':'EARLY-SELECTOR-V1','binding':binding,'symbols':{k:syms[k] for k in list(binding['symbols'])+['eg_bootstrap','eg_scratch_start','eg_scratch_end','eg_uboot_entry','eg_bootstrap_policy']},'elf_sha256':selector.digest(out.read_bytes()),'raw_sha256':selector.digest(reconstructed),'sources':sources,'git_revisions':tracked,'compiler':subprocess.check_output([CC,'--version'],text=True).splitlines()[0],'flags':FLAGS,'policy_flags':(['-DDODGE_INTENT_PROTOTYPE'] if a.intent_prototype else [])+(['-DDODGE_DIAGNOSTIC_STAGES'] if a.diagnostic_stages else []),'link_flags':['--emit-relocs'],'trust':'integrity/source binding only; not authentication or hardware approval'}
        a.output_dir.mkdir(mode=0o700)
        for name in ['selector.elf','selector.bin']:experiment.c.write_new(a.output_dir/name,(w/name).read_bytes())
        experiment.c.write_new(a.output_dir/'manifest.json',(json.dumps(manifest,indent=2)+'\n').encode())
        selector.validate(a.output_dir,{'public':PUBLIC},binding)
        print(json.dumps({'directory':str(a.output_dir),'bytes':len(reconstructed),'binding':binding},indent=2))
def export_template(a):
    """Fixed linked allocation, independent of baseline bytes/hash/entry/length.

    All changing baseline facts are data; original +4 B and Image/BOOT size
    headers are the only instruction/header edits during native packing.
    """
    if a.original or not a.efi_helper or not a.intent_prototype:
        raise ValueError('template requires --intent-prototype --efi-helper and NO --original')
    raw,elf,config=[experiment.c.read_regular(getattr(a,n),experiment.c.LIMIT) for n in ('payload','elf','config')]
    helper=experiment.c.read_regular(a.efi_helper,experiment.c.LIMIT)
    abi=experiment.elf_layout(elf,raw,config)
    if abi.get('consumer_abi')!=1:raise ValueError('checked native context ABI required')
    pages=48*1024*1024
    payload=experiment.c.align(pages+8192+65536)
    native_end=experiment.c.align(payload+abi['stack_offset'])
    archive=native_end+2*1024*1024
    end=archive+16*1024*1024+4096
    binding={'request_generation':'00'*32,'symbols':{
        'eg_image_start':0,'eg_image_end':end,'eg_workspace_start':pages,
        'eg_workspace_end':end,'eg_request_pages':pages,'eg_android_entry':0,
        'embedded_uboot':payload,'uboot_stack_top':payload+abi['stack_offset'],
        'eg_fdt_workspace':native_end,'eg_fdt_workspace_end':archive}}
    a.output_dir.mkdir(mode=0o700)
    with tempfile.TemporaryDirectory() as d:
        w=Path(d);objects=compile_objects(w,extra=['-DEG_RUNTIME_TEMPLATE'],policy_flags=['-DDODGE_INTENT_PROTOTYPE']+(['-DDODGE_DIAGNOSTIC_STAGES'] if a.diagnostic_stages else []))
        (w/'link.ld').write_text(linker(binding));out=w/'selector.elf'
        subprocess.run([LD,'--emit-relocs','-T',str(w/'link.ld'),*objects,'-o',str(out)],check=True)
        subprocess.run([OBJCOPY,'-O','binary',str(out),str(w/'selector.bin')],check=True)
        syms,code,start,_,_=selector.inspect(out.read_bytes())
        assert start==pages+8192 and code==(w/'selector.bin').read_bytes()
        assert syms['eg_scratch_end']<=payload
        assert syms['eg_runtime_parameters']-syms['eg_request_generation']==32, 'runtime data ABI adjacency'
        manifest={'schema':1,'profile':'dodge','pages':pages,'payload':payload,
                  'native_end':native_end,'archive':archive,'image_end':end,
                  'stack_offset':abi['stack_offset'],'raw_length':len(raw),
                  'entry_parameters':syms['eg_runtime_parameters']-start,
                  'generation_data':syms['eg_request_generation']-start,
                  'selector_sha256':selector.digest(code),'raw_sha256':selector.digest(raw),
                  'elf_sha256':selector.digest(elf),'config_sha256':selector.digest(config),
                  'helper_sha256':selector.digest(helper)}
        for name,data in [('selector.bin',code),('selector.elf',out.read_bytes()),('firmware.bin',raw),('firmware.elf',elf),('firmware.config',config),('boot-choice.efi',helper)]:
            experiment.c.write_new(a.output_dir/name,data)
        experiment.c.write_new(a.output_dir/'template.json',(json.dumps(manifest,indent=2)+'\n').encode())
        audit={'format':'BOOT-CHOICE-TEMPLATE-SOURCES-V1','symbols':syms,'diagnostic_stages':a.diagnostic_stages,
               'binding':binding,'compiler':subprocess.check_output([CC,'--version'],text=True).splitlines()[0],
               'sources':[{'root':r,'path':p,'sha256':selector.digest((PUBLIC/p).read_bytes())} for r,p in SOURCES+HEADERS]}
        experiment.c.write_new(a.output_dir/'sources.json',(json.dumps(audit,indent=2)+'\n').encode())
        print(json.dumps(manifest,indent=2))

if __name__=='__main__':main()
