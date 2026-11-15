/* SPDX-License-Identifier: GPL-2.0-only */
#include "commit-intent.h"
#define LIMIT (2U*1024U*1024U)
static uint32_t be32(const unsigned char *p)
{ return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3]; }
static void put(unsigned char *p,uint32_t x)
{ for(unsigned i=0;i<4;i++)p[i]=(unsigned char)(x>>(24-8*i)); }
static int span(uint32_t a,uint32_t n,uint32_t end)
{ return a<=end && n<=end-a; }
static int eq(const unsigned char *p,uint32_t n,const char *s)
{ unsigned i=0;while(s[i]){if(i>=n || p[i]!=(unsigned char)s[i])return 0;i++;}return i==n; }
static void copy(unsigned char *d,const unsigned char *s,size_t n)
{ for(size_t i=0;i<n;i++)d[i]=s[i]; }
size_t eg_fdt_copy_intent(const void *src,size_t mapped,void *dst,size_t capacity,
                          const unsigned char *token)
{
    const unsigned char *p=src;unsigned char *q=dst;
    uint32_t total,so,st,ro,sn,ss,at,end,insert=0;
    unsigned depth=0,roots=0,chosen=0,done=0,child[32]={0};
    struct eg_choice_observation observation;unsigned selected;
    if(!p || !q || !token || mapped<40 || ((uintptr_t)q&7) ||
       !eg_intent_decode(token,token+16,&observation,&selected))return 0;
    total=be32(p+4);
    if(be32(p)!=0xd00dfeed || total<40 || total>mapped || total>LIMIT)return 0;
    so=be32(p+8);st=be32(p+12);ro=be32(p+16);sn=be32(p+32);ss=be32(p+36);
    if(be32(p+20)!=17 || be32(p+24)>17 || ro<40 || ro%8 || so%4 || ss%4 ||
       !span(so,ss,total) || !span(st,sn,total) || ro>so || so+ss>st)return 0;
    /* Complete reservation map, including terminator, stays byte-identical. */
    at=ro;
    for(;;) {
        if(!span(at,16,so))return 0;
        uint64_t base=(uint64_t)be32(p+at)<<32|be32(p+at+4);
        uint64_t size=(uint64_t)be32(p+at+8)<<32|be32(p+at+12);at+=16;
        if(!base && !size)break;
        if(!size || base>UINT64_MAX-size)return 0;
    }
    at=so;end=so+ss;
    while(span(at,4,end)) {
        uint32_t t=be32(p+at);at+=4;
        if(t==1) {
            uint32_t start=at;
            if(depth==32 || (!depth && roots))return 0;
            while(at<end && p[at])at++;
            if(at==end)return 0;
            if(!depth){if(at!=start)return 0;roots++;}
            else child[depth-1]=1;
            if(depth==1 && eq(p+start,at-start,"chosen")) {
                if(chosen++)return 0;
                insert=(at+4)&~3U;
            }
            /* A chosen unit-address is not the required singleton. */
            if(depth==1 && at-start>=7 && eq(p+start,6,"chosen") && p[start+6]=='@')return 0;
            child[depth++]=0;at=(at+4)&~3U;if(at>end)return 0;
        } else if(t==3) {
            if(!depth || child[depth-1] || !span(at,8,end))return 0;
            uint32_t len=be32(p+at),no=be32(p+at+4),start=no;at+=8;
            if(!span(at,len,end) || no>=sn)return 0;
            while(no<sn && p[st+no])no++;
            if(no==sn || eq(p+st+start,no-start,EG_INTENT_PROPERTY))return 0;
            at=(at+len+3)&~3U;if(at>end)return 0;
        } else if(t==2) {
            if(!depth)return 0;
            depth--;
        } else if(t==9) {
            if(depth || roots!=1 || chosen!=1 || at!=end)return 0;
            done=1;break;
        } else if(t!=4)return 0;
    }
    const uint32_t added=12+EG_INTENT_BYTES,names=sizeof(EG_INTENT_PROPERTY);
    if(!done || !insert || total>LIMIT-added-names)return 0;
    uint32_t used=total+added+names,newtotal=(used+7)&~7U;
    uintptr_t a=(uintptr_t)p,b=(uintptr_t)q,c=(uintptr_t)token;
    if(newtotal>capacity || a>UINTPTR_MAX-total || b>UINTPTR_MAX-newtotal ||
       c>UINTPTR_MAX-EG_INTENT_BYTES || (b<a+total && a<b+newtotal) ||
       (b<c+EG_INTENT_BYTES && c<b+newtotal))return 0;
    /* All validation precedes writes. Keep gaps and trailing opaque bytes too;
     * only header extents, inserted property and appended name change. */
    copy(q,p,insert);put(q+insert,3);put(q+insert+4,EG_INTENT_BYTES);put(q+insert+8,sn);
    copy(q+insert+12,token,EG_INTENT_BYTES);
    copy(q+insert+added,p+insert,st+sn-insert);
    copy(q+st+added+sn,(const unsigned char *)EG_INTENT_PROPERTY,names);
    copy(q+st+added+sn+names,p+st+sn,total-st-sn);
    for(uint32_t i=used;i<newtotal;i++)q[i]=0;
    put(q+4,newtotal);put(q+12,st+added);put(q+32,sn+names);put(q+36,ss+added);
    return newtotal;
}
