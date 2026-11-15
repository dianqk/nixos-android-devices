/* SPDX-License-Identifier: GPL-2.0-only */
#include <assert.h>
#include <stdio.h>
#include "../tools/early-entry/spmi-observer.h"
struct mock { unsigned mode, reads, writes, ticks; uint32_t version,count; };
static int read32(void *c,uint64_t a,uint32_t *v)
{
    struct mock *m=c; m->reads++;
    if(m->mode==4) return 0;
    if(a==0x10000) *v=m->version;
    else if(a==0x10004) *v=m->count;
    else if(a>=0x12000 && a<0x12010) *v=(0x013<<8)|1;
    else if(a>=0x20000 && a<0x20010) *v=(a==0x20004)?0:1;
    else if(a==0x30028) *v=(m->mode==1 || m->mode==3)?0:m->mode==2?3:1;
    else if(a==0x30038) *v=0xa5;
    else return 0;
    return 1;
}
static int write32(void *c,uint64_t a,uint32_t v)
{ struct mock *m=c; m->writes++; assert(a==0x30020 && v==0x8000100); return m->mode!=5; }
static int counter(void *c,uint64_t *v)
{ struct mock *m=c; *v=m->mode==3?0:m->ticks++; return 1; }
int main(void)
{
    struct mock m={.version=0x70000000,.count=4};
    struct eg_spmi_io io={&m,read32,write32,counter,1000000,0x10000,0x20000,0x30000};
    uint16_t apid=999; uint8_t v=0;
    assert(eg_spmi_find(&io,0x013,&apid) && apid==1);
    assert(!eg_spmi_find(&io,0x18d,&apid));
    assert(eg_spmi_read_byte(&io,1,0x1310,&v) && v==0xa5 && m.writes==1);
    m.mode=1; m.ticks=0; assert(!eg_spmi_read_byte(&io,1,0x1310,&v));
    assert(m.ticks<=1002);
    m.mode=2; assert(!eg_spmi_read_byte(&io,1,0x1310,&v));
    m.mode=3; m.reads=0;
    assert(!eg_spmi_read_byte(&io,1,0x1310,&v) && m.reads==100000);
    m.mode=4; assert(!eg_spmi_find(&io,0x013,&apid));
    assert(!eg_spmi_read_byte(&io,1,0x1310,&v));
    m.mode=5; assert(!eg_spmi_read_byte(&io,1,0x1310,&v));
    m.mode=0; m.version=0x80000000; assert(!eg_spmi_find(&io,0x013,&apid));
    m.version=0x70000000; m.count=1025; assert(!eg_spmi_find(&io,0x013,&apid));
    m.count=0; assert(!eg_spmi_find(&io,0x013,&apid));
    io.frequency=0; assert(!eg_spmi_read_byte(&io,1,0x1310,&v));
    io.counter=0; m.mode=0;
    assert(eg_spmi_read_byte_bounded(&io,1,0x1310,&v,1000));
    m.mode=1; m.reads=0;
    assert(!eg_spmi_read_byte_bounded(&io,1,0x1310,&v,1000) && m.reads==1000);
    assert(!eg_spmi_read_byte_bounded(&io,1,0x1310,&v,0));
    assert(!eg_spmi_read_byte_bounded(&io,1,0x1310,&v,100001));
    puts("SPMI success/timeout/error/fault/version/count/frequency passed");
}
