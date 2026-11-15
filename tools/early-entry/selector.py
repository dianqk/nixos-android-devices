# SPDX-License-Identifier: GPL-2.0-only
"""Validate an explicitly supplied, source-bound offline selector (not authentication)."""
import hashlib
import json
from pathlib import Path
import struct

def digest(b): return hashlib.sha256(b).hexdigest()
def require(ok, why):
    if not ok: raise ValueError(why)

def inspect(elf):
    require(elf[:7] == b'\x7fELF\x02\x01\x01' and struct.unpack_from('<H',elf,18)[0]==183, 'selector must be AArch64 ELF64 LE')
    off=struct.unpack_from('<Q',elf,40)[0]; size,count,names=struct.unpack_from('<HHH',elf,58)
    require(size==64 and 0<count<256 and names<count, 'selector section table')
    def span(at,n):
        require(0<=at<=len(elf) and 0<=n<=len(elf)-at,'selector ELF bounds'); return elf[at:at+n]
    h=[struct.unpack('<IIQQQQIIQQ',span(off+i*64,64)) for i in range(count)]
    strings=span(h[names][4],h[names][5])
    def string(data,at):
        require(at<len(data) and b'\0' in data[at:],'selector ELF string');return data[at:].split(b'\0',1)[0].decode('ascii')
    sections={string(strings,x[0]):(x,span(x[4],x[5]) if x[1]!=8 else b'') for x in h}
    sh,data=sections['.symtab']; require(sh[9]==24 and len(data)%24==0 and sh[6]<count,'selector symbols')
    strs=span(h[sh[6]][4],h[sh[6]][5]); syms={}
    for at in range(0,len(data),24):
        name,info,_,idx,value,_=struct.unpack_from('<IBBHQQ',data,at)
        if not idx:
            require(not name or info>>4==0,'undefined selector symbol')
        else: syms[string(strs,name)]=value
    # Final emitted relocation audit: only page-relative/PC-relative code forms.
    # Low12 relocations are invariant only for page-aligned runtime Image bases.
    allowed={273,274,275,276,277,278,279,280,282,283,284,285,286,299}
    relocations=0
    for name,(sh,data) in sections.items():
        require(not(name.startswith('.got') or name.startswith('.dynamic')),'selector GOT/dynamic forbidden')
        if sh[1] in (4,9):
            require(sh[1]==4 and sh[9]==24 and len(data)%24==0,'selector relocation format')
            for at in range(0,len(data),24):
                _,info,_=struct.unpack_from('<QQq',data,at)
                require(info&0xffffffff in allowed,'absolute/unsupported selector relocation'); relocations+=1
    require(relocations>0,'selector must retain relocation audit records')
    alloc=[(sh,data) for sh,data in sections.values() if sh[2]&2 and sh[5]]
    require(alloc and all(sh[1]!=8 for sh,_ in alloc),'selector must materialize every allocation')
    start=min(sh[3] for sh,_ in alloc);end=max(sh[3]+sh[5] for sh,_ in alloc)
    require(0<end-start<2*1024*1024,'selector extent')
    raw=bytearray(end-start); used=[]
    for sh,data in alloc:
        a,b=sh[3],sh[3]+sh[5]
        require(all(b<=x or a>=y for x,y in used),'selector section overlap');used.append((a,b))
        raw[a-start:b-start]=data
    return syms,bytes(raw),start,end,struct.unpack_from('<Q',elf,24)[0]

def validate(directory, roots, expected):
    directory=Path(directory)
    require(not directory.is_symlink(),'selector directory alias')
    def read(name):
        p=directory/name;require(p.is_file() and not p.is_symlink() and p.stat().st_size<16*1024*1024,'selector file');return p.read_bytes()
    manifest=json.loads(read('manifest.json'));elf=read('selector.elf');raw=read('selector.bin')
    require(manifest['format']=='EARLY-SELECTOR-V1','selector manifest format')
    require(manifest['elf_sha256']==digest(elf) and manifest['raw_sha256']==digest(raw),'selector manifest hash mismatch')
    require(manifest['binding']==expected,'selector input binding mismatch')
    require(manifest['sources'] and roots,'explicit selector source roots required')
    for entry in manifest['sources']:
        rel=Path(entry['path']);require(not rel.is_absolute() and '..' not in rel.parts,'selector source path')
        root=Path(roots[entry['root']]).resolve();path=(root/rel).resolve()
        require(path.is_relative_to(root) and digest(path.read_bytes())==entry['sha256'],'selector source mismatch')
    syms,reconstructed,start,end,entry=inspect(elf)
    require(reconstructed==raw,'selector ELF/raw mismatch')
    require(manifest['symbols']=={k:syms[k] for k in manifest['symbols']},'selector manifest symbol mismatch')
    for key,value in expected['symbols'].items(): require(syms[key]==value,'selector layout symbol mismatch: '+key)
    require(start==expected['symbols']['eg_request_pages']+8192 and end==syms['eg_scratch_end'] and entry==syms['eg_bootstrap'],'selector entry/extent')
    require(syms['eg_scratch_end']-syms['eg_scratch_start']==16384 and syms['eg_scratch_end']<=syms['embedded_uboot'],'selector stack/payload overlap')
    require(raw[syms['eg_scratch_start']-start:]==bytes(16384),'selector scratch not materialized')
    return raw,syms,manifest
