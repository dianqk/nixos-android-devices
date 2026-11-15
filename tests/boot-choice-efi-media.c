/* SPDX-License-Identifier: GPL-2.0-only */
/* Compile with GNU-EFI headers, -fshort-wchar -ffunction-sections
 * -fdata-sections -fno-builtin and -Wl,--gc-sections. Uncalled ABI dispatch
 * functions are discarded; this tests actual transport snapshot/ABI helpers. */
#include <assert.h>
#include <stdio.h>
#include "../pkgs/boot-choice-efi/transport.c"
int main(void) {
 CHOICE_IO p={.revision=1,.size=40,.flags=3,.controller=1};
 /* A non-null ABI function pointer is required; never invoked here. */
 p.sync=(void *)1;
 assert(supported(&p));assert(!supported(NULL));
 p.size=32;assert(!supported(&p));p.size=40;
 p.revision=2;assert(!supported(&p));p.revision=1;
 p.flags=1;assert(!supported(&p));p.flags=3;
 p.target=1;assert(!supported(&p));p.target=0;
 p.lun=8;assert(!supported(&p));p.lun=7;
 p.controller=0;assert(!supported(&p));p.controller=1;
 EFI_BLOCK_IO_MEDIA em={.MediaId=1,.MediaPresent=TRUE,.BlockSize=512,.LastBlock=1000};
 EFI_BLOCK_IO_MEDIA bm={.MediaId=2,.MediaPresent=TRUE,.BlockSize=4096,.LastBlock=2000};
 EFI_BLOCK_IO esp={.Media=&em}, boot={.Media=&bm};
 snapshot(&esp_media,&esp);snapshot(&members[0],&esp);snapshot(&members[1],&boot);member_count=2;
 UINT64 geometry[2];
 assert(!bc_select(1,geometry));assert(disk==&boot && media==2 && block==4096 && last==2000);
 assert(geometry[0]==4096 && geometry[1]==2000);
 assert(bc_select(2,geometry));
 em.MediaId++;assert(bc_select(1,geometry));em.MediaId--;
 bm.MediaId++;assert(bc_select(0,geometry));bm.MediaId--;
 bm.BlockSize=512;assert(bc_select(0,geometry));bm.BlockSize=4096;
 bm.LastBlock++;assert(bc_select(0,geometry));bm.LastBlock--;
 bm.MediaPresent=FALSE;assert(bc_select(0,geometry));bm.MediaPresent=TRUE;
 boot.Media=NULL;assert(bc_select(0,geometry));
 puts("PASS production EFI ABI layout/null/flags/LUN and separate ESP/boot media snapshots");
}
