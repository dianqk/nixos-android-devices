// SPDX-License-Identifier: GPL-2.0-only
/* GNU-EFI ABI transport only. All storage/selection authority lives in Rust. */
#include <efi.h>
#include <efilib.h>
#include "../../tools/boot-choice/context-wire.h"
_Static_assert(BOOT_CHOICE_PROVENANCE_SIZE==96 && BOOT_CHOICE_PROVENANCE_ATTRIBUTES==6, "provenance ABI");
static EFI_SYSTEM_TABLE *st;
static EFI_HANDLE self;
static EFI_BLOCK_IO *disk;
static UINT32 media;
static UINTN block;
static EFI_LBA last;
/* ABI shared with Dodge firmware; opaque identity comes from actual DM UFS
 * ancestry. Synthetic vendor paths cannot safely identify sibling LUNs. */
typedef struct choice_io CHOICE_IO;
struct choice_io {
    UINT32 revision, size;
    UINT64 flags, controller;
    UINT32 target, lun;
    EFI_STATUS (EFIAPI *sync)(CHOICE_IO *, UINT32);
};
_Static_assert(sizeof(CHOICE_IO)==40, "choice I/O ABI");
static EFI_GUID choice_guid={0x6b58f5b8,0x18c6,0x47ad,{0x90,0x45,0x55,0x46,0x53,0x49,0x4f,0x31}};
struct member { EFI_BLOCK_IO *io; UINT32 media; UINTN block; EFI_LBA last; };
static struct member members[8], esp_media;
static UINTN member_count;
static CHOICE_IO *member_sync[8], *esp_sync;
static EFI_FILE_HANDLE root;
static CHAR16 journal_path[]=L"\\EFI\\android-devices\\boot-choice.undo";
static CHAR16 full_journal_path[]=L"\\EFI\\android-devices\\boot-choice.install.undo";
static BOOLEAN unchanged(struct member *m) {
    return m->io && m->io->Media && m->io->Media->MediaPresent &&
        m->io->Media->MediaId==m->media && m->io->Media->BlockSize==m->block &&
        m->io->Media->LastBlock==m->last;
}
static void snapshot(struct member *m, EFI_BLOCK_IO *io) {
    m->io=io;m->media=io->Media->MediaId;m->block=io->Media->BlockSize;m->last=io->Media->LastBlock;
}
UINTN bc_select(UINTN i, UINT64 *geometry) {
    if (i>=member_count || !unchanged(&esp_media)) return 1;
    for(UINTN j=0;j<member_count;j++) if(!unchanged(&members[j])) return 1;
    disk=members[i].io;media=members[i].media;block=members[i].block;last=members[i].last;
    geometry[0]=block;geometry[1]=last;return 0;
}
static BOOLEAN supported(CHOICE_IO *p) {
    return p && p->revision==1 && p->size==40 && p->flags==3 &&
        p->controller && p->target==0 && p->lun<8 && p->sync;
}
extern UINT32 bc_run(UINT8 *, UINTN, const UINT8 *, UINTN);
void *bc_alloc(UINTN n) { void *p = NULL; if (EFI_ERROR(st->BootServices->AllocatePool(EfiLoaderData,n,&p))) return NULL; return p; }
void bc_error(const UINT8 *bytes, UINTN length) {
    Print(L"boot-choice: ");for(UINTN i=0;i<length;i++)Print(L"%c",(UINTN)bytes[i]);Print(L"\r\n");
}
void bc_free(void *p) { if (p && EFI_ERROR(st->BootServices->FreePool(p))) Print(L"boot-choice: pool release failed\r\n"); }
__attribute__((noreturn)) void bc_abort(void) {
    Print(L"boot-choice: Rust invariant failure; refusing boot\r\n");
    st->BootServices->Exit(self,EFI_ABORTED,0,NULL);
    /* Exit must not return on a valid image; a broken implementation is fatal,
     * never a reset/chainload or an infinite loop. */
    __builtin_trap();
}
static UINTN transfer(UINT64 lba, UINTN n, void *out, BOOLEAN write) {
    if (!disk || !disk->Media || !unchanged(&esp_media)) return 1;
    EFI_BLOCK_IO_MEDIA *m=disk->Media;
    void *aligned=NULL, *allocation=NULL;
    UINTN align=m->IoAlign>8?m->IoAlign:8;
    EFI_STATUS s;
    if (!m->MediaPresent || m->MediaId!=media || m->BlockSize!=block || m->LastBlock!=last ||
        (write && m->ReadOnly) || !n || n%block || lba>last || n/block-1>last-lba ||
        align>65536 || (align&(align-1)) || n>~(UINTN)0-align) return 1;
    allocation=bc_alloc(n+align);
    if (!allocation) return 1;
    aligned=(void *)(((UINTN)allocation+align-1)&~(align-1));
    if(write) {CopyMem(aligned,out,n);s=disk->WriteBlocks(disk,media,lba,n,aligned);}
    else {s=disk->ReadBlocks(disk,media,lba,n,aligned);if(!EFI_ERROR(s))CopyMem(out,aligned,n);}
    bc_free(allocation);return EFI_ERROR(s)?1:0;
}
UINTN bc_read(UINT64 lba, UINTN n, void *out) {return transfer(lba,n,out,FALSE);}
UINTN bc_write(UINT64 lba, UINTN n, void *in) {return transfer(lba,n,in,TRUE);}
static CHOICE_IO *selected_sync(void) {
    for(UINTN i=0;i<member_count;i++) if(members[i].io==disk && unchanged(&members[i]))return member_sync[i];
    return NULL;
}
UINTN bc_flush(void) {
    CHOICE_IO *p=selected_sync();
    return !p || !unchanged(&esp_media) || EFI_ERROR(p->sync(p,media)) ? 1:0;
}
static UINTN esp_flush(void) {
    return !unchanged(&esp_media) || !esp_sync || EFI_ERROR(esp_sync->sync(esp_sync,esp_media.media)) ? 1:0;
}
UINTN bc_probe(void) {
    EFI_FILE_HANDLE f=NULL;
    if(!root || !unchanged(&esp_media))return 1;
    /* Full-image undo belongs to the native owner. A valid no-op may still
     * chainload for native recovery, but no preference write/recovery may race
     * it. Only proven absence permits the first synchronization or write. */
    EFI_STATUS s=root->Open(root,&f,full_journal_path,EFI_FILE_MODE_READ,0);
    if(s==EFI_SUCCESS) {f->Close(f);return 1;}
    if(s!=EFI_NOT_FOUND)return 1;
    if(bc_flush())return 1;
    return esp_flush();
}
/* 0 success, 2 absent, 1 failure. File bytes are interpreted only by Rust. */
UINTN bc_journal_read(void *out, UINTN cap, UINTN *length) {
    EFI_FILE_HANDLE f=NULL;UINTN n=cap;EFI_STATUS s;
    if(!root || !unchanged(&esp_media))return 1;
    s=root->Open(root,&f,journal_path,EFI_FILE_MODE_READ,0);
    if(s==EFI_NOT_FOUND)return 2;
    if(EFI_ERROR(s))return 1;
    s=f->Read(f,&n,out);
    if(!EFI_ERROR(s) && n==cap) {UINT8 extra;UINTN one=1;s=f->Read(f,&one,&extra);if(!EFI_ERROR(s) && one)s=EFI_BAD_BUFFER_SIZE;}
    EFI_STATUS close=f->Close(f);*length=n;
    return EFI_ERROR(s)||EFI_ERROR(close)?1:0;
}
UINTN bc_journal_create(void *bytes, UINTN length) {
    EFI_FILE_HANDLE f=NULL;UINTN n=length;EFI_STATUS s;
    if(!root || !unchanged(&esp_media))return 1;
    /* Do not truncate or overwrite any pre-existing evidence. */
    s=root->Open(root,&f,journal_path,EFI_FILE_MODE_READ,0);
    if(!EFI_ERROR(s)) {f->Close(f);return 1;}
    if(s!=EFI_NOT_FOUND)return 1;
    s=root->Open(root,&f,journal_path,EFI_FILE_MODE_READ|EFI_FILE_MODE_WRITE|EFI_FILE_MODE_CREATE,0);
    if(EFI_ERROR(s))return 1;
    s=f->Write(f,&n,bytes);
    if(!EFI_ERROR(s) && n!=length)s=EFI_DEVICE_ERROR;
    if(!EFI_ERROR(s))s=f->Flush(f);
    if(!EFI_ERROR(s) && esp_flush())s=EFI_DEVICE_ERROR;
    EFI_STATUS close=f->Close(f);
    return EFI_ERROR(s)||EFI_ERROR(close)?1:0;
}
UINTN bc_journal_remove(void) {
    EFI_FILE_HANDLE f=NULL;EFI_STATUS s;
    if(!root || !unchanged(&esp_media))return 1;
    s=root->Open(root,&f,journal_path,EFI_FILE_MODE_READ|EFI_FILE_MODE_WRITE,0);
    if(EFI_ERROR(s))return 1;
    /* EFI Delete closes its handle, even on failure. Warning is not success. */
    s=f->Delete(f);if(s!=EFI_SUCCESS)return 1;
    return esp_flush();
}
static BOOLEAN same_guid(EFI_GUID *a, EFI_GUID *b) { return CompareMem(a,b,sizeof(*a))==0; }
EFI_STATUS EFIAPI efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *table) {
    EFI_GUID context_guid=BOOT_CHOICE_CONTEXT_GUID_INIT;
    EFI_GUID loaded_guid=LOADED_IMAGE_PROTOCOL, block_guid=BLOCK_IO_PROTOCOL;
    EFI_LOADED_IMAGE *loaded=NULL;
    EFI_DEVICE_PATH *file=NULL;
    CHOICE_IO *esp_group=NULL; EFI_BLOCK_IO *esp_io=NULL;
    EFI_HANDLE *handles=NULL,child=NULL;
    UINTN count=0,contexts=0;
    UINT32 lun_mask=0;
    UINT8 context[96];
    EFI_STATUS status;
    if (!table || !table->ConOut || !table->BootServices ||
        table->NumberOfTableEntries>256 ||
        (table->NumberOfTableEntries && !table->ConfigurationTable)) return EFI_UNSUPPORTED;
    st=table;self=image;InitializeLib(image,table);
    status=st->BootServices->HandleProtocol(image,&loaded_guid,(void **)&loaded);
    if (EFI_ERROR(status)) return status;
    if (!loaded || !loaded->DeviceHandle) return EFI_UNSUPPORTED;
    member_count=0;root=NULL;
    for (UINTN i=0;i<st->NumberOfTableEntries;i++) {
        if (same_guid(&context_guid,&st->ConfigurationTable[i].VendorGuid)) {
            if (!st->ConfigurationTable[i].VendorTable) return EFI_INVALID_PARAMETER;
            CopyMem(context,st->ConfigurationTable[i].VendorTable,sizeof(context));contexts++;
        }
    }
    if (contexts!=1) {Print(L"boot-choice: missing/duplicate context\r\n");return EFI_UNSUPPORTED;}
    status=st->BootServices->HandleProtocol(loaded->DeviceHandle,&choice_guid,(void **)&esp_group);
    if (EFI_ERROR(status) || !supported(esp_group)) return EFI_UNSUPPORTED;
    status=st->BootServices->HandleProtocol(loaded->DeviceHandle,&block_guid,(void **)&esp_io);
    if (EFI_ERROR(status) || !esp_io || !esp_io->Media || !esp_io->Media->MediaPresent) return EFI_UNSUPPORTED;
    snapshot(&esp_media,esp_io);esp_sync=esp_group;
    EFI_GUID fs_guid=SIMPLE_FILE_SYSTEM_PROTOCOL;
    EFI_FILE_IO_INTERFACE *fs=NULL;
    status=st->BootServices->HandleProtocol(loaded->DeviceHandle,&fs_guid,(void **)&fs);
    if(EFI_ERROR(status) || !fs)return EFI_UNSUPPORTED;
    status=fs->OpenVolume(fs,&root);if(EFI_ERROR(status))return status;
    status=st->BootServices->LocateHandleBuffer(ByProtocol,&block_guid,NULL,&count,&handles);
    if (EFI_ERROR(status)) return status;
    if(!handles || !count || count>256) {if(handles)st->BootServices->FreePool(handles);return EFI_UNSUPPORTED;}
    for (UINTN i=0;i<count;i++) {
        EFI_BLOCK_IO *candidate=NULL; CHOICE_IO *group=NULL;
        status=st->BootServices->HandleProtocol(handles[i],&choice_guid,(void **)&group);
        if (EFI_ERROR(status)) continue;
        if (!supported(group)) {member_count=0;break;}
        if (group->controller!=esp_group->controller) continue;
        status=st->BootServices->HandleProtocol(handles[i],&block_guid,(void **)&candidate);
        if (EFI_ERROR(status) || !candidate || !candidate->Media) {member_count=0;break;}
        if(candidate->Media->LogicalPartition) continue;
        if (!candidate->Media->MediaPresent || member_count==8 || (lun_mask&(1U<<group->lun))) {member_count=0;break;}
        BOOLEAN duplicate=FALSE;
        for(UINTN j=0;j<member_count;j++) if(members[j].io==candidate) duplicate=TRUE;
        if(duplicate) {member_count=0;break;}
        lun_mask|=1U<<group->lun;
        member_sync[member_count]=group;
        snapshot(&members[member_count++],candidate);
    }
    status=st->BootServices->FreePool(handles);if (EFI_ERROR(status)) return status;
    if(!member_count || !(lun_mask&(1U<<esp_group->lun)))return EFI_UNSUPPORTED;
    UINT32 result=bc_run(context,member_count,loaded->LoadOptions,loaded->LoadOptionsSize);
    status=root->Close(root);root=NULL;
    if(result==1 || EFI_ERROR(status)) {Print(L"boot-choice: transaction/authority failed; no boot action\r\n");return EFI_ABORTED;}
    if(result==2) {
        Print(L"boot-choice: Android committed; resetting\r\n");
        st->RuntimeServices->ResetSystem(EfiResetCold,EFI_SUCCESS,0,NULL);
        Print(L"boot-choice: ResetSystem returned; choice remains committed\r\n");return EFI_DEVICE_ERROR;
    }
    /* The next manual invocation must observe the sequence just committed,
     * not the original selector's stale observation. Table lifetime is EFI. */
    UINT8 *fresh=bc_alloc(sizeof(context));if(!fresh)return EFI_OUT_OF_RESOURCES;
    CopyMem(fresh,context,sizeof(context));
    status=st->BootServices->InstallConfigurationTable(&context_guid,fresh);
    if(EFI_ERROR(status)){bc_free(fresh);return status;}
    /* Memory-store provenance survives ExitBootServices for Linux readers.
     * Exact BS|RT, never NON_VOLATILE: no preference/NVRAM/ESP write. Publish
     * only after Rust refreshed the context to the committed sequence. A failed
     * publication refuses chainload; any already committed choice stays so. */
    const char name[]=BOOT_CHOICE_PROVENANCE_NAME;
    CHAR16 variable[sizeof(name)];
    for(UINTN i=0;i<sizeof(name);i++)variable[i]=(UINT8)name[i];
    status=st->RuntimeServices->SetVariable(variable,&context_guid,
        BOOT_CHOICE_PROVENANCE_ATTRIBUTES,sizeof(context),context);
    if(EFI_ERROR(status))return status;
    UINT8 observed[BOOT_CHOICE_PROVENANCE_SIZE];
    UINTN observed_size=sizeof(observed);UINT32 attributes=0;
    status=st->RuntimeServices->GetVariable(variable,&context_guid,&attributes,
        &observed_size,observed);
    if(EFI_ERROR(status))return status;
    if(attributes!=BOOT_CHOICE_PROVENANCE_ATTRIBUTES || observed_size!=sizeof(context) ||
       CompareMem(observed,context,sizeof(context)))return EFI_COMPROMISED_DATA;
    UINT64 geometry[2];if(bc_select(0,geometry))return EFI_MEDIA_CHANGED;
    Print(L"boot-choice: verified U-Boot; chainloading\r\n");
    file=FileDevicePath(loaded->DeviceHandle,L"\\EFI\\BOOT\\BOOTAA64.EFI");
    if(!file)return EFI_OUT_OF_RESOURCES;
    status=st->BootServices->LoadImage(FALSE,image,file,NULL,0,&child);
    EFI_STATUS released=st->BootServices->FreePool(file);
    if(EFI_ERROR(status))return status;
    if(EFI_ERROR(released)){EFI_STATUS unloaded=st->BootServices->UnloadImage(child);return EFI_ERROR(unloaded)?unloaded:released;}
    status=st->BootServices->StartImage(child,NULL,NULL);
    EFI_STATUS unloaded=st->BootServices->UnloadImage(child);
    return EFI_ERROR(status)?status:(EFI_ERROR(unloaded)?unloaded:EFI_ABORTED);
}
/* Compiler memory intrinsics, not libc/syscalls. */
void *memmove(void *d,const void *s,UINTN n){UINT8 *a=d;const UINT8 *b=s;if((UINTN)a<(UINTN)b){for(UINTN i=0;i<n;i++)a[i]=b[i];}else{while(n){n--;a[n]=b[n];}}return d;}
int memcmp(const void *a,const void *b,UINTN n){const UINT8 *x=a,*y=b;for(UINTN i=0;i<n;i++)if(x[i]!=y[i])return x[i]<y[i]?-1:1;return 0;}

int bcmp(const void *a,const void *b,UINTN n){return memcmp(a,b,n);}
