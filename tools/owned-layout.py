# SPDX-License-Identifier: GPL-2.0-only
"""Deterministic runnable owned allocation, calculated before selector linking.
Offsets on wire are absolute; linker offsets are Image-relative. No output hash
participates in layout or installation identity.
"""
import hashlib
import struct
PAGE = 4096
CAP = 256 * 1024 * 1024

def align(n): return (n + PAGE - 1) & -PAGE

def plan(original, native_end, intent=False):
    if not (8192 <= len(original) <= CAP and len(original) % PAGE == 0):
        raise ValueError('original partition bound')
    prefix = (PAGE + struct.unpack_from('<I', original, 8)[0]) & -PAGE
    if not 4160 <= prefix <= len(original): raise ValueError('original prefix')
    records = [(0, original[:4160])]
    records += [(at, original[at:at+PAGE]) for at in range(prefix, len(original), PAGE)
                if any(original[at:at+PAGE])]
    archive = b''.join(struct.pack('<QQ', at, len(data)) + data for at, data in records)
    if len(archive) > 16*1024*1024 or len(records) > 65536:
        raise ValueError('archive capacity')
    fdt_start = PAGE + native_end
    start = fdt_start + (2*1024*1024 if intent else 0)
    meta = align(start + len(archive))
    body = meta + PAGE
    if not (native_end % PAGE == 0 and body + 8192 <= len(original)):
        raise ValueError('owned allocation capacity')
    return dict(intent=intent, fdt_start=fdt_start, native_end=native_end, archive_start=start, archive=archive,
                prefix=prefix, count=len(records), meta=meta, body=body)

def finish(body, original, raw, binding, layout):
    """Materialize the prelinked allocation; never extend advertised sizes here."""
    s = binding['symbols']; p = layout
    if len(body) != p['body'] or s['eg_image_end'] != len(body)-PAGE or s['eg_workspace_end'] != s['eg_image_end']:
        raise ValueError('compiled owned allocation mismatch')
    out = bytearray(body); meta = p['meta']; pages = PAGE+s['eg_request_pages']
    out[p['archive_start']:p['archive_start']+len(p['archive'])] = p['archive']
    out[meta:meta+8] = b'OWNBOOT1'; struct.pack_into('<II', out, meta+8, 1, 3 if p["intent"] else 2)
    payload = PAGE+s['embedded_uboot']
    values = [len(original), len(out), p['archive_start'], pages, pages+8192,
              payload, payload, payload+len(raw), align(payload+len(raw)),
              len(out), p['archive_start'], len(p['archive']), p['prefix'], p['count']]
    for i, value in enumerate(values): struct.pack_into('<Q', out, meta+16+8*i, value)
    if p['intent']:
        struct.pack_into('<QQQ',out,meta+224,p['fdt_start'],2*1024*1024,1)
    out[meta+128:meta+160] = bytes.fromhex(binding['request_generation'])
    out[meta+160:meta+192] = hashlib.sha256(original).digest()
    normalized = bytearray(out); normalized[pages:pages+8192] = bytes(8192)
    normalized[meta+192:meta+224] = bytes(32)
    out[meta+192:meta+224] = hashlib.sha256(normalized).digest()
    return bytes(out)
