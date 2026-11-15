/* SPDX-License-Identifier: GPL-2.0-only */
/* Executes production efi_main -> Rust staticlib -> fake firmware services.
 * No device handles, system reboot, Linux disk I/O or firmware emulator. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define _EFISTDARG_H_
#include <stdarg.h>
typedef va_list ms_va_list;
#define GNU_EFI_SETJMP_H
#include <setjmp.h>
#define InitializeLib test_initialize
#define Print test_print
#define FileDevicePath test_path
#include "../pkgs/boot-choice-efi/transport.c"
void test_initialize(EFI_HANDLE h,EFI_SYSTEM_TABLE *t){(void)h;(void)t;}
UINTN test_print(const CHAR16 *s,...){(void)s;return 0;}
EFI_DEVICE_PATH *test_path(EFI_HANDLE h,CHAR16 *p){(void)p;assert(h==(void *)2);return bc_alloc(sizeof(EFI_DEVICE_PATH));}
VOID EFIAPI CopyMem(VOID *d,VOID *s,UINTN n){memcpy(d,s,n);}
INTN CompareMem(const VOID *a,const VOID *b,UINTN n){return memcmp(a,b,n);}
static UINT8 *boot_bytes,*initial;static UINTN disk_size;
static EFI_BLOCK_IO_MEDIA bm,em,rm;
static EFI_BLOCK_IO boot_io,esp_io,raw_io;
static CHOICE_IO bp,ep,rp;
static EFI_LOADED_IMAGE loaded;
static EFI_BOOT_SERVICES bs;static EFI_RUNTIME_SERVICES rs;static EFI_SYSTEM_TABLE table;
static EFI_CONFIGURATION_TABLE cfg;
static EFI_SIMPLE_TEXT_OUT_PROTOCOL console;
static EFI_FILE_PROTOCOL volume,jfile;
static EFI_FILE_IO_INTERFACE fs;
static UINT8 ctx[96],base_ctx[96],journal_bytes[8448];
static UINTN journal_length,cursor;
#ifdef USE_PRODUCTION_OPEN
extern unsigned long production_open_status(unsigned,int,int);
static unsigned production_fault;
static UINT8 retained_journal[8448];
#endif
static unsigned calls,fail_at,boot_writes,resets,starts,esp_syncs,boot_syncs;
static unsigned provenance_fault,provenance_present;static UINT8 provenance_bytes[96];
static unsigned journal_verified,flushes,write_offsets[8],corrupt_readback,rollback_failure,return_reset,alloc_fail,short_write;
static jmp_buf action;
static int fault(void){return ++calls==fail_at;}
static EFI_STATUS EFIAPI pool(EFI_MEMORY_TYPE type,UINTN n,VOID **p){(void)type;if(alloc_fail){alloc_fail--;return EFI_OUT_OF_RESOURCES;}*p=malloc(n);return *p?EFI_SUCCESS:EFI_OUT_OF_RESOURCES;}
static EFI_STATUS EFIAPI release(VOID *p){free(p);return EFI_SUCCESS;}
static EFI_STATUS EFIAPI sync_media(CHOICE_IO *p,UINT32 id){assert(id==1);if(p==&bp)boot_syncs++;else esp_syncs++;return fault()?EFI_DEVICE_ERROR:EFI_SUCCESS;}
static EFI_STATUS EFIAPI read_blocks(EFI_BLOCK_IO *io,UINT32 id,EFI_LBA lba,UINTN n,VOID *p){
 assert(id==1);if(fault())return EFI_DEVICE_ERROR;
 if(io==&boot_io){assert(lba*512+n<=disk_size);memcpy(p,boot_bytes+lba*512,n);if(boot_writes && corrupt_readback && n>4096){((UINT8 *)p)[0]^=1;corrupt_readback=0;}}
 else memset(p,0,n);
 return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI write_blocks(EFI_BLOCK_IO *io,UINT32 id,EFI_LBA lba,UINTN n,VOID *p){
 assert(io==&boot_io && id==1 && n==4096 && journal_length==8448 && journal_verified && esp_syncs && boot_syncs);
 UINTN start=(64+(disk_size/512-256)/2)*512;
 UINT32 kernel;UINT64 pages;memcpy(&kernel,initial+start+8,4);
 UINTN body=4096+kernel;memcpy(&pages,initial+start+body-4096+40,8);
 assert(lba*512==start+pages || lba*512==start+pages+4096 || lba*512==start+body);
 assert(lba*512+n<=disk_size);if(boot_writes<8)write_offsets[boot_writes]=(unsigned)(lba*512);
 boot_writes++;if(fault() || (rollback_failure && boot_writes>2))return EFI_DEVICE_ERROR;
 memcpy(boot_bytes+lba*512,p,n);return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI close_file(EFI_FILE_PROTOCOL *f){(void)f;return fault()?EFI_DEVICE_ERROR:EFI_SUCCESS;}
static EFI_STATUS EFIAPI file_read(EFI_FILE_PROTOCOL *f,UINTN *n,VOID *out){
 assert(f==&jfile);if(fault())return EFI_DEVICE_ERROR;
 UINTN left=journal_length-cursor;if(*n>left)*n=left;memcpy(out,journal_bytes+cursor,*n);cursor+=*n;
 if(cursor==journal_length && journal_length)journal_verified=1;
 return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI file_write(EFI_FILE_PROTOCOL *f,UINTN *n,VOID *in){assert(f==&jfile);if(fault())return EFI_DEVICE_ERROR;assert(*n<=sizeof(journal_bytes));if(short_write)(*n)--;memcpy(journal_bytes,in,*n);journal_length=*n;
#ifdef USE_PRODUCTION_OPEN
 memcpy(retained_journal,in,*n);
#endif
return EFI_SUCCESS;}
static EFI_STATUS EFIAPI file_flush(EFI_FILE_PROTOCOL *f){assert(f==&jfile);flushes++;return fault()?EFI_DEVICE_ERROR:EFI_SUCCESS;}
static EFI_STATUS EFIAPI file_delete(EFI_FILE_PROTOCOL *f){assert(f==&jfile);if(fault())return EFI_DEVICE_ERROR;journal_length=0;return EFI_SUCCESS;}
static unsigned full_present;
static EFI_STATUS full_open_status;
static EFI_STATUS EFIAPI file_open(EFI_FILE_PROTOCOL *f,EFI_FILE_PROTOCOL **out,CHAR16 *path,UINT64 mode,UINT64 attrs){
 assert(f==&volume && !attrs);
 if(!CompareMem(path,full_journal_path,sizeof(full_journal_path))){
  if(fault())return EFI_DEVICE_ERROR;
  if(full_open_status)return full_open_status;
  if(full_present){*out=&jfile;return EFI_SUCCESS;}
  return EFI_NOT_FOUND;
 }
 assert(!CompareMem(path,journal_path,sizeof(journal_path)));
 if(fault())return EFI_DEVICE_ERROR;
#ifdef USE_PRODUCTION_OPEN
 EFI_STATUS actual=production_open_status(production_fault,journal_length!=0,!!(mode&EFI_FILE_MODE_CREATE));
 if(actual!=EFI_SUCCESS)return actual;
#endif
 if(!journal_length && !(mode&EFI_FILE_MODE_CREATE))return EFI_NOT_FOUND;
 cursor=0;*out=&jfile;return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI open_volume(EFI_FILE_IO_INTERFACE *f,EFI_FILE_PROTOCOL **out){assert(f==&fs);*out=&volume;return EFI_SUCCESS;}
static EFI_STATUS EFIAPI handle(EFI_HANDLE h,EFI_GUID *g,VOID **out){
 EFI_GUID lg=LOADED_IMAGE_PROTOCOL,bg=BLOCK_IO_PROTOCOL,fg=SIMPLE_FILE_SYSTEM_PROTOCOL;
 if(h==(void *)1 && same_guid(g,&lg)){*out=&loaded;return EFI_SUCCESS;}
 if(h==(void *)2 && same_guid(g,&fg)){*out=&fs;return EFI_SUCCESS;}
 if(same_guid(g,&choice_guid)){*out=h==(void *)2?&ep:h==(void *)3?&bp:h==(void *)4?&rp:NULL;return *out?EFI_SUCCESS:EFI_UNSUPPORTED;}
 if(same_guid(g,&bg)){*out=h==(void *)2?&esp_io:h==(void *)3?&boot_io:h==(void *)4?&raw_io:NULL;return *out?EFI_SUCCESS:EFI_UNSUPPORTED;}
 return EFI_UNSUPPORTED;
}
static EFI_STATUS EFIAPI locate(EFI_LOCATE_SEARCH_TYPE t,EFI_GUID *g,VOID *key,UINTN *n,EFI_HANDLE **out){
 (void)t;(void)g;(void)key;*n=3;*out=malloc(3*sizeof(EFI_HANDLE));(*out)[0]=(void *)2;(*out)[1]=(void *)3;(*out)[2]=(void *)4;return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI install_table(EFI_GUID *g,VOID *p){assert(same_guid(g,&cfg.VendorGuid));memcpy(ctx,p,96);cfg.VendorTable=ctx;free(p);return EFI_SUCCESS;}
static EFI_STATUS EFIAPI set_variable(CHAR16 *name,EFI_GUID *guid,UINT32 attrs,UINTN n,VOID *data){
 assert(name && same_guid(guid,&cfg.VendorGuid) && attrs==6 && n==96);
 assert(!CompareMem(name,L"AndroidDevicesBootContext",sizeof(L"AndroidDevicesBootContext")));
 if(provenance_fault==1)return EFI_DEVICE_ERROR;
 memcpy(provenance_bytes,data,96);provenance_present=1;return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI get_variable(CHAR16 *name,EFI_GUID *guid,UINT32 *attrs,UINTN *n,VOID *data){
 (void)name;assert(same_guid(guid,&cfg.VendorGuid) && *n==96 && provenance_present);
 if(provenance_fault==2)return EFI_DEVICE_ERROR;
 *attrs=provenance_fault==3?7:6;*n=provenance_fault==4?95:96;
 memcpy(data,provenance_bytes,*n);if(provenance_fault==5)((UINT8 *)data)[20]^=1;
 return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI load_image(BOOLEAN boot,EFI_HANDLE parent,EFI_DEVICE_PATH *path,VOID *src,UINTN n,EFI_HANDLE *child){assert(!boot && parent==(void *)1 && path && !src && !n);*child=(void *)5;return EFI_SUCCESS;}
static EFI_STATUS EFIAPI start_image(EFI_HANDLE h,UINTN *n,CHAR16 **out){assert(h==(void *)5 && !n && !out);assert(provenance_present && !memcmp(provenance_bytes,ctx,96));starts++;longjmp(action,1);}
static EFI_STATUS EFIAPI unload(EFI_HANDLE h){(void)h;return EFI_SUCCESS;}
static EFI_STATUS EFIAPI reset_system(EFI_RESET_TYPE type,EFI_STATUS status,UINTN n,CHAR16 *data){assert(type==EfiResetCold && !status && !n && !data);resets++;if(!return_reset)longjmp(action,2);return EFI_DEVICE_ERROR;}
static EFI_STATUS EFIAPI exit_image(EFI_HANDLE h,EFI_STATUS s,UINTN n,CHAR16 *p){(void)h;(void)s;(void)n;(void)p;longjmp(action,3);}
static UINT32 crc32(const UINT8 *b,UINTN n){UINT32 c=~0U;for(UINTN i=0;i<n;i++){c^=i>=76?0:b[i];for(int j=0;j<8;j++)c=(c>>1)^(0xedb88320U&-(c&1));}return ~c;}
static void intent(unsigned stored,unsigned selected){memcpy(ctx,base_ctx,96);memcpy(ctx+72,&stored,4);memcpy(ctx+76,&selected,4);unsigned change=stored!=selected;memcpy(ctx+80,&change,4);UINT32 sum=crc32(ctx+16,80);memcpy(ctx+92,&sum,4);}
static int run(void){int jumped=setjmp(action);if(jumped)return jumped;EFI_STATUS s=efi_main((void *)1,&table);assert(EFI_ERROR(s));return 0;}
static void fresh(void){full_present=0;full_open_status=EFI_SUCCESS;provenance_fault=provenance_present=0;memcpy(boot_bytes,initial,disk_size);memcpy(ctx,base_ctx,96);journal_length=cursor=0;calls=fail_at=boot_writes=resets=starts=esp_syncs=boot_syncs=journal_verified=flushes=corrupt_readback=rollback_failure=return_reset=alloc_fail=short_write=0;loaded.LoadOptionsSize=0;}
static void read_file(const char *dir,const char *name,UINT8 **out,UINTN *n){char p[4096];snprintf(p,sizeof(p),"%s/%s",dir,name);FILE *f=fopen(p,"rb");assert(f);fseek(f,0,SEEK_END);*n=ftell(f);rewind(f);*out=malloc(*n);assert(fread(*out,1,*n,f)==*n);fclose(f);}
int main(int argc,char **argv){
 assert(argc==2);UINT8 *token;UINTN n;read_file(argv[1],"disk.bin",&initial,&disk_size);read_file(argv[1],"context.bin",&token,&n);assert(n==96);memcpy(base_ctx,token,96);free(token);boot_bytes=malloc(disk_size);
 bm=(EFI_BLOCK_IO_MEDIA){.MediaId=1,.MediaPresent=TRUE,.BlockSize=512,.LastBlock=disk_size/512-1};em=bm;rm=bm;rm.LastBlock=129;
 boot_io=(EFI_BLOCK_IO){.Media=&bm,.ReadBlocks=read_blocks,.WriteBlocks=write_blocks};esp_io=boot_io;esp_io.Media=&em;raw_io=boot_io;raw_io.Media=&rm;
 ep=(CHOICE_IO){.revision=1,.size=40,.flags=3,.controller=1,.target=0,.lun=0,.sync=sync_media};bp=ep;bp.lun=3;rp=ep;rp.lun=1;
 loaded.DeviceHandle=(void *)2;bs.AllocatePool=pool;bs.FreePool=release;bs.HandleProtocol=handle;bs.LocateHandleBuffer=locate;bs.InstallConfigurationTable=install_table;bs.LoadImage=load_image;bs.StartImage=start_image;bs.UnloadImage=unload;bs.Exit=exit_image;rs.ResetSystem=reset_system;rs.SetVariable=set_variable;rs.GetVariable=get_variable;
 cfg.VendorGuid=(EFI_GUID){0x9fae4b51,0x9d56,0x4e38,{0xa7,0xc1,0x51,0x64,0xe8,0x4d,0x60,0x82}};cfg.VendorTable=ctx;
 table.BootServices=&bs;table.RuntimeServices=&rs;table.ConOut=&console;table.NumberOfTableEntries=1;table.ConfigurationTable=&cfg;
 volume.Open=file_open;volume.Close=close_file;jfile.Close=close_file;jfile.Read=file_read;jfile.Write=file_write;jfile.Flush=file_flush;jfile.Delete=file_delete;fs.OpenVolume=open_volume;
 fresh();assert(run()==1 && starts==1 && !resets && !boot_writes && !journal_length && !esp_syncs && !boot_syncs);
 for(unsigned i=1;i<=5;i++){fresh();provenance_fault=i;assert(run()==0 && !starts && !resets && !boot_writes && !esp_syncs && !boot_syncs);}
 // A pending full-image operation blocks preference synchronization/writes,
 // but valid no-op boot remains available to the native recovery owner.
 fresh();full_present=1;assert(run()==1 && starts==1 && !boot_writes && !esp_syncs && !boot_syncs);
 fresh();full_present=1;intent(1,0);assert(run()==0 && !starts && !resets && !boot_writes && !esp_syncs && !boot_syncs);
 EFI_STATUS full_errors[]={EFI_DEVICE_ERROR,EFI_OUT_OF_RESOURCES,EFI_INVALID_PARAMETER,EFI_UNSUPPORTED};
 for(unsigned i=0;i<sizeof(full_errors)/sizeof(full_errors[0]);i++){fresh();full_open_status=full_errors[i];intent(1,0);assert(run()==0 && !boot_writes && !starts && !resets && !esp_syncs && !boot_syncs);}
 fresh();intent(1,0);assert(run()==2 && resets==1 && !starts && boot_writes==2 && !journal_length && flushes==1);
 unsigned success_calls=calls;
#ifdef USE_PRODUCTION_OPEN
 UINT8 pending[8448];memcpy(pending,retained_journal,sizeof(pending));
 unsigned open_faults[]={1,2,3,4,5,7,8,9,10,12};
 for(unsigned i=0;i<sizeof(open_faults)/sizeof(open_faults[0]);i++){
  fresh();memcpy(journal_bytes,pending,sizeof(pending));journal_length=sizeof(pending);
  production_fault=open_faults[i];fprintf(stderr,"pending journal / actual firmware Open fault %u\n",production_fault);
  assert(run()==0 && !starts && !resets && !boot_writes && journal_length==sizeof(pending));
  assert(!memcmp(journal_bytes,pending,sizeof(pending)));
 }
 production_fault=0;
 // A successfully missing FAT lookup is the only absence case; ordinary
 // no-op still chains with no disk mutation or synchronization.
 fresh();assert(run()==1 && starts==1 && !boot_writes && !resets && !esp_syncs && !boot_syncs);
 fresh();intent(1,0);assert(run()==2);success_calls=calls;
#endif
assert(write_offsets[0]!=write_offsets[1]);assert(!memcmp(boot_bytes,initial,write_offsets[0]));
 // Every actual File Open/Read/Write/Flush/Close/Delete, both syncs and target
 // write operation fails once. Error paths must never reset or chainload.
 for(unsigned i=1;i<=success_calls;i++){fprintf(stderr,"EFI I/O fault %u/%u\n",i,success_calls);fresh();intent(1,0);fail_at=i;assert(run()==0);assert(!starts && !resets);}
 fresh();intent(1,0);corrupt_readback=1;assert(run()==0 && !resets && !starts && boot_writes==4 && !journal_length);assert(!memcmp(initial,boot_bytes,disk_size));
 fresh();intent(1,0);corrupt_readback=1;rollback_failure=1;assert(run()==0 && journal_length && !resets && !starts);
 fresh();intent(1,0);return_reset=1;assert(run()==0 && resets==1 && !starts && boot_writes==2 && !journal_length);assert(memcmp(initial,boot_bytes,disk_size));
 fresh();intent(1,0);short_write=1;assert(run()==0 && !boot_writes && !resets && !starts && journal_length==8447);
 fresh();ctx[92]^=1;assert(run()==0 && !boot_writes);
 fresh();loaded.LoadOptions=L"arbitrary";loaded.LoadOptionsSize=20;assert(run()==0 && !boot_writes);
 fresh();alloc_fail=1;assert(run()==0 && !boot_writes);
 // Up commit from Android, table refresh, then deliberate menu Android.
 fresh();intent(1,0);assert(run()==2);UINT8 android_ctx[96];memcpy(android_ctx,ctx,96);
 // Reset route does not publish a context; reconstruct the normal next boot
 // context from the committed image's owned sequence/mode.
 UINT64 seq;memcpy(&seq,ctx+64,8);seq++;memcpy(ctx+64,&seq,8);unsigned zero=0,one=1;memcpy(ctx+72,&zero,4);memcpy(ctx+76,&one,4);memcpy(ctx+80,&one,4);UINT32 sum=crc32(ctx+16,80);memcpy(ctx+92,&sum,4);
 boot_writes=resets=starts=0;assert(run()==1 && starts==1 && boot_writes==2);
 assert(provenance_present && !memcmp(provenance_bytes,ctx,96));
 UINT8 refreshed_ctx[96];memcpy(refreshed_ctx,ctx,96);assert(!memcmp(ctx+72,&one,4) && !memcmp(ctx+76,&one,4));
 loaded.LoadOptions=L"target=android";loaded.LoadOptionsSize=sizeof(L"target=android");boot_writes=resets=starts=0;assert(run()==2 && resets==1 && boot_writes==2 && !starts);
 memcpy(ctx,android_ctx,96);boot_writes=resets=starts=0;assert(run()==0 && !boot_writes && !starts && !resets);
 // Fresh Android->Up transition commits then publication fails: maintenance,
 // not unsafe chainload or rollback of an already committed preference.
 fresh();intent(1,0);assert(run()==2);
 memcpy(&seq,ctx+64,8);seq++;memcpy(ctx+64,&seq,8);memcpy(ctx+72,&zero,4);memcpy(ctx+76,&one,4);memcpy(ctx+80,&one,4);sum=crc32(ctx+16,80);memcpy(ctx+92,&sum,4);
 boot_writes=resets=starts=0;provenance_fault=1;assert(run()==0 && boot_writes==2 && !resets && !starts && !journal_length);
 (void)refreshed_ctx;printf("PASS full EFI entry: no-op, %u I/O fault points, rollback/corruption, reset-return, raw sibling, manual Android and Up context refresh\n",success_calls);
 free(boot_bytes);free(initial);return 0;
}
