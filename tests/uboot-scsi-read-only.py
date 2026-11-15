#!/usr/bin/env python3
"""Host-compile actual patched U-Boot guard/dispatch functions with mock transport.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-scsi-read-only.py PATCHED_UBOOT
Both the ordinary and read-only profiles are exercised; no device is accessed.
"""
from pathlib import Path
import re,subprocess,tempfile,os,sys
source=Path(sys.argv[1]).resolve()
def function(path,name):
 text=(source/path).read_text();match=re.search(r'(?m)^(?:static )?[a-zA-Z_][a-zA-Z0-9_ *]*\b'+name+r'\(',text);assert match,name;start=match.start()
 brace=text.index('{',start);depth=1;end=brace+1
 while depth:
  depth += (text[end]=='{')-(text[end]=='}');end+=1
 return text[start:end]+'\n'
scsi=function('drivers/scsi/scsi-uclass.c','scsi_exec')
write=function('drivers/block/blk-uclass.c','blk_write')
erase=function('drivers/block/blk-uclass.c','blk_erase')
efi=function('lib/efi_loader/efi_disk.c','efi_disk_write_blocks')
ufs=(source/'drivers/ufs/ufs-uclass.c').read_text()
def guard_prefix(name):
 f=function('drivers/ufs/ufs-uclass.c',name)
 end=f.index('return -EROFS;')+len('return -EROFS;')
 return f[:end]+'\n transported++; return 0;\n}\n'
query_guards='\n'.join(guard_prefix(n) for n in ['ufshcd_query_attr','__ufshcd_query_descriptor','ufshcd_query_flag'])
ufs_header=(source/'drivers/ufs/ufs.h').read_text()
enums='\n'.join(re.search(r'enum '+n+r' \{.*?\n\};',ufs_header,re.S)[0] for n in ['query_opcode','flag_idn','attr_idn','desc_idn'])
ops=re.search(r'static const struct blk_ops scsi_blk_ops = \{.*?\n\};',(source/'drivers/scsi/scsi.c').read_text(),re.S)[0]
boiler=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
typedef unsigned long ulong;
typedef unsigned long lbaint_t;
typedef uint8_t u8;
typedef uint32_t u32;
typedef uint64_t u64;
#define IS_ENABLED(x) (x)
#define CONFIG_BOUNCE_BUFFER 0
#define CONFIG_PHYS_64BIT 1
#define EFIAPI
#define EFI_ENTRY(...) \
	do {           \
	} while (0)
#define EFI_EXIT(x) (x)
#define EFI_SUCCESS 0
#define EFI_WRITE_PROTECTED 8
#define EFI_INVALID_PARAMETER 2
#define EFI_MEDIA_CHANGED 13
#define EFI_NO_MEDIA 12
#define EFI_DISK_WRITE 1
typedef unsigned long efi_status_t;
typedef unsigned long efi_uintn_t;
struct efi_block_io_media {
	bool read_only, media_present;
	u32 media_id, io_align, block_size;
	u64 last_block;
};
struct efi_block_io {
	struct efi_block_io_media *media;
};
struct scsi_cmd {
	unsigned char cmd[16];
	unsigned int cmdlen;
};
struct udevice;
struct blk_ops {
	ulong (*read)(struct udevice *, lbaint_t, lbaint_t, void *);
	ulong (*write)(struct udevice *, lbaint_t, lbaint_t, const void *);
	ulong (*erase)(struct udevice *, lbaint_t, lbaint_t);
};
struct scsi_ops {
	int (*exec)(struct udevice *, struct scsi_cmd *);
};
struct blk_desc {
	int uclass_id, devnum, blksz;
	bool bb;
};
struct udevice {
	const struct blk_ops *ops;
	struct scsi_ops *scsi;
	struct blk_desc *plat;
};
struct bbstate {
	void *bounce_buffer;
};
struct blk_bounce_buffer {
	struct udevice *dev;
	struct bbstate state;
};
#define GEN_BB_READ 0
struct ufs_hba {
	int unused;
};
struct ufs_query_req {
	int unused;
};
struct ufs_query_res {
	int unused;
};
#define QUERY_REQ_TIMEOUT 1
static int transported, cache_invalidated;
#define blk_get_ops(d) ((d)->ops)
#define scsi_get_ops(d) ((d)->scsi)
#define dev_get_uclass_plat(d) ((d)->plat)
#define blk_buffer_aligned 0
#define bounce_buffer_start_extalign(...) 0
#define bounce_buffer_stop(...) \
	do {                    \
	} while (0)
#define blkcache_invalidate(a, b) (cache_invalidated++)
static int transport(struct udevice *d, struct scsi_cmd *c)
{
	transported++;
	return 0;
}
static efi_status_t efi_disk_rw_blocks(struct efi_block_io *a, u32 b, u64 c,
				       efi_uintn_t d, void *e, int f)
{
	transported++;
	return EFI_SUCCESS;
}
static ulong scsi_read(struct udevice *d, lbaint_t a, lbaint_t b, void *c)
{
	return b;
}
static ulong scsi_write(struct udevice *d, lbaint_t a, lbaint_t b,
			const void *c)
{
	transported++;
	return b;
}
static ulong scsi_erase(struct udevice *d, lbaint_t a, lbaint_t b)
{
	transported++;
	return b;
}
'''
main=r'''
int main(void)
{
	struct scsi_ops so = { .exec = transport };
	struct blk_desc desc = { .blksz = 4096 };
	struct udevice dev = { .ops = &scsi_blk_ops,
			       .scsi = &so,
			       .plat = &desc };
	struct scsi_cmd cmd = { .cmdlen = 16 };
	unsigned char buffer[4096] = { 0 };
	transported = 0;
	cmd.cmd[0] = 0x28;
	assert(!scsi_exec(&dev, &cmd));
	assert(transported == 1);
	cmd.cmd[0] = 0x2a;
#if CONFIG_SCSI_READ_ONLY
	assert(!scsi_blk_ops.write && !scsi_blk_ops.erase);
	assert(scsi_exec(&dev, &cmd) == -EROFS);
	assert(transported == 1);
	assert(blk_write(&dev, 0, 1, buffer) == -ENOSYS);
	assert(blk_erase(&dev, 0, 1) == -ENOSYS);
	assert(transported == 1 && cache_invalidated == 0);
	const unsigned char forbidden[] = { 0x04, 0x15, 0x1b, 0x2a, 0x3b, 0x42,
					    0x48, 0x55, 0x8a, 0xaa, 0xb5 };
	for (unsigned int j = 0; j < sizeof(forbidden); j++) {
		cmd.cmd[0] = forbidden[j];
		int before = transported;
		assert(scsi_exec(&dev, &cmd) == -EROFS &&
		       transported == before);
	}
	cmd.cmd[0] = 0x9e;
	cmd.cmd[1] = 0x11;
	assert(scsi_exec(&dev, &cmd) == -EROFS);
	cmd.cmd[1] = 0x10;
	cmd.cmdlen = 15;
	assert(scsi_exec(&dev, &cmd) == -EROFS);
	cmd.cmdlen = 16;
	for (unsigned int opcode = 0; opcode < 256; opcode++) {
		cmd.cmd[0] = opcode;
		cmd.cmd[1] = 0x10;
		int before = transported;
		int ret = scsi_exec(&dev, &cmd);
		assert((ret == 0) ==
		       scsi_command_is_read_only(cmd.cmd, cmd.cmdlen));
		assert(transported - before == (ret == 0));
	}
#else
	assert(scsi_blk_ops.write && scsi_blk_ops.erase);
	assert(!scsi_exec(&dev, &cmd));
	assert(blk_write(&dev, 0, 1, buffer) == 1);
	assert(blk_erase(&dev, 0, 1) == 1);
#endif

	for (unsigned int op = 0; op <= 8; op++) {
		u32 value = 0;
		u8 buf[64] = { 0 };
		int len = sizeof(buf);
		bool flag = false;
		int before;
		before = transported;
		int r = ufshcd_query_attr(NULL, op, 0, 0, 0, &value);
		assert((r == 0) == (!CONFIG_SCSI_READ_ONLY ||
				    op == UPIU_QUERY_OPCODE_READ_ATTR));
		assert(transported - before == (r == 0));
		before = transported;
		r = __ufshcd_query_descriptor(NULL, op, 0, 0, 0, buf, &len);
		assert((r == 0) == (!CONFIG_SCSI_READ_ONLY ||
				    op == UPIU_QUERY_OPCODE_READ_DESC));
		assert(transported - before == (r == 0));
		before = transported;
		r = ufshcd_query_flag(NULL, op, QUERY_FLAG_IDN_FDEVICEINIT,
				      &flag);
		assert((r == 0) == (!CONFIG_SCSI_READ_ONLY ||
				    op == UPIU_QUERY_OPCODE_READ_FLAG ||
				    op == UPIU_QUERY_OPCODE_SET_FLAG));
		assert(transported - before == (r == 0));
		before = transported;
		r = ufshcd_query_flag(NULL, op, QUERY_FLAG_IDN_BKOPS_EN, &flag);
		assert((r == 0) == (!CONFIG_SCSI_READ_ONLY ||
				    op == UPIU_QUERY_OPCODE_READ_FLAG));
		assert(transported - before == (r == 0));
	}
	struct efi_block_io_media media = { .read_only = true,
					    .media_present = true,
					    .media_id = 1,
					    .block_size = 4096,
					    .last_block = 10 };
	struct efi_block_io io = { .media = &media };
	int before = transported;
	assert(efi_disk_write_blocks(&io, 1, 0, sizeof(buffer), buffer) ==
	       EFI_WRITE_PROTECTED);
	assert(transported == before);
	return 0;
}
'''
work=Path(os.environ.get('TMPDIR',Path.cwd()/'tmp')).resolve();work.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='uboot-storage-',dir=work) as tmp:
 tmp=Path(tmp);c=tmp/'test.c';c.write_text(boiler+'\n#include "scsi_read_only.h"\n'+scsi+write+erase+ops+'\n'+efi+enums+query_guards+main)
 for mode in [0,1]:
  binary=tmp/f'test{mode}'
  subprocess.run([os.environ.get('CC','cc'),'-std=gnu11','-Wall','-Wextra','-Wno-unused-parameter','-Wno-unused-function','-Wno-unused-variable',f'-DCONFIG_SCSI_READ_ONLY={mode}','-iquote',str(source/'include'),str(c),'-o',str(binary)],check=True)
  subprocess.run([str(binary)],check=True)
print('PASS: actual SCSI/EFI write rejection, mutating opcode contract and UFS query guards; normal profile retained')
