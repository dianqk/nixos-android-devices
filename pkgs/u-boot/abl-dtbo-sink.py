"""Redirect overlay labels of the U-Boot DTB to empty sink nodes.

ABL merges the dtbo partition's overlay into the DTB appended to the boot
image before starting U-Boot, and refuses to boot when the merge fails. A
stock overlay written for the Android DT references labels this DTB does not
have (FDT_ERR_NOTFOUND). For every listed label, add /abl-dtbo-sink/<label>
with a fresh phandle and point /__symbols__/<label> at it, so the overlay
applies but only fills the sink; labels already present in the DTB are
redirected too, keeping overlay content out of real nodes. Labels that are
not listed (e.g. arch_timer for ABL's own hypervisor overlay) are untouched.

Usage: abl-dtbo-sink.py IN.dtb OUT.dtb LABELS.txt
"""
import sys, libfdt
src, dst, labels_file = sys.argv[1:4]
labels = [l.strip() for l in open(labels_file) if l.strip() and not l.startswith('#')]
data = open(src, 'rb').read()
fdt = libfdt.Fdt(data)
fdt.resize(len(data) + len(labels) * 160 + 4096)
maxph = 0; off = 0; depth = 0
while True:
    r = fdt.next_node(off, depth, [libfdt.NOTFOUND])
    if isinstance(r, int) or r[0] < 0:
        break
    off, depth = r
    maxph = max(maxph, fdt.get_phandle(off))
fdt.add_subnode(0, 'abl-dtbo-sink')
ph = maxph
for l in labels:
    n = fdt.add_subnode(fdt.path_offset('/abl-dtbo-sink'), l)
    ph += 1
    fdt.setprop_u32(n, 'phandle', ph)
    fdt.setprop_str(fdt.path_offset('/__symbols__'), l, '/abl-dtbo-sink/' + l)
fdt.pack()
open(dst, 'wb').write(fdt.as_bytearray())
print(f'{len(labels)} labels -> /abl-dtbo-sink, phandles {maxph + 1}..{ph}')
