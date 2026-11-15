#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""OFFLINE experimental BOOT4 embedding. Not hardware accepted or safe to flash."""
import argparse
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import hashlib
import zlib

_spec = importlib.util.spec_from_file_location('carrier', Path(__file__).with_name('boot-image-carrier.py'))
c = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c)
require = c.require
_spec = importlib.util.spec_from_file_location("owned_layout", Path(__file__).with_name("owned-layout.py"))
owned_layout = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(owned_layout)


def elf_layout(elf, raw, config):
    """Reconstruct U-Boot's selected sections + RELATIVE fixups + separate DTB.

    Matches the U-Boot Makefile OBJCOPYFLAGS and tools/relocate-rela.c contract;
    no build manifest or externally supplied symbol offsets are trusted.
    """
    require(elf[:7] == b'\x7fELF\x02\x01\x01', 'need ELF64 little endian')
    require(struct.unpack_from('<H', elf, 18)[0] == 183, 'need AArch64 ELF')
    entry = struct.unpack_from('<Q', elf, 24)[0]
    off = struct.unpack_from('<Q', elf, 40)[0]
    entsize, count, names = struct.unpack_from('<HHH', elf, 58)
    require(entsize == 64 and 0 < count < 256 and names < count, 'unsupported ELF sections')
    table = c.span(elf, off, count * 64, 'ELF section table')
    headers = [struct.unpack_from('<IIQQQQIIQQ', table, i * 64) for i in range(count)]
    strings = c.span(elf, headers[names][4], headers[names][5], 'section strings')
    sections = {}
    for h in headers:
        require(h[0] < len(strings), 'section name out of bounds')
        name = strings[h[0]:].split(b'\0', 1)[0].decode('ascii')
        sections[name] = (h, c.span(elf, h[4], h[5], name))
    syms = {}
    h, data = sections['.symtab']
    require(h[9] == 24 and h[6] < count and len(data) % 24 == 0, 'bad symbol table')
    sh = headers[h[6]]
    strings = c.span(elf, sh[4], sh[5], 'symbol strings')
    for at in range(0, len(data), 24):
        name, _, _, section, value, _ = struct.unpack_from('<IBBHQQ', data, at)
        require(name < len(strings), 'bad symbol name')
        if section:
            syms[strings[name:].split(b'\0', 1)[0].decode('ascii')] = value
    require(syms['_start'] == entry, 'ELF entry differs from _start')
    selected = {'.text', '.secure_text', '.secure_data', '.rodata', '.data',
                '__u_boot_list', '.rela.dyn', '.got', '.got.plt', '.binman_sym_table',
                '.text_rest', '.dtb.init.rodata', '.efi_runtime', '.efi_runtime_rel'}
    end = max(h[3] + h[5] for name, (h, _) in sections.items() if name in selected)
    require(0 < end - entry <= c.LIMIT, 'ELF load extent invalid')
    binary = bytearray(b'\xff' * (end - entry))
    for name, (h, data) in sections.items():
        if name in selected:
            at = h[3] - entry
            require(0 <= at <= len(binary) - len(data), 'ELF section outside image')
            binary[at:at + len(data)] = data
    rela = sections['.rela.dyn'][1]
    require(len(rela) % 24 == 0, 'bad RELA size')
    for at in range(0, len(rela), 24):
        target, info, addend = struct.unpack_from('<QQQ', rela, at)
        require(info == 1027, 'only symbol-free AArch64 RELATIVE relocations supported')
        target -= entry
        require(0 <= target <= len(binary) - 8, 'relocation outside raw image')
        struct.pack_into('<Q', binary, target, addend)
    require(raw[:len(binary)] == binary, 'raw payload does not match relocated ELF')
    dtb = raw[len(binary):]
    require(len(dtb) >= 40 and dtb[:4] == b'\xd0\x0d\xfe\xed' and
            struct.unpack_from('>I', dtb, 4)[0] == len(dtb), 'need exact appended separate DTB')
    cfg = dict(line.split('=', 1) for line in config.decode().splitlines()
               if line.startswith('CONFIG_') and '=' in line)
    for key in ('ARM64', 'POSITION_INDEPENDENT', 'OF_SEPARATE', 'SAVE_PREV_BL_FDT_ADDR'):
        require(cfg.get('CONFIG_' + key) == 'y', 'unsupported config: ' + key)
    for key in ('ARMV8_MULTIENTRY', 'ARMV8_SWITCH_TO_EL1', 'BLOBLIST'):
        require(cfg.get('CONFIG_' + key) != 'y', 'unsupported config: ' + key)
    require(int(cfg['CONFIG_TEXT_BASE'], 0) == entry, 'config/ELF text base mismatch')
    bss = syms['__bss_start'] - entry
    stack = bss + int(cfg['CONFIG_SYS_INIT_SP_BSS_OFFSET'], 0)
    require(0 < bss <= syms['__bss_end'] - entry <= stack and stack % 16 == 0,
            'invalid BSS/initial stack envelope')
    require(max(len(raw), syms['_end'] - entry) <= stack == c.arm64(raw)['image_size'],
            'resolved workspace disagrees with raw Image size')
    consumer = syms.get('android_devices_boot_choice_context_abi_v1', 0) - entry
    consumer_abi = int(cfg.get('CONFIG_EFI_BOOT_CHOICE_CONTEXT') == 'y' and
                       0 <= consumer <= len(raw)-4 and
                       raw[consumer:consumer+4] == b'\x01\x00\x00\x00')
    return {'consumer_abi': consumer_abi, 'stack_offset': stack, 'symbols': {name: syms[name] - entry for name in
            ('_start', '__bss_start', '__bss_end', '_end', 'save_boot_params')},
            'elf_sha256': c.digest(elf).hex(), 'config_sha256': c.digest(config).hex()}


def branch(pc, target):
    delta = target - pc
    require(delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27), 'B out of range')
    return struct.pack('<I', 0x14000000 | ((delta // 4) & 0x3ffffff))


def selector_binding(original, raw, elf, config, info, abi, owned=False):
    if owned == 'intent':
        require(abi.get('consumer_abi') == 1, 'flag-3 requires actual checked native U-Boot context ABI v1')
    pages=c.align(info['kernel']['image_size'])
    start=pages+8192
    payload=c.align(start+65536)
    end=c.align(payload+abi['stack_offset'])
    layout=owned_layout.plan(original,end,owned=='intent') if owned else None
    fdt_symbols={'eg_fdt_workspace':layout['fdt_start']-c.PAGE,'eg_fdt_workspace_end':layout['fdt_start']-c.PAGE+2*1024*1024} if owned=='intent' else {}
    if owned: end=layout['body']-c.PAGE
    generation=hashlib.sha256(original+raw+elf+config).hexdigest()
    return {'request_generation':generation,'original_sha256':c.digest(original).hex(), 'payload_sha256':c.digest(raw).hex(),
            'elf_sha256':c.digest(elf).hex(), 'config_sha256':c.digest(config).hex(),
            'symbols':{**fdt_symbols,'eg_image_start':0,'eg_image_end':end,
                       'eg_workspace_start':pages,'eg_workspace_end':end,'eg_request_pages':pages,
                       'eg_android_entry':info['kernel']['branch_target'],
                       'embedded_uboot':payload,'uboot_stack_top':payload+abi['stack_offset']}}


def build(original, raw, elf, config, selector_bundle=None, source_roots=None, owned=False):
    info = c.boot4(original)
    abi = elf_layout(elf, raw, config)
    if owned == 'intent':
        require(abi.get('consumer_abi') == 1, 'flag-3 requires actual checked native U-Boot context ABI v1')
    require(info['kernel']['entry_offset'] == 4, 'original must have MZ branch at +4')
    pages = c.align(info['kernel']['image_size'])
    selector = pages + (8192 if selector_bundle else 0)
    payload = c.align(selector + (65536 if selector_bundle else 24))
    stack = payload + abi['stack_offset']
    end = c.align(stack)
    layout = owned_layout.plan(original,end,owned=='intent') if owned else None
    if owned:
        require(selector_bundle is not None, 'owned runnable requires source-bound selector')
        end = layout['body']-c.PAGE
    require(end <= c.LIMIT and c.PAGE + end + 65536 <= len(original), 'expanded image exceeds partition')
    # These are actual AArch64 instructions, with PC-relative destinations only.
    # Default executes two B instructions, preserving every register and SP.
    # The U-Boot diagnostic label is UNREACHABLE from this entry, deliberately.
    adrp_pc = selector + 8
    page_delta = (stack // 4096) - (adrp_pc // 4096)
    require(-(1 << 20) <= page_delta < (1 << 20), 'ADRP out of range')
    imm = page_delta & 0x1fffff
    adrp = 0x90000009 | ((imm & 3) << 29) | ((imm >> 2) << 5)
    code = (branch(selector, selector + 4) + branch(selector + 4, info['kernel']['branch_target']) +
            struct.pack('<III', adrp, 0x91000129 | ((stack % 4096) << 10), 0x9100013f) +
            branch(selector + 20, payload))
    selector_manifest=None
    if selector_bundle:
        spec=importlib.util.spec_from_file_location('early_selector',Path(__file__).parent/'early-entry/selector.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        code, symbols, selector_manifest=module.validate(selector_bundle,source_roots,
            selector_binding(original,raw,elf,config,info,abi,owned))
        require(symbols['eg_bootstrap']==selector,'selector bootstrap must begin suffix')
        require(selector+len(code)<=payload,'selector exceeds reserved envelope')
    kernel = bytearray(end)
    old_size = info['kernel']['stored_bytes']
    kernel[:old_size] = original[c.PAGE:c.PAGE + old_size]
    kernel[4:8] = branch(4, selector)
    struct.pack_into('<Q', kernel, 16, end)
    if selector_bundle:
        record=bytearray(4096);record[:8]=b'BOOTREQ1';struct.pack_into('<I',record,8,1)
        record[12:44]=bytes.fromhex(selector_manifest['binding']['request_generation'])
        struct.pack_into('<QI',record,44,1,1);struct.pack_into('<I',record,60,zlib.crc32(record))
        kernel[pages:pages+4096]=record
    kernel[selector:selector + len(code)] = code
    kernel[payload:payload + len(raw)] = raw
    header = bytearray(original[:c.PAGE])
    struct.pack_into('<I', header, 8, end)
    image = bytes(header + kernel)
    if owned:
        image = owned_layout.finish(image,original,raw,selector_manifest["binding"],layout)
    return image, {'status': 'OFFLINE EXPERIMENT ONLY; NOT SAFE-TO-FLASH OR HARDWARE ACCEPTED',
                   'entry_policy': ('external audited selector: exact result1 U-Boot, otherwise Android' if selector_bundle else 'unconditional Android; U-Boot diagnostic label unreachable'),
                   'selector_manifest': selector_manifest,
                   'selector_offset': selector, 'payload_offset': payload,
                   'stack_top_offset': stack, 'expanded_image_size': end, 'abi': abi,
                   'avb_policy': 'REPLACED with unsigned AVB NONE hash descriptor; no RSA trust claim',
                   'original': info, 'payload_sha256': c.digest(raw).hex()}


def seal(body, size):
    with tempfile.TemporaryDirectory() as work:
        temp=Path(work)/'boot.img';temp.write_bytes(body)
        subprocess.run(['avbtool','add_hash_footer','--image',str(temp),'--partition_size',str(size),
            '--partition_name','boot','--algorithm','NONE','--hash_algorithm','sha256','--salt',''],check=True,stdout=subprocess.DEVNULL)
        subprocess.run(['avbtool','verify_image','--image',str(temp)],check=True,stdout=subprocess.DEVNULL)
        return c.read_regular(temp,c.LIMIT)

def immutable_body(image, catalog):
    body=bytearray(image[:c.PAGE+catalog['expanded_image_size']])
    offset=c.PAGE+catalog['selector_manifest']['binding']['symbols']['eg_request_pages']
    require(offset+8192<=len(body),'request bounds')
    body[offset:offset+8192]=bytes(8192)
    return bytes(body)

def verify(image, original, catalog):
    require(catalog['format'] == 'BOOT-EXPERIMENT-V1', 'unknown catalog')
    if 'immutable_body_sha256' in catalog:
        require(c.digest(immutable_body(image,catalog)).hex()==catalog['immutable_body_sha256'],'immutable image changed')
        require(seal(image[:c.PAGE+catalog['expanded_image_size']],len(image))==image,'noncanonical or invalid AVB/tail')
    else:
        require(c.digest(image).hex() == catalog['output_sha256'], 'output/catalog hash mismatch')
    require(c.digest(original).hex() == catalog['original']['sha256'], 'original/catalog hash mismatch')
    c.boot4(original)
    info = c.boot4(image)
    require(info['kernel']['stored_bytes'] == info['kernel']['image_size'] ==
            catalog['expanded_image_size'], 'expanded header sizes disagree')
    require(len(image) == len(original) and info['avb'] and info['avb']['algorithm'] == 0,
            'expected partition-sized unsigned AVB NONE output')
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    pack = sub.add_parser('pack')
    for name in ('original', 'payload', 'elf', 'config'):
        pack.add_argument('--' + name, required=True, type=Path)
    pack.add_argument('--selector-bundle', type=Path)
    pack.add_argument('--intent-prototype', action='store_true', help='host-only flag-3 producer; NOT deployable without transactional EFI adapter')
    pack.add_argument('--owned-runnable', action='store_true', help='prelinked flag-2 owned allocation; host validation only')
    pack.add_argument('--selector-source-root', action='append', default=[], metavar='NAME=PATH')
    pack.add_argument('--output-dir', required=True, type=Path)
    pack.add_argument('--allow-unsigned-avb-none', action='store_true', required=True)
    request=sub.add_parser('request', help='host files only; fresh output bundle, no device writes')
    request.add_argument('directory',type=Path)
    request.add_argument('--output-dir',type=Path,required=True)
    request.add_argument('--mode',choices=['android','uboot'],required=True)
    request.add_argument('--page-tool',type=Path,required=True)
    for name in ('verify', 'restore'):
        p = sub.add_parser(name)
        p.add_argument('directory', type=Path)
        if name == 'restore':
            p.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            original, raw, elf, config = [c.read_regular(getattr(args, name), c.LIMIT)
                                          for name in ('original', 'payload', 'elf', 'config')]
            roots=dict(value.split('=',1) for value in args.selector_source_root)
            image, report = build(original, raw, elf, config,args.selector_bundle,roots,'intent' if args.intent_prototype else args.owned_runnable)
            # avbtool operates ONLY on a fresh ordinary temporary host file.
            with tempfile.TemporaryDirectory() as work:
                temp = Path(work) / 'boot.img'
                temp.write_bytes(image)
                subprocess.run(['avbtool', 'add_hash_footer', '--image', str(temp),
                                '--partition_size', str(len(original)), '--partition_name', 'boot',
                                '--algorithm', 'NONE', '--hash_algorithm', 'sha256', '--salt', ''], check=True)
                subprocess.run(['avbtool', 'verify_image', '--image', str(temp)], check=True)
                image = c.read_regular(temp, c.LIMIT)
            report.update(format='BOOT-EXPERIMENT-V1', output_sha256=c.digest(image).hex())
            if report['selector_manifest']:
                report['immutable_body_sha256']=c.digest(immutable_body(image,report)).hex()
            verify(image, original, report)
            # New directory is the transaction boundary: never follow/overwrite an alias.
            args.output_dir.mkdir(mode=0o700)
            c.write_new(args.output_dir / 'original.img', original)
            c.write_new(args.output_dir / 'experiment.img', image)
            c.write_new(args.output_dir / 'catalog.json', (json.dumps(report, indent=2) + '\n').encode())
        else:
            require(not args.directory.is_symlink(), 'directory symlink refused')
            original = c.read_regular(args.directory / 'original.img', c.LIMIT)
            image = c.read_regular(args.directory / 'experiment.img', c.LIMIT)
            report = json.loads(c.read_regular(args.directory / 'catalog.json', 1024 * 1024))
            verify(image, original, report)
            if args.command == 'request':
                require('immutable_body_sha256' in report,'no owned request layout')
                binding=report['selector_manifest']['binding'];offset=c.PAGE+binding['symbols']['eg_request_pages']
                body=bytearray(image[:c.PAGE+report['expanded_image_size']])
                with tempfile.TemporaryDirectory() as work:
                    src=Path(work)/'pages';dst=Path(work)/'updated';src.write_bytes(body[offset:offset+8192])
                    subprocess.run([str(args.page_tool.resolve()),str(src),str(dst),binding['request_generation'],args.mode],check=True)
                    pages=c.read_regular(dst,8192);require(len(pages)==8192,'page-tool size')
                    body[offset:offset+8192]=pages
                image=seal(body,len(image));verify(image,original,report)
                report['output_sha256']=c.digest(image).hex()
                args.output_dir.mkdir(mode=0o700)
                c.write_new(args.output_dir/'original.img',original)
                c.write_new(args.output_dir/'experiment.img',image)
                c.write_new(args.output_dir/'catalog.json',(json.dumps(report,indent=2)+'\n').encode())
            if args.command == 'restore':
                c.write_new(args.output, original)
        print(json.dumps(report, indent=2))
    except (ValueError, OSError, KeyError, struct.error, subprocess.CalledProcessError) as error:
        parser.exit(1, f'error: {error}\n')


if __name__ == '__main__':
    main()
