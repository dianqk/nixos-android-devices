#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""Compile actual U-Boot EFI Open + FAT traversal with RAM allocation/block faults.
UBOOT_SOURCE points at prepared source. TEST_OUTPUT optionally retains the native
bridge object used by the full EFI-entry harness. No source/device is modified.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(os.environ['UBOOT_SOURCE'])
efi = (root / 'lib/efi_loader/efi_file.c').read_text()
fat = (root / 'fs/fat/fat.c').read_text()

def function(source, name):
    import re
    match = re.search(r'^(?:static )?[A-Za-z_][\w *]*\b' + name + r'\([^;]*?\)\n\{', source, re.M)
    assert match, name
    start, brace = match.start(), source.index('{', match.start())
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

# Legacy source deliberately compiles too: its first allocation regression
# assertion fails, proving this is not just a better-behaved fake EFI service.
checked = 'get_fatent_checked' in fat
preamble = r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <stdbool.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;
typedef uint32_t __u32; typedef uint16_t __u16; typedef uint8_t __u8;
typedef uint64_t u64; typedef unsigned long efi_status_t;
#define EFIERR(x) ((1UL<<63)|(x))
#define EFI_SUCCESS 0
#define EFI_INVALID_PARAMETER EFIERR(2)
#define EFI_UNSUPPORTED EFIERR(3)
#define EFI_DEVICE_ERROR EFIERR(7)
#define EFI_OUT_OF_RESOURCES EFIERR(9)
#define EFI_NOT_FOUND EFIERR(14)
#define EFI_FILE_MODE_READ 1
#define EFI_FILE_MODE_WRITE 2
#define EFI_FILE_MODE_CREATE (1ULL<<63)
#define EFI_FILE_DIRECTORY 16
#define EFI_FILE_READ_ONLY 1
#define EFI_FILE_VALID_ATTR 0x37
#define CONFIG_EFI_BOOT_CHOICE_DURABLE_IO 1
#define IS_ENABLED(x) (x)
#define EFI_PRINT(...) ((void)0)
#define debug(...) ((void)0)
#define log_debug(...) ((void)0)
#define log_err(...) ((void)0)
#define MAX_UTF8_PER_UTF16 3
#define FS_TYPE_FAT 1
#define TYPE_FILE 1
#define TYPE_DIR 2
#define TYPE_ANY 3
#define ISDIRDELIM(c) ((c)=='/' || (c)=='\\')
#define min_t(t,a,b) ((t)(a)<(t)(b)?(t)(a):(t)(b))
#define max(a,b) ((a)>(b)?(a):(b))
#define VFAT_MAXLEN_BYTES 768
#define MAX_CLUSTSIZE 4096
#define ARCH_DMA_MINALIGN 8
#define __aligned(x) __attribute__((aligned(x)))
#define ATTR_DIR 16
#define ATTR_VOLUME 8
#define ATTR_VFAT 15
#define DELETED_FLAG 0xe5
#define aRING 0x05
#define LAST_LONG_ENTRY_MASK 0x40
#define FAT32BUFSIZE 1024
#define FAT16BUFSIZE 2048
#define FAT12BUFSIZE 2730
#define FATBUFBLOCKS 8
#define FAT2CPU32(x) (x)
#define FAT2CPU16(x) (x)
#define CHECK_CLUST(c,f) ((c)<=1 || (c)>=((f)==32?0x0ffffff0U:(f)==16?0xfff0U:0xff0U))
typedef struct { char name[8],ext[3]; } nameext_t;
typedef struct dir_entry { nameext_t nameext; u8 attr; u8 pad[20]; } dir_entry;
typedef struct {u8 alias_checksum;} dir_slot;
typedef struct { unsigned root_cluster,fatsize,clust_size,rootdir_size,rootdir_sect,sect_size;
 unsigned fatbufnum,fatlength,fat_sect;u8 *fatbuf;} fsdata;
typedef struct fat_itr fat_itr;
static unsigned fault, allocs, selections; static int present, fat32;
/* Faults:1/2 EFI allocations,3 sanitize,4/5/6 set_blk_dev,
 * 7 iterator allocation,8 filesystem boot info,9 directory read,
 *10 FAT-chain read,11 create,12 filesystem buffer allocation. */
static void *test_calloc(size_t n,size_t size){if(++allocs==fault && fault<=2)return NULL;return calloc(n,size);}
static void *cache_alloc(size_t n){if(fault==7)return NULL;return malloc(n);}
#define calloc test_calloc
#define malloc_cache_aligned cache_alloc
static int get_fs_info(fsdata *f){
 if(fault==8 || fault==12)return -1;
 *f=(fsdata){.root_cluster=2,.fatsize=fat32?32:16,.clust_size=1,.rootdir_size=1,.rootdir_sect=20,.sect_size=512,.fatbufnum=~0U,.fatlength=8,.fat_sect=8};
 f->fatbuf=malloc(4096);memset(f->fatbuf,0xff,4096);return 0;
}
static unsigned clust_to_sect(fsdata *f,unsigned c){(void)f;return c+20;}
static int flush_dirty_fat_buffer(fsdata *f){(void)f;return 0;}
static int disk_read(unsigned sect,unsigned count,void *buffer){
 if((fault==9 && sect!=8)||(fault==10 && sect==8))return -1;
 memset(buffer,sect==8?0xff:0,count*512);
 if(sect!=8 && present){dir_entry *e=buffer;memcpy(e->nameext.name,"journal",7);}
 return count;
}
#define START(d) ((void)mydata,2)
static void get_name(dir_entry *d,char *out){memcpy(out,d->nameext.name,8);out[8]=0;}
static void slot2str(dir_slot *s,char *buf,int *idx){(void)s;(void)buf;*idx=0;}
static u8 mkcksum(nameext_t *n){(void)n;return 0;}
'''
# Exact production iterator structure (including the new local errno).
a = fat.index('struct fat_itr {')
b = fat.index('\n};', a) + 3
iterator = fat[a:b]
fat_names = (['get_fatent_checked'] if checked else ['get_fatent']) + [
    'fat_itr_root', 'fat_itr_child', 'fat_next_cluster', 'next_dent',
    'extract_vfat_name', 'fat_itr_next', 'fat_itr_isdir', 'fat_itr_resolve',
    'fat_lookup' if checked else 'fat_exists']
fat_code = '\n'.join(function(fat, n) for n in fat_names)
efi_preamble = r'''
struct efi_simple_file_system_protocol {int unused;};
struct file_system {struct efi_simple_file_system_protocol base;};
#define to_fs(x) ((struct file_system *)(x))
struct efi_file_handle {int unused;};
struct file_handle {struct efi_file_handle base;struct file_system *fs;u64 open_mode;char *path;int isdir;};
#define to_fh(x) ((struct file_handle *)(x))
static const struct efi_file_handle efi_file_handle_protocol={0};
static void utf16_to_utf8(u8 *out,u16 *in,int n){for(int i=0;i<n;i++)out[i]=in[i];}
static int u16_strlen(u16 *in){int n=0;while(in[n])n++;return n;}
static int sanitize_path(char *s){(void)s;return fault==3;}
static int set_blk_dev(struct file_handle *fh){(void)fh;return ++selections==fault-3 && fault>=4 && fault<=6;}
static int fs_get_type(void){return FS_TYPE_FAT;}
static void fs_close(void){}
static int efi_create_file(struct file_handle *fh,u64 attr){(void)fh;(void)attr;return fault==11?-1:0;}
static int is_dir(struct file_handle *fh){(void)fh;return 0;}
'''
if checked:
    efi_preamble += 'static int fs_exists(const char *p){(void)p;abort();}\n'
else:
    efi_preamble += 'static int fs_exists(const char *p){return fat_exists(p);}\n'
bridge = r'''
/* Native ABI bridge also called by production efi_main's fake FileProtocol. */
unsigned long production_open_status(unsigned inject,int exists,int create){
 struct file_system fs={0};struct file_handle parent={.fs=&fs,.path=""};
 struct efi_file_handle *opened=NULL;u16 name[]={'j','o','u','r','n','a','l',0};
 fault=inject;allocs=selections=0;present=exists;fat32=inject==10;
 efi_status_t s=efi_file_open_int(&parent.base,&opened,name,create?(EFI_FILE_MODE_READ|EFI_FILE_MODE_WRITE|EFI_FILE_MODE_CREATE):EFI_FILE_MODE_READ,0);
 if(opened){struct file_handle *h=to_fh(opened);free(h->path);free(h);}
 return s;
}
#ifndef OPEN_BRIDGE_ONLY
int main(void){
 struct file_system fs={0};struct efi_file_handle *volume=NULL;
 for(unsigned i=1;i<=2;i++){fault=i;allocs=0;assert(efi_open_volume_int(&fs.base,&volume)==EFI_OUT_OF_RESOURCES && !volume);}
 assert(production_open_status(0,1,0)==EFI_SUCCESS);
 assert(production_open_status(0,0,0)==EFI_NOT_FOUND);
 for(unsigned i=1;i<=12;i++){
  if(i==6 || i==11)continue;
  unsigned long s=production_open_status(i,1,0);
  fprintf(stderr,"production Open fault %u => %lx\n",i,s);
  assert(s!=EFI_SUCCESS && s!=EFI_NOT_FOUND);
 }
 assert(production_open_status(1,1,0)==EFI_OUT_OF_RESOURCES);
 assert(production_open_status(2,1,0)==EFI_OUT_OF_RESOURCES);
 assert(production_open_status(3,1,0)==EFI_INVALID_PARAMETER);
 assert(production_open_status(7,1,0)==EFI_OUT_OF_RESOURCES);
 assert(production_open_status(0,0,1)==EFI_SUCCESS);
 for(unsigned i=4;i<=6;i++)assert(production_open_status(i,0,1)==EFI_DEVICE_ERROR);
 assert(production_open_status(11,0,1)==EFI_DEVICE_ERROR);
 puts("PASS actual EFI Open/FAT traversal: positive absence vs allocation/path/device/directory/FAT/create errors");
}
#endif
'''
source = preamble + iterator + '\nstatic int fat_itr_isdir(fat_itr *itr);\n' + fat_code + efi_preamble + function(efi, 'file_open') + function(efi, 'efi_file_open_int') + function(efi, 'efi_open_volume_int') + bridge
with tempfile.TemporaryDirectory() as d:
    work = Path(os.environ.get('TEST_OUTPUT', d))
    work.mkdir(parents=True, exist_ok=True)
    c = work / 'production-open.c'
    c.write_text(source)
    flags = ['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-sign-compare']
    subprocess.run(flags + [str(c), '-o', str(work / 'production-open')], check=True)
    subprocess.run([str(work / 'production-open')], check=True)
    subprocess.run(flags + ['-DOPEN_BRIDGE_ONLY', '-c', str(c), '-o', str(work / 'production-open.o')], check=True)
