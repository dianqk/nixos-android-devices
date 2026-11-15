/* SPDX-License-Identifier: GPL-2.0-only */
#include "draw.h"
/* Original 5x7 bitmaps. Deliberately tiny repertoire, not a borrowed font. */
static unsigned row(char c,unsigned y)
{
    static const unsigned char glyphs[][7]={
        {14,17,17,31,17,17,17}, /* A */
        {17,17,17,17,17,17,14}, /* U */
        {30,17,17,30,17,17,30}, /* B */
        {0,0,30,17,17,17,17}, /* n */
        {1,1,15,17,17,17,15}, /* d */
        {0,0,22,25,16,16,16}, /* r */
        {0,0,14,17,17,17,14}, /* o */
        {4,0,12,4,4,4,14}, /* i */
        {8,8,30,8,8,9,6}, /* t */
        {0,0,0,31,0,0,0}, /* - */
        {14,17,19,21,25,17,14}, /* 0 */
        {4,12,4,4,4,4,14}, /* 1 */
        {14,17,1,2,4,8,31}, /* 2 */
        {30,1,1,14,1,1,30}, /* 3 */
#ifdef DODGE_DIAGNOSTIC_STAGES
        {2,6,10,18,31,2,2}, /* 4 */
        {31,16,16,30,1,1,30}, /* 5 */
        {14,16,16,30,17,17,14}, /* 6 */
        {31,1,2,4,8,8,8}, /* 7 */
        {14,17,17,14,17,17,14}, /* 8 */
        {14,17,17,15,1,1,14}, /* 9 */
        {14,17,16,16,16,17,14}, /* C */
        {30,17,17,17,17,17,30}, /* D */
        {31,16,16,30,16,16,31}, /* E */
        {31,16,16,30,16,16,16}, /* F */
#endif
    };
#ifdef DODGE_DIAGNOSTIC_STAGES
    const char alphabet[]="AUBndroit-0123456789CDEF";
#else
    const char alphabet[]="AUBndroit-0123";
#endif
    for(unsigned i=0;alphabet[i];i++) if(c==alphabet[i]) return glyphs[i][y];
    return 0;
}
int eg_draw_valid(const struct eg_framebuffer *f)
{
    if(!f || !f->rgb32 || !f->base || (f->base&3) || !f->size ||
       f->base>UINT64_MAX-f->size || !f->width || !f->height ||
       f->width>8192 || f->height>8192 || (f->stride&3) ||
       f->stride<(uint64_t)f->width*4 || f->stride>65536) return 0;
    return (uint64_t)f->height*f->stride<=f->size;
}
static void pixel(const struct eg_framebuffer *f,unsigned x,unsigned y,uint32_t v)
{ *(volatile uint32_t *)(uintptr_t)(f->base+(uint64_t)y*f->stride+x*4)=v; }
void eg_draw_clear(const struct eg_framebuffer *f)
{
    if(!eg_draw_valid(f)) return;
    for(unsigned y=0;y<f->height;y++) for(unsigned x=0;x<f->width;x++) pixel(f,x,y,0);
}
static int bounds(const struct eg_framebuffer *f,unsigned x,unsigned y,unsigned w,unsigned h)
{ return eg_draw_valid(f) && w && h && x<=f->width && w<=f->width-x &&
         y<=f->height && h<=f->height-y; }
int eg_draw_fill_rect(const struct eg_framebuffer *f,unsigned x,unsigned y,unsigned w,unsigned h,uint32_t color)
{
    if(!bounds(f,x,y,w,h)) return 0;
    for(unsigned j=0;j<h;j++) for(unsigned i=0;i<w;i++) pixel(f,x+i,y+j,color);
    return 1;
}
int eg_draw_outline(const struct eg_framebuffer *f,unsigned x,unsigned y,unsigned w,unsigned h,uint32_t color)
{
    if(!bounds(f,x,y,w,h)) return 0;
    for(unsigned i=0;i<w;i++) {
        pixel(f,x+i,y,color);
        if(h>1) pixel(f,x+i,y+h-1,color);
    }
    for(unsigned j=1;j+1<h;j++) {
        pixel(f,x,y+j,color);
        if(w>1) pixel(f,x+w-1,y+j,color);
    }
    return 1;
}
int eg_draw_rect(const struct eg_framebuffer *f,unsigned x,unsigned y,unsigned w,unsigned h)
{ return eg_draw_outline(f,x,y,w,h,UINT32_MAX); }
int eg_draw_text(const struct eg_framebuffer *f,unsigned x,unsigned y,unsigned s,const char *text)
{
    unsigned n=0;
    if(!eg_draw_valid(f) || !text || !s || s>64) return 0;
    while(text[n]) { if(++n>128) return 0; }
    uint64_t width=n?((uint64_t)n*6-1)*s:0;
    if(x>f->width || width>f->width-x || y>f->height || 7*s>f->height-y) return 0;
    for(unsigned k=0;k<n;k++) for(unsigned j=0;j<7;j++) for(unsigned i=0;i<5;i++)
        if(row(text[k],j)&(16>>i)) for(unsigned dy=0;dy<s;dy++) for(unsigned dx=0;dx<s;dx++)
            pixel(f,x+(k*6+i)*s+dx,y+j*s+dy,UINT32_MAX);
    return 1;
}
