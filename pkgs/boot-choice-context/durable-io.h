/* SPDX-License-Identifier: GPL-2.0+ */
/* Linked positive capability marker; read when constructing each protocol. */
const volatile u32 android_devices_boot_choice_durable_io_abi_v1 = 1;

/* Actual DM ancestry, not synthetic vendor device-path prefixes. UFS binds a
 * SCSI child and ordinary data LUN block children. Reject all other ancestry. */
static struct udevice *choice_controller(struct blk_desc *desc)
{
 struct udevice *blk = desc ? desc->bdev : NULL;
 if (!blk || device_get_uclass_id(blk) != UCLASS_BLK ||
     !blk->parent || device_get_uclass_id(blk->parent) != UCLASS_SCSI ||
     !blk->parent->parent ||
     device_get_uclass_id(blk->parent->parent) != UCLASS_UFS ||
     desc->target != 0 || desc->lun > 7)
  return NULL;
 return blk->parent->parent;
}

/* No IMMED, no range: complete the whole corresponding ordinary LU. */
efi_status_t efi_boot_choice_sync(struct blk_desc *desc)
{
 struct scsi_cmd cmd = { 0 };
 if (!IS_ENABLED(CONFIG_EFI_BOOT_CHOICE_DURABLE_IO) ||
     !choice_controller(desc))
  return EFI_UNSUPPORTED;
 cmd.cmd[0] = 0x35; /* SYNCHRONIZE CACHE(10), IMMED=0 */
 cmd.cmdlen = 10;
 cmd.target = desc->target;
 cmd.lun = desc->lun;
 cmd.dma_dir = DMA_NONE;
 return scsi_exec(desc->bdev->parent, &cmd) ? EFI_DEVICE_ERROR : EFI_SUCCESS;
}

static efi_status_t EFIAPI choice_sync(struct efi_boot_choice_io *this,
                                      u32 media_id)
{
 struct efi_disk_obj *disk;
 efi_status_t ret;
 EFI_ENTRY("%p, %x", this, media_id);
 if (!this)
  return EFI_EXIT(EFI_INVALID_PARAMETER);
 disk = container_of(this, struct efi_disk_obj, choice_io);
 if (!disk->media.media_present)
  return EFI_EXIT(EFI_NO_MEDIA);
 if (disk->media.media_id != media_id)
  return EFI_EXIT(EFI_MEDIA_CHANGED);
 if ((u64)(uintptr_t)choice_controller(disk->choice_desc) != this->controller ||
     disk->choice_desc->lun != this->lun ||
     disk->choice_desc->target != this->target)
  return EFI_EXIT(EFI_DEVICE_ERROR);
 ret = efi_boot_choice_sync(disk->choice_desc);
 return EFI_EXIT(ret);
}
