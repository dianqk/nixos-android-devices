/* SPDX-License-Identifier: GPL-2.0+ */
/* Compile the production firmware transport against synchronous SCSI/DM mocks. */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32;
typedef uint64_t u64;
typedef int efi_status_t;
#define EFIAPI
#define CONFIG_EFI_BOOT_CHOICE_DURABLE_IO 1
#define IS_ENABLED(x) (x)
#define UCLASS_BLK 1
#define UCLASS_SCSI 2
#define UCLASS_UFS 3
#define DMA_NONE 0
#define EFI_SUCCESS 0
#define EFI_DEVICE_ERROR 1
#define EFI_UNSUPPORTED 2
#define EFI_MEDIA_CHANGED 3
#define EFI_NO_MEDIA 4
#define EFI_INVALID_PARAMETER 5
#define EFI_ENTRY(...) do {} while (0)
#define EFI_EXIT(x) (x)
#define container_of(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
struct udevice { struct udevice *parent; int cls; };
struct blk_desc { struct udevice *bdev; unsigned target, lun; };
struct scsi_cmd { unsigned char cmd[16]; unsigned cmdlen, target, lun, dma_dir, datalen; void *pdata; };
struct efi_boot_choice_io {
 u32 revision,size; u64 flags,controller; u32 target,lun;
 efi_status_t (*sync)(struct efi_boot_choice_io *,u32);
};
struct efi_disk_obj {
 struct efi_boot_choice_io choice_io;
 struct blk_desc *choice_desc;
 struct { int media_present; u32 media_id; } media;
};
static int result, calls;
static struct udevice *expected_scsi;
static unsigned expected_lun;
static int device_get_uclass_id(struct udevice *d) { return d->cls; }
static int scsi_exec(struct udevice *d, struct scsi_cmd *c) {
 const unsigned char cdb[16] = {0x35};
 assert(d==expected_scsi);
 assert(!memcmp(c->cmd,cdb,sizeof(cdb)));
 assert(c->cmdlen==10 && c->target==0 && c->lun==expected_lun);
 assert(c->dma_dir==DMA_NONE && c->datalen==0 && !c->pdata);
 calls++;
 return result; /* only returns when completed, or failed */
}
#include "../pkgs/boot-choice-context/durable-io.h"
int main(void) {
 struct udevice ufs={NULL,UCLASS_UFS}, scsi={&ufs,UCLASS_SCSI}, blk={&scsi,UCLASS_BLK};
 struct blk_desc desc={&blk,0,0};
 struct efi_disk_obj disk={.choice_desc=&desc,.media={1,7}};
 disk.choice_io.controller=(uintptr_t)&ufs;
 expected_scsi=&scsi;
 for(unsigned lun=0;lun<8;lun++) {
  desc.lun=disk.choice_io.lun=expected_lun=lun;
  result=0; assert(choice_sync(&disk.choice_io,7)==EFI_SUCCESS);
  result=-1; assert(choice_sync(&disk.choice_io,7)==EFI_DEVICE_ERROR);
  result=-110; assert(choice_sync(&disk.choice_io,7)==EFI_DEVICE_ERROR);
 }
 assert(calls==24);
 assert(choice_sync(NULL,7)==EFI_INVALID_PARAMETER);
 assert(choice_sync(&disk.choice_io,8)==EFI_MEDIA_CHANGED);
 disk.media.media_present=0;
 assert(choice_sync(&disk.choice_io,7)==EFI_NO_MEDIA);
 disk.media.media_present=1;
 disk.choice_io.controller++;
 assert(choice_sync(&disk.choice_io,7)==EFI_DEVICE_ERROR);
 desc.lun=8; assert(efi_boot_choice_sync(&desc)==EFI_UNSUPPORTED);
 desc.lun=0;desc.target=1;assert(efi_boot_choice_sync(&desc)==EFI_UNSUPPORTED);
 desc.target=0;ufs.cls=99;assert(efi_boot_choice_sync(&desc)==EFI_UNSUPPORTED);
 ufs.cls=UCLASS_UFS;scsi.cls=99;assert(efi_boot_choice_sync(&desc)==EFI_UNSUPPORTED);
 assert(calls==24);
 puts("PASS exact CDB, all ordinary LUNs, no IMMED/range, scope, completion failure, media/controller changes");
}
