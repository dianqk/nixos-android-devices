#!/usr/bin/env python3
"""Execute ACM's real stdio initializer with poisoned automatic storage.

Usage: python tests/uboot-acm-stdio.py /path/to/u-boot /path/to/test-work-dir
Checks both configurations of the optional console flush callback. Requires GCC.
"""
from pathlib import Path
import os
import resource
import subprocess
import sys
import tempfile

source, work = map(Path, sys.argv[1:])
work.mkdir(parents=True, exist_ok=True)
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
acm = (source / 'drivers/usb/gadget/f_acm.c').read_text()
start = acm.index('int drv_usbacm_init(void)')
initializer = acm[start:acm.index('\n}', start) + 2]
header = (source / 'include/stdio_dev.h').read_text()
start = header.index('struct stdio_dev {')
descriptor = header[start:header.index('\n};', start) + 3]
shim = r'''
#include <assert.h>
#include <stddef.h>
#include <string.h>
#define STDIO_NAME_LEN 32
#define DEV_FLAGS_INPUT 1
#define DEV_FLAGS_OUTPUT 2
struct list_head { struct list_head *next, *prev; };
'''
checks = r'''
static int acm_stdio_start(struct stdio_dev *d) { return 0; }
static int acm_stdio_stop(struct stdio_dev *d) { return 0; }
static int acm_stdio_tstc(struct stdio_dev *d) { return 0; }
static int acm_stdio_getc(struct stdio_dev *d) { return 0; }
static void acm_stdio_putc(struct stdio_dev *d, char c) {}
static void acm_stdio_puts(struct stdio_dev *d, const char *s) {}
static int stdio_register(struct stdio_dev *d) {
    assert(!strcmp(d->name, "usbacm"));
    assert(d->flags == (DEV_FLAGS_INPUT | DEV_FLAGS_OUTPUT));
    assert(d->ext == 0 && d->priv == NULL);
    assert(d->start == acm_stdio_start && d->stop == acm_stdio_stop);
    assert(d->tstc == acm_stdio_tstc && d->getc == acm_stdio_getc);
    assert(d->putc == acm_stdio_putc && d->puts == acm_stdio_puts);
#ifdef CONFIG_CONSOLE_FLUSH_SUPPORT
    /* A non-NULL garbage callback makes panic() fault before reset. */
    assert(d->flush == NULL);
#endif
    return 17;
}
'''
with tempfile.TemporaryDirectory(dir=work) as directory:
    path = Path(directory)
    c = path / 'acm-stdio.c'
    c.write_text(shim + descriptor + checks + initializer +
                 '\nint main(void) { assert(drv_usbacm_init() == 17); }\n')
    for flush in (True, False):
        flags = ['-DCONFIG_CONSOLE_FLUSH_SUPPORT'] if flush else []
        binary = path / 'acm-stdio'
        subprocess.run([os.environ.get('CC', 'gcc'), '-O2',
                        '-ftrivial-auto-var-init=pattern', *flags,
                        str(c), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
print('ACM stdio initializer passes with and without console flush support')
