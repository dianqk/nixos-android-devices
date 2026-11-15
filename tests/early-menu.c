/* SPDX-License-Identifier: GPL-2.0-only */
#include "menu.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
unsigned long pixel_writes;
struct mock { uint64_t ticks; unsigned mode,draws,count_mask,selections; uint64_t first3,last,initial_latency,update_latency,visible3; };
static int clock_mock(void *p,uint64_t *hz,uint64_t *ticks)
{
    struct mock *m=p; *hz=m->mode==9?0:1000;
    if(m->mode!=8) m->ticks+=10;
    *ticks=m->ticks; return m->mode!=10;
}
static int keys_mock(void *p,unsigned *keys)
{
    struct mock *m=p; uint64_t t=m->ticks; *keys=0;
    if(m->mode==1 && t>=500 && t<1500) *keys=2; /* Down hold, no Power */
    if(m->mode==2 && t>=500 && t<1500) *keys=1;
    if(m->mode==3 && t<500) *keys=5; /* inherited Power+Up then release */
    if(m->mode==4) *keys=4; /* never released => bounded Android */
    if(m->mode==5 && t>=500 && t<1500) *keys=3;
    if(m->mode==6 && t>=500 && t<510) *keys=2; /* bounce */
    if(m->mode==7 && t>=2990 && t<3500) *keys=2; /* resets near expiry */
    if(m->mode==12 && t>=m->initial_latency+500 && t<m->initial_latency+1500) *keys=2;
    if(m->mode==11) return 0;
    return 1;
}
static void paint_mock(void *p,unsigned choice,unsigned count)
{
    struct mock *m=p; assert(count>=1 && count<=3); m->count_mask|=1<<count;
    if(!m->draws) m->first3=m->ticks;
    if(count==3) m->selections++;
    m->ticks+=m->draws?m->update_latency:m->initial_latency;
    if(count==3) m->visible3=m->ticks;
    m->last=m->ticks; m->draws++; (void)choice;
}
int main(void)
{
    for(unsigned mode=0;mode<12;mode++) for(unsigned pref=0;pref<2;pref++) {
        struct mock m={.mode=mode};
        struct eg_menu_io io={&m,clock_mock,keys_mock,paint_mock};
        unsigned got=eg_menu(&io,pref);
        unsigned expected=mode==1 || mode==4 || mode==7 || mode>=8?0:mode==2?1:pref;
        assert(got==expected);
        if(mode!=4 && mode<8) {
            assert(m.count_mask==14); assert(m.ticks-m.first3>=3000);
            if(mode==1 || mode==2) assert(m.selections==(1+(pref!=(mode==2)))); /* hold never repeats */
            if(mode==7) assert(m.ticks>=6010); /* full reset */
            if(mode==3) assert(m.first3>=520);
        }
        if(mode==4) assert(!m.draws && m.ticks<=3020);
    }
    for(unsigned latency=2000;latency<=6000;latency+=4000) for(unsigned j=0;j<3;j++) {
        unsigned mode=(unsigned[]){0,3,12}[j];
        struct mock m={.mode=mode,.initial_latency=latency,.update_latency=200};
        struct eg_menu_io io={&m,clock_mock,keys_mock,paint_mock};
        assert(eg_menu(&io,1)==(mode==12?0:1));
        assert(m.ticks>=m.visible3+3000); assert(m.count_mask==14);
    }
    puts("24 menu selection and6 rendering-latency callback cases passed");
    return 0;
}
