#!/usr/bin/env python3
"""Compile the patched U-Boot font-selection code with instrumented device APIs.

Usage: python tests/uboot-font-scale.py PATCHED_UBOOT_SOURCE
Checks all 256 glyphs, padded byte rows, rotation, allocation failure/reselection
and native-scale behavior with AddressSanitizer and UndefinedBehaviorSanitizer.
No Nix build or hardware is needed; CC defaults to the host C compiler.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
core = (source / 'drivers/video/console_core.c').read_text()
functions = core[core.index('static struct video_fontdata *console_scale_font'):core.index('int check_bpix_support')]
preamble = r'''
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "video_font_data.h"
#include "video_font_8x16.h"
#define GFP_KERNEL 0
#define debug(...) ((void)0)
#define VID_TO_POS(x) ((x) * 256)
struct console_simple_priv { struct video_fontdata *fontdata, *scaled_font; };
struct vidconsole_priv { int x_charsize, y_charsize, cols, rows, xsize_frac; };
struct video_priv { int xsize, ysize, rot; };
struct udevice {
    struct udevice *parent;
    struct console_simple_priv simple;
    struct vidconsole_priv console;
    struct video_priv video;
};
static int allocations, fail_alloc;
static void *devm_kzalloc(struct udevice *dev, size_t size, int flags) {
    (void)dev; (void)flags;
    if (fail_alloc) return NULL;
    void *p = calloc(1, size);
    if (p) allocations++;
    return p;
}
static void devm_kfree(struct udevice *dev, void *p) {
    (void)dev;
    assert(p); /* U-Boot devres does not accept a NULL resource. */
    allocations--;
    free(p);
}
static void *dev_get_priv(struct udevice *dev) { return &dev->simple; }
static void *dev_get_uclass_priv(struct udevice *dev) {
    return dev->parent ? (void *)&dev->console : (void *)&dev->video;
}
'''
checks = r'''
static void check_glyphs(struct video_fontdata *a, struct video_fontdata *b, int scale) {
    assert(b->width == a->width * scale && b->height == a->height * scale);
    assert(b->byte_width == (b->width + 7) / 8);
    assert(b->char_pixel_bytes == b->height * b->byte_width);
    for (int g = 0; g < 256; g++)
        for (int y = 0; y < b->height; y++)
            for (int x = 0; x < b->byte_width * 8; x++) {
                int expected = x < b->width &&
                    (a->video_fontdata[g * a->char_pixel_bytes + y / scale * a->byte_width + x / scale / 8]
                     & (0x80 >> (x / scale % 8)));
                int actual = b->video_fontdata[g * b->char_pixel_bytes + y * b->byte_width + x / 8]
                             & (0x80 >> (x % 8));
                assert(!!actual == !!expected);
            }
}
int main(void) {
    struct udevice panel = { .video = { .xsize = 1080, .ysize = 2160 } };
    struct udevice console = { .parent = &panel };
    struct video_fontdata font = FONT_ENTRY(8, 16, 8x16);
    assert(console_set_font(&console, &font) == 0);
    check_glyphs(&font, console.simple.fontdata, CONFIG_VIDEO_FONT_SCALE);
    assert(console.console.cols == 1080 / (8 * CONFIG_VIDEO_FONT_SCALE));
    assert(console.console.rows == 2160 / (16 * CONFIG_VIDEO_FONT_SCALE));
    if (CONFIG_VIDEO_FONT_SCALE == 1) {
        assert(allocations == 0 && console.simple.fontdata == &font);
    } else {
        assert(allocations == 1);
        struct video_fontdata *old = console.simple.fontdata;
        fail_alloc = 1;
        assert(console_set_font(&console, &font) == -ENOMEM);
        assert(console.simple.fontdata == old && allocations == 1);
        fail_alloc = 0;
        panel.video.rot = 1;
        assert(console_set_font(&console, &font) == 0);
        assert(allocations == 1);
        assert(console.console.cols == 2160 / (8 * CONFIG_VIDEO_FONT_SCALE));
        assert(console.console.rows == 1080 / (16 * CONFIG_VIDEO_FONT_SCALE));
        devm_kfree(&console, console.simple.scaled_font);
    }
    /* Six-pixel fonts exercise source and destination byte padding. */
    unsigned char padded[256 * 8];
    for (size_t i = 0; i < sizeof(padded); i++) padded[i] = i;
    struct video_fontdata narrow = { "6x8", 6, 8, 1, 8, padded };
    struct video_fontdata *scaled = console_scale_font(&console, &narrow, 3);
    assert(scaled);
    check_glyphs(&narrow, scaled, 3);
    devm_kfree(&console, scaled);
    assert(allocations == 0);
    printf("scale %d: glyphs, metrics, padded rows, allocation handling OK\n", CONFIG_VIDEO_FONT_SCALE);
    return 0;
}
'''
(REPO / 'tmp').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=REPO / 'tmp', prefix='font-scale-') as directory:
    work = Path(directory)
    for header in ('video_font_data.h', 'video_font_8x16.h'):
        shutil.copyfile(source / 'include' / header, work / header)
    (work / 'check.c').write_text(preamble + functions + checks)
    for scale in (1, 2, 3, 4):
        subprocess.run([os.environ.get('CC', 'cc'), '-std=gnu11', '-g', '-O1',
                        '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                        f'-DCONFIG_VIDEO_FONT_SCALE={scale}', '-I', str(work), str(work / 'check.c'),
                        '-o', str(work / 'check')], check=True)
        subprocess.run([str(work / 'check')], check=True)
