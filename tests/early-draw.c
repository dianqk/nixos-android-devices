/* SPDX-License-Identifier: GPL-2.0-only */
/* Pure memory only: explicit synthetic geometry, no platform policy. */
#include "../tools/early-entry/draw.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
int main(void)
{
    const unsigned width=128,height=128,stride=528;
    size_t bytes=(size_t)height*stride;
    unsigned char *raw=malloc(bytes+128); assert(raw); memset(raw,0x5a,bytes+128);
    struct eg_framebuffer f={.base=(uintptr_t)(raw+64),.size=bytes,.width=width,.height=height,.stride=stride,.rgb32=1};
    assert(eg_draw_valid(&f)); eg_draw_clear(&f);
    assert(eg_draw_text(&f,10,10,1,"AUBndroit-0123"));
    assert(eg_draw_rect(&f,1,1,126,126));
    assert(!eg_draw_text(&f,128,128,1,"A"));
    assert(!eg_draw_text(&f,0,0,~0U,"A"));
    assert(!eg_draw_rect(&f,0,0,~0U,1));
    for(unsigned i=0;i<64;i++) assert(raw[i]==0x5a && raw[bytes+64+i]==0x5a);
    for(unsigned y=0;y<height;y++) for(unsigned x=width*4;x<stride;x++) assert(raw[64+y*stride+x]==0x5a);
    memset(raw+64,0x5a,bytes);
    assert(eg_draw_fill_rect(&f,30,40,12,8,0));
    assert(eg_draw_outline(&f,30,40,12,8,UINT32_MAX));
    for(unsigned y=0;y<height;y++) for(unsigned x=0;x<width;x++) {
        uint32_t v=*(uint32_t *)(raw+64+(size_t)y*stride+4*x);
        int inside=x>=30 && x<42 && y>=40 && y<48;
        int edge=inside && (x==30 || x==41 || y==40 || y==47);
        assert(v==(edge?UINT32_MAX:inside?0:0x5a5a5a5a));
    }
    assert(eg_draw_outline(&f,127,127,1,1,0));
    assert(!eg_draw_fill_rect(&f,~0U,0,1,1,0));
    assert(!eg_draw_fill_rect(&f,0,0,0,1,0));
    assert(!eg_draw_outline(&f,127,127,2,1,0));
    for(unsigned i=0;i<64;i++) assert(raw[i]==0x5a && raw[bytes+64+i]==0x5a);
    for(unsigned y=0;y<height;y++) for(unsigned x=width*4;x<stride;x++) assert(raw[64+y*stride+x]==0x5a);
    struct eg_framebuffer bad=f;bad.base=UINT64_MAX-16;assert(!eg_draw_valid(&bad));
    bad=f;bad.width=~0U;assert(!eg_draw_valid(&bad));
    bad=f;bad.stride=4;assert(!eg_draw_valid(&bad));
    bad=f;bad.size=bytes-1;assert(!eg_draw_valid(&bad));
    bad=f;bad.rgb32=0;assert(!eg_draw_valid(&bad));
    free(raw); return 0;
}
