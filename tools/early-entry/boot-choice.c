/* SPDX-License-Identifier: GPL-2.0-only */
/* Original implementation, wire-compatible with tools/boot-choice/format.rs. */
#include "boot-choice.h"
static uint32_t le32(const unsigned char *p) {return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint64_t le64(const unsigned char *p) {return le32(p)|(uint64_t)le32(p+4)<<32;}
static int valid(const unsigned char *p,const unsigned char *g) {
 const unsigned char magic[8]={'B','O','O','T','R','E','Q','1'};unsigned nonzero=0;
 for(unsigned i=0;i<8;i++)if(p[i]!=magic[i])return 0;
 for(unsigned i=0;i<32;i++){if(p[12+i]!=g[i])return 0;nonzero|=g[i];}
 if(!nonzero || le32(p+8)!=1 || !le64(p+44) || le32(p+52)>1 || le32(p+56))return 0;
 uint32_t c=~0U;
 for(unsigned i=0;i<4096;i++) {if(i>=64 && p[i])return 0;c^=(i>=60 && i<64)?0:p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320U & (0U-(c&1)));}
 return ~c==le32(p+60);
}
unsigned eg_request_select(const unsigned char *p,const unsigned char *g) {
 int a=valid(p,g),b=valid(p+4096,g);
 if(!a && !b){unsigned any=0;for(unsigned i=0;i<8192;i++)any|=p[i];return !any;}
 if(!a)return le32(p+4096+52);
 if(!b)return le32(p+52);
 uint64_t x=le64(p+44),y=le64(p+4096+44);
 if(x==y && le32(p+52)!=le32(p+4096+52))return 0;
 return le32(p+(x>=y?0:4096)+52);
}
