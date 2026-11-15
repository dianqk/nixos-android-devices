/* SPDX-License-Identifier: GPL-2.0-only */
#include "commit-intent.h"
static uint32_t le32(const unsigned char *p)
{ return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static void put32(unsigned char *p,uint32_t n)
{ for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(n>>(8*i)); }
static uint32_t crc(const unsigned char *p)
{
    uint32_t c=~0U;
    for(unsigned i=0;i<EG_INTENT_BYTES;i++) {
        c^=i>=76?0:p[i];
        for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320U & (0U-(c&1)));
    }
    return ~c;
}
enum eg_choice_route eg_choice_route(const struct eg_choice_observation *o,unsigned selected)
{
    if(!o || !o->sequence || o->mode>1 || selected>1)return EG_CHOICE_REFUSED;
    if(o->mode==selected)return selected?EG_UBOOT_UNCHANGED:EG_ORIGINAL_ANDROID;
    if(o->sequence==UINT64_MAX)return EG_CHOICE_REFUSED;
    return selected?EG_UBOOT_COMMIT_UBOOT:EG_UBOOT_COMMIT_ANDROID;
}
int eg_intent_encode(unsigned char *out,const unsigned char *g,
                     const struct eg_choice_observation *o,unsigned selected)
{
    static const unsigned char magic[8]={'B','C','I','N','T','E','N','T'};
    enum eg_choice_route r=eg_choice_route(o,selected); unsigned nz=0;
    unsigned char generation[32];
    if(!out || !g || (r!=EG_UBOOT_COMMIT_ANDROID && r!=EG_UBOOT_COMMIT_UBOOT && r!=EG_UBOOT_UNCHANGED))return 0;
    /* Snapshot inputs before any output writes, even for overlapping buffers. */
    uint64_t sequence=o->sequence;unsigned mode=o->mode;
    for(unsigned i=0;i<32;i++){generation[i]=g[i];nz|=g[i];}
    if(!nz)return 0;
    for(unsigned i=0;i<EG_INTENT_BYTES;i++)out[i]=0;
    for(unsigned i=0;i<8;i++)out[i]=magic[i];
    put32(out+8,1);put32(out+12,EG_INTENT_BYTES);
    for(unsigned i=0;i<32;i++)out[16+i]=generation[i];
    put32(out+48,(uint32_t)sequence);put32(out+52,(uint32_t)(sequence>>32));
    put32(out+56,mode);put32(out+60,selected);put32(out+64,r!=EG_UBOOT_UNCHANGED);
    /* 68 booted-slot, 72 observation-source: unavailable, not fabricated. */
    put32(out+76,crc(out));return 1;
}
int eg_intent_encode_readonly(unsigned char *out,const unsigned char *g,
                             const struct eg_choice_observation *o)
{
    if(!o || !o->sequence || o->mode>1)return 0;
    /* Reuse canonical encoder without a sequence increment, even at MAX. */
    struct eg_choice_observation observed=*o,encoding={o->sequence,1};
    if(!eg_intent_encode(out,g,&encoding,1))return 0;
    put32(out+56,observed.mode);put32(out+64,EG_INTENT_READ_ONLY);
    put32(out+76,crc(out));return 1;
}
int eg_intent_decode(const unsigned char *in,const unsigned char *g,
                     struct eg_choice_observation *out,unsigned *selected)
{
    static const unsigned char magic[8]={'B','C','I','N','T','E','N','T'};
    unsigned nz=0;
    if(!in || !g || !out || !selected)return 0;
    for(unsigned i=0;i<8;i++)if(in[i]!=magic[i])return 0;
    for(unsigned i=0;i<32;i++){if(in[16+i]!=g[i])return 0;nz|=g[i];}
    if(!nz || le32(in+8)!=1 || le32(in+12)!=EG_INTENT_BYTES ||
       le32(in+64)>EG_INTENT_READ_ONLY ||
       !((le32(in+68)==0 && le32(in+72)==0) ||
         ((le32(in+68)==1 || le32(in+68)==2) && le32(in+72)==1)) || le32(in+76)!=crc(in))return 0;
    struct eg_choice_observation o={.sequence=le32(in+48)|(uint64_t)le32(in+52)<<32,.mode=le32(in+56)};
    unsigned s=le32(in+60);enum eg_choice_route r=eg_choice_route(&o,s);
    if(le32(in+64)==EG_INTENT_READ_ONLY) {
        if(!o.sequence || o.mode>1 || s!=1)return 0;
    } else if(r==EG_UBOOT_UNCHANGED) { if(le32(in+64)!=0)return 0; }
    else if((r!=EG_UBOOT_COMMIT_ANDROID && r!=EG_UBOOT_COMMIT_UBOOT) || le32(in+64)!=1)return 0;
    *out=o;*selected=s;return 1;
}

int eg_intent_bind_slot(unsigned char *token,const unsigned char *generation,unsigned slot)
{
    struct eg_choice_observation o;unsigned selected;
    if((slot!=1 && slot!=2) || !eg_intent_decode(token,generation,&o,&selected))return 0;
    put32(token+68,slot);put32(token+72,1);put32(token+76,crc(token));return 1;
}
