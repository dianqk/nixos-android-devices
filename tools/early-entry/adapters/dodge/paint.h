/* SPDX-License-Identifier: GPL-2.0-only */
/* Product default renderer. Personal layout/cutout policy is not required. */
#ifndef DODGE_PAINT_H
#define DODGE_PAINT_H
struct dodge_paint_state { unsigned initialized,choice,count; };
static void dodge_paint(const struct eg_framebuffer *f,struct dodge_paint_state *state,
                        unsigned choice,unsigned seconds)
{
 unsigned scale=f->width/96;if(scale>8)scale=8;
 if(!state || !scale || seconds>3 || !eg_draw_valid(f))return;
 unsigned w=64*scale,h=28*scale;
 if(f->width<w || f->height<h)return;
 unsigned x=(f->width-w)/2,y=(f->height-h)/2;
 if(!state->initialized || state->choice!=choice || state->count!=seconds) {
  char count[2]={(char)('0'+seconds),0};
  eg_draw_fill_rect(f,x,y,w,h,0);
  eg_draw_text(f,x+8*scale,y+2*scale,scale,"U-Boot");
  eg_draw_text(f,x+8*scale,y+12*scale,scale,"Android");
  eg_draw_outline(f,x,y+(choice?0:10*scale),w,10*scale,0xffffffff);
  eg_draw_text(f,x+52*scale,y+20*scale,scale,count);
 }
 state->initialized=1;state->choice=choice;state->count=seconds;
}
#endif
