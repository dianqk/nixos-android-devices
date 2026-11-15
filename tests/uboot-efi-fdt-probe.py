#!/usr/bin/env python3
"""Compile the actual EFI FDT probe with host libfdt and EFI service mocks.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-efi-fdt-probe.py UBOOT DTB
Set CFLAGS/LDFLAGS for the host libfdt headers/library if needed.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve() / 'lib/efi_loader/fdt_probe.c'
dtb = Path(sys.argv[2]).resolve()
api = r'''
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef u64 efi_status_t; typedef u64 efi_physical_addr_t; typedef size_t efi_uintn_t;
typedef void *efi_handle_t; typedef struct {u8 data[16];} efi_guid_t;
#define EFIAPI
#define EFI_FDT_GUID {{0}}
#define EFI_LOAD_FILE2_PROTOCOL_GUID {{1}}
#define EFI_INITRD_MEDIA_GUID {{2}}
#define EFI_LOADED_IMAGE_PROTOCOL_GUID {{3}}
#define EFI_SUCCESS 0
#define EFI_LOAD_ERROR 1
#define EFI_UNSUPPORTED 3
#define EFI_BUFFER_TOO_SMALL 5
#define EFI_NOT_FOUND 14
#define EFI_ABORTED 21
#define EFI_LOADER_DATA 2
#define EFI_ALLOCATE_ANY_PAGES 0
#define EFI_OPEN_PROTOCOL_GET_PROTOCOL 2
#define EFI_PAGE_SIZE 4096
#define EFI_PAGE_MASK 4095
#define EFI_PAGE_SHIFT 12
#define DEVICE_PATH_TYPE_MEDIA_DEVICE 4
#define DEVICE_PATH_SUB_TYPE_VENDOR_PATH 3
#define DEVICE_PATH_TYPE_END 0x7f
#define DEVICE_PATH_SUB_TYPE_END 0xff
struct efi_device_path {u8 type,sub_type;u16 length;};
struct efi_mem_desc {u32 type,pad;u64 physical_start,virtual_start,num_pages,attribute;};
struct efi_loaded_image {void *image_base;u64 image_size;};
struct efi_load_file_protocol {efi_status_t(*load_file)(struct efi_load_file_protocol*,struct efi_device_path*,bool,efi_uintn_t*,void*);};
struct efi_simple_text_output_protocol {efi_status_t(*output_string)(struct efi_simple_text_output_protocol*,const u16*);};
struct efi_boot_services {
 efi_status_t(*get_memory_map)(efi_uintn_t*,struct efi_mem_desc*,efi_uintn_t*,efi_uintn_t*,u32*);
 efi_status_t(*allocate_pool)(u32,efi_uintn_t,void**);efi_status_t(*free_pool)(void*);
 efi_status_t(*locate_device_path)(const efi_guid_t*,struct efi_device_path**,efi_handle_t*);
 efi_status_t(*open_protocol)(efi_handle_t,const efi_guid_t*,void**,efi_handle_t,efi_handle_t,u32);
 efi_status_t(*allocate_pages)(u32,u32,efi_uintn_t,efi_physical_addr_t*);
 efi_status_t(*free_pages)(efi_physical_addr_t,efi_uintn_t);
 efi_status_t(*calculate_crc32)(void*,efi_uintn_t,u32*);
};
struct efi_configuration_table {efi_guid_t guid;void *table;};
struct efi_system_table {struct efi_simple_text_output_protocol *con_out;struct efi_boot_services *boottime;efi_uintn_t nr_tables;struct efi_configuration_table *tables;};
'''
main = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include FDT_PROBE_SOURCE
static char output[262144];static size_t used;static int mode,allocations;
static efi_status_t print(struct efi_simple_text_output_protocol*p,const u16*s){while(*s){assert(used+1<sizeof(output));output[used++]=(char)*s++;}output[used]=0;return 0;}
static efi_status_t getmap(efi_uintn_t*size,struct efi_mem_desc*map,efi_uintn_t*key,efi_uintn_t*stride,u32*version){
 *stride=sizeof(*map);*size=2*sizeof(*map);
 if(mode==0)return EFI_SUCCESS;
 if(mode==1)*size=505*sizeof(*map);
 if(mode==2)*stride=1;
 if(mode==3)*size+=1;
 return EFI_BUFFER_TOO_SMALL;
}
static efi_status_t allocate(u32 t,efi_uintn_t size,void**p){allocations++;return EFI_ABORTED;}
static efi_status_t openimage(efi_handle_t h,const efi_guid_t*g,void**p,efi_handle_t a,efi_handle_t c,u32 flags){static struct efi_loaded_image image={(void*)0x90000000,4096};*p=&image;return 0;}
int main(int argc,char**argv){
 char *original=calloc(1,2*1024*1024),*work=calloc(1,2*1024*1024);FILE*f=fopen(argv[1],"rb");assert(f);size_t bytes=fread(original,1,1024*1024,f);fclose(f);assert(bytes>sizeof(struct fdt_header));
 struct efi_simple_text_output_protocol out={print};struct efi_boot_services bs={.get_memory_map=getmap,.allocate_pool=allocate,.open_protocol=openimage};struct efi_configuration_table config={{{0}},work};struct efi_system_table table={&out,&bs,1,&config};st=&table;
 assert(!fdt_open_into(original,work,2*1024*1024));assert(report_fdt((u8*)work)==EFI_SUCCESS);
 int root=fdt_path_offset(work,"/");assert(!fdt_setprop_u32(work,root,"#address-cells",2));assert(!fdt_setprop_u32(work,root,"#size-cells",2));
 int memory=fdt_add_subnode(work,root,"memory-controller-test");assert(memory>=0);assert(!fdt_setprop_u32(work,memory,"reg",1));assert(report_fdt((u8*)work)==EFI_SUCCESS);
 int chosen=fdt_path_offset(work,"/chosen");assert(chosen>=0);fdt64_t range[2]={cpu_to_fdt64(0x80000000),cpu_to_fdt64(0x73800000)};assert(!fdt_setprop(work,chosen,"linux,usable-memory-range",range,sizeof(range)));used=0;assert(report_fdt((u8*)work)==EFI_SUCCESS);assert(strstr(output,"usable_start=0x0000000080000000"));assert(strstr(output,"usable_size=0x0000000073800000"));
 assert(!fdt_setprop(work,chosen,"linux,usable-memory-range",range,8));assert(report_fdt((u8*)work)==EFI_UNSUPPORTED);
 assert(!fdt_open_into(original,work,2*1024*1024));int reserved=fdt_path_offset(work,"/reserved-memory");assert(reserved>=0);assert(!fdt_setprop_u32(work,reserved,"#address-cells",1));assert(report_fdt((u8*)work)==EFI_UNSUPPORTED);
 assert(!fdt_open_into(original,work,2*1024*1024));((struct fdt_header*)work)->magic=0;assert(report_fdt((u8*)work)==EFI_LOAD_ERROR);
 assert(!fdt_open_into(original,work,2*1024*1024));((struct fdt_header*)work)->size_dt_struct=cpu_to_fdt32(3);assert(report_fdt((u8*)work)==EFI_LOAD_ERROR);
 assert(!fdt_open_into(original,work,2*1024*1024));((struct fdt_header*)work)->totalsize=cpu_to_fdt32(sizeof(struct fdt_header)-1);assert(report_fdt((u8*)work)==EFI_LOAD_ERROR);
 for(mode=0;mode<4;mode++){assert(!fdt_open_into(original,work,2*1024*1024));used=allocations=0;assert(efi_main(NULL,&table)==EFI_LOAD_ERROR);assert(!allocations);assert(strstr(output,"EFI-FDT-PROBE FAIL"));assert(!strstr(output,"EFI-FDT-PROBE PASS"));}
 free(work);free(original);
}
'''
with tempfile.TemporaryDirectory(prefix='efi-fdt-probe-') as tmp:
    work=Path(tmp);(work/'linux').mkdir();(work/'efi_api.h').write_text(api)
    (work/'efi_load_initrd.h').write_text('struct efi_lo_dp_prefix {struct {struct efi_device_path header;efi_guid_t guid;}vendor;struct efi_device_path end;};\n')
    (work/'linux/libfdt.h').write_text('#include <libfdt.h>\n')
    (work/'test.c').write_text(main)
    args=shlex.split(os.environ.get('CC','cc'))+['-std=gnu11','-Wall',f'-I{work}',f'-DFDT_PROBE_SOURCE="{source}"']
    args+=shlex.split(os.environ.get('CFLAGS',''))+[str(work/'test.c'),'-o',str(work/'test')]+shlex.split(os.environ.get('LDFLAGS',''))+['-lfdt']
    subprocess.run(args,check=True);subprocess.run([str(work/'test'),str(dtb)],check=True)
print('PASS actual FDT parser: compiled board, cap, local reserved cells, exact memory-node names, malformed/truncated data; EFI_SUCCESS/oversized/misaligned memory queries fail before allocation')
