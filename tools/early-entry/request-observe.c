/* SPDX-License-Identifier: GPL-2.0-only */
/* Strict observation for the opt-in commit protocol. Legacy fallback unchanged. */
#include "commit-intent.h"
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
int eg_request_observe(const unsigned char *p,const unsigned char *g,
                       struct eg_choice_observation *out) {
 if(!p || !g || !out)return 0;
 int a=valid(p,g),b=valid(p+4096,g);
 if(!a && !b)return 0;
 uint64_t x=a?le64(p+44):0,y=b?le64(p+4096+44):0;
 if(a && b && x==y)return 0;
 const unsigned char *r=p+(y>x?4096:0);
 *out=(struct eg_choice_observation){.sequence=le64(r+44),.mode=le32(r+52)};
 return 1;
}
