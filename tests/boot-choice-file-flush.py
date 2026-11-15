#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""Compile actual prepared U-Boot File Write/Flush functions with ordering mocks.
UBOOT_SOURCE must be the existing patched source; no firmware source is modified.
"""
import os
from pathlib import Path
import subprocess
import tempfile

source = (Path(os.environ['UBOOT_SOURCE']) / 'lib/efi_loader/efi_file.c').read_text()
def function(name):
    start = source.index('static efi_status_t ' + name + '(')
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

preamble = r'''
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef long long loff_t;
typedef size_t efi_uintn_t;
typedef int efi_status_t;
#define EFI_SUCCESS 0
#define EFI_INVALID_PARAMETER 1
#define EFI_UNSUPPORTED 2
#define EFI_ACCESS_DENIED 3
#define EFI_DEVICE_ERROR 4
#define EFI_FILE_MODE_WRITE 2
#define FS_TYPE_FAT 1
#define CONFIG_EFI_BOOT_CHOICE_DURABLE_IO 1
#define IS_ENABLED(x) (x)
#define true 1
typedef int bool;
struct file_system { void *desc; };
struct efi_file_handle { int unused; };
struct file_handle {
 struct efi_file_handle base;
 struct file_system *fs;
 loff_t offset;
 int isdir;
 uint64_t open_mode;
 bool write_failed;
 char *path;
};
#define to_fh(x) ((struct file_handle *)(x))
static int phase, failwrite, failflush, shortwrite, type=FS_TYPE_FAT, flushes;
static void *expected;
static int set_blk_dev(struct file_handle *fh) { assert(fh->fs->desc==expected);return 0; }
static uintptr_t map_to_sysmem(void *p) { return (uintptr_t)p; }
static int fs_get_type(void) {return type;}
static int fs_write(char *p,uintptr_t b,loff_t off,size_t n,loff_t *act) {
 (void)p;(void)b;(void)off;
 assert(phase==0);phase=1;*act=n-shortwrite;return failwrite;
}
static int efi_boot_choice_sync(void *desc) {
 assert(desc==expected && phase==1);flushes++;return failflush?EFI_DEVICE_ERROR:EFI_SUCCESS;
}
'''
main = r'''
int main(void) {
 int esp, boot;
 struct file_system fs={&esp};
 struct file_handle fh={.fs=&fs,.open_mode=EFI_FILE_MODE_WRITE};
 char data[8]={0};size_t n=sizeof(data);
 expected=&esp;
 assert(efi_file_write_int(&fh.base,&n,data)==EFI_SUCCESS);
 assert(efi_file_flush_int(&fh.base)==EFI_SUCCESS);
 assert(flushes==1);
 /* A boot-LUN flush is separate, never a global or journal-only flush. */
 expected=&boot;assert(efi_boot_choice_sync(&boot)==EFI_SUCCESS);assert(flushes==2);
 expected=&esp;failflush=1;
 assert(efi_file_flush_int(&fh.base)==EFI_DEVICE_ERROR);
 phase=0;shortwrite=1;
 assert(efi_file_write_int(&fh.base,&n,data)==EFI_SUCCESS && n==sizeof(data)-1);
 /* EFI reports a successful partial count; the application must reject it. */
 phase=0;shortwrite=0;failwrite=1;
 assert(efi_file_write_int(&fh.base,&n,data)==EFI_DEVICE_ERROR);
 int before=flushes;
 assert(efi_file_flush_int(&fh.base)==EFI_DEVICE_ERROR && flushes==before);
 fh.write_failed=0;type=99;
 assert(efi_file_flush_int(&fh.base)==EFI_UNSUPPORTED);
 fh.open_mode=0;
 assert(efi_file_flush_int(&fh.base)==EFI_ACCESS_DENIED);
 puts("PASS actual File Write/Flush ordering, per-volume scope, sticky write failure, flush failure, unsupported FS");
}
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d)
    (p/'test.c').write_text(preamble + function('efi_file_write_int') + '\n' + function('efi_file_flush_int') + main)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
