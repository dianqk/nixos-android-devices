/* SPDX-License-Identifier: GPL-2.0-only */
#include "bootconfig.h"
#include <stdint.h>
static uint32_t le32(const unsigned char *p)
{ return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static int same(const unsigned char *a,const char *b,size_t n)
{ for(size_t i=0;i<n;i++)if(a[i]!=(unsigned char)b[i])return 0;return 1; }
static unsigned refuse(struct eg_bootconfig_report *r,unsigned error,
                       const unsigned char *p,size_t size,size_t offset)
{
    if(r){r->error=error;r->offset=offset;r->byte=p && offset<size?p[offset]:0;}
    return 0;
}
unsigned eg_bootconfig_slot_report(const void *range,size_t size,
                                  struct eg_bootconfig_report *report)
{
    const unsigned char *p=range;size_t magic=0;unsigned found=0,slot=0;
#define REFUSE(error,offset) return refuse(report,error,p,size,offset)
    if(report)*report=(struct eg_bootconfig_report){0};
    if(!p || size<20){REFUSE(EG_BC_RANGE,0);}
    /* Linux get_boot_config_from_initrd: magic may precede up to 3 bytes of
     * alignment. Unlike Linux, require those padding bytes to be zero. */
    for(size_t pad=0;pad<4 && size>=20+pad;pad++) {
        size_t at=size-pad-12;
        if(same(p+at,"#BOOTCONFIG\n",12)) { magic=at;found=1;break; }
        if(p[size-pad-1]){
            /* Inspect only the same four bounded candidates to distinguish
             * absent magic from nonzero alignment padding; do not admit it. */
            for(size_t next=pad+1;next<4 && size>=20+next;next++)
                if(same(p+size-next-12,"#BOOTCONFIG\n",12)){
                    REFUSE(EG_BC_PADDING,size-pad-1);
                }
            break;
        }
    }
    if(!found){REFUSE(EG_BC_MAGIC,size-12);}
    size_t n=le32(p+magic-8);
    /* Kernel setup_boot_config rejects size >= XBC_DATA_MAX (32767). */
    if(!n || n>=32767){REFUSE(EG_BC_SIZE,magic-8);}
    if(n>magic-8){REFUSE(EG_BC_BOUNDS,magic-8);}
    const unsigned char *text=p+magic-8-n;uint32_t sum=0;
    for(size_t i=0;i<n;i++)sum+=text[i];
    if(sum!=le32(p+magic-4)){REFUSE(EG_BC_CHECKSUM,magic-4);}
    /* Flat Android assignments allow quoted or unquoted scalar values.
     * Never evaluate XBC trees, comments, arrays, escapes or operators that
     * could hide a duplicate key. The kernel-visible text must fit this subset. */
    size_t at=0;
    while(at<n) {
        /* Linux XBC parses a C string, not every byte of the checksummed
         * payload. A NUL at a complete-record boundary ends that text; OEM
         * allocation/alignment bytes after it are opaque, not more keys.
         * The checksum above still covers ALL n bytes, including this suffix.
         * Never scan past NUL to discover a slot the kernel cannot observe. */
        if(text[at]==0)break;
        if(text[at]=='\n' || text[at]==' ' || text[at]=='\t'){at++;continue;}
        size_t key=at;
        while(at<n && ((text[at]>='a' && text[at]<='z') ||
              (text[at]>='A' && text[at]<='Z') ||
              (text[at]>='0' && text[at]<='9') || text[at]=='_' || text[at]=='.' || text[at]=='-'))at++;
        size_t len=at-key;
        if(!len || text[key]=='.' || text[at-1]=='.'){
            REFUSE(EG_BC_KEY,(size_t)(text-p)+key);
        }
        for(size_t i=key+1;i<at;i++)if(text[i]=='.' && text[i-1]=='.'){
            REFUSE(EG_BC_KEY,(size_t)(text-p)+i);
        }
        while(at<n && (text[at]==' ' || text[at]=='\t'))at++;
        if(at>=n || text[at]!='='){REFUSE(EG_BC_ASSIGN,(size_t)(text-p)+at);}
        at++;
        while(at<n && (text[at]==' ' || text[at]=='\t'))at++;
        if(at>=n){REFUSE(EG_BC_VALUE,(size_t)(text-p)+at);}
        unsigned quoted=text[at]=='"';
        if(quoted)at++;
        size_t val=at;
        while(at<n) {
            unsigned c=text[at];
            if(quoted && c=='"')break;
            if(!quoted && (c==0 || c=='\n' || c==' ' || c=='\t'))break;
            if(c<32 || c>126 || c=='\\' ||
               (!quoted && (c=='"' || c=='\'' || c=='#' || c==';' ||
                            c=='{' || c=='}' || c=='[' || c==']' ||
                            c==',' || c=='=' || c=='+'))){
                REFUSE(EG_BC_VALUE,(size_t)(text-p)+at);
            }
            at++;
        }
        if((quoted && at==n) || (!quoted && at==val)){
            REFUSE(EG_BC_VALUE,(size_t)(text-p)+at);
        }
        if(len==23 && same(text+key,"androidboot.slot_suffix",23)) {
            if(slot){REFUSE(EG_BC_DUPLICATE,(size_t)(text-p)+key);}
            if(at-val!=2 || text[val]!='_' || (text[val+1]!='a' && text[val+1]!='b')){
                REFUSE(EG_BC_SLOT,(size_t)(text-p)+val);
            }
            slot=text[val+1]=='a'?1:2;
        }
        if(quoted)at++;
        while(at<n && (text[at]==' ' || text[at]=='\t'))at++;
        if(at<n && text[at]!='\n' && text[at]!=0){
            REFUSE(EG_BC_SEPARATOR,(size_t)(text-p)+at);
        }
        if(at<n && text[at]=='\n')at++;
    }
    if(!slot){REFUSE(EG_BC_MISSING_SLOT,(size_t)(text-p));}
#undef REFUSE
    return slot;
}
unsigned eg_bootconfig_slot(const void *range,size_t size)
{ return eg_bootconfig_slot_report(range,size,0); }
