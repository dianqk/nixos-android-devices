/* SPDX-License-Identifier: GPL-2.0-only */
#include "menu.h"
unsigned eg_menu(const struct eg_menu_io *io,unsigned selected)
{
    uint64_t freq,now,last,start,stable=0,deadline=0;
    unsigned previous=7,armed=0,old_count=4,old_choice=2,stalls=0;
    unsigned reset=0;
    if(!io || !io->clock || !io->keys || !io->paint ||
       !io->clock(io->ctx,&freq,&now) || freq<1000 || freq>1000000000) return 0;
    start=last=now;
    /* The iteration/stall cap is a fail-Android guard, never a substitute clock.
     * Frequency/ticks must remain valid/monotonic; 20ms stable release/edges.
     * Startup release has a separate bounded 3s budget. */
    for(unsigned loops=0;loops<1000000;loops++) {
        uint64_t hz,t; unsigned keys;
        if(!io->clock(io->ctx,&hz,&t) || hz!=freq || t<last ||
           !io->keys(io->ctx,&keys) || keys>7) return 0;
        if(t==last) { if(++stalls==10000) return 0; } else stalls=0;
        last=t; now=t;
        if(!armed && now-start>=3*freq) return 0;
        if(keys!=previous) { previous=keys; stable=now; }
        if(!armed) {
            if(!keys && now-stable>=freq/50) {
                armed=1;
                if(now>UINT64_MAX-3*freq) return 0;
                deadline=now+3*freq; reset=1;
            } else continue;
        }
        /* Power has no menu action. Chords cannot select. Any held key must
         * first return to zero; one action per debounced press, no repeat. */
        if((keys==1 || keys==2) && now-stable>=freq/50) {
            if(armed==1) {
                selected=keys==1; armed=2;
                if(now>UINT64_MAX-3*freq) return 0;
                deadline=now+3*freq; reset=1;
            }
        } else if(keys && keys!=1 && keys!=2) armed=2;
        else if(!keys && now-stable>=freq/50) armed=1;
        if(!reset && now>=deadline) return selected;
        unsigned count=reset?3:(unsigned)((deadline-now+freq-1)/freq);
        if(count!=old_count || selected!=old_choice) {
            io->paint(io->ctx,selected,count); old_count=count;old_choice=selected;
            /* Synchronous paint may be expensive: charge no initial/selection
             * rendering latency against the visible three-second window. */
        }
        if(reset) {
            uint64_t hz,t;
            if(!io->clock(io->ctx,&hz,&t) || hz!=freq || t<last || t>UINT64_MAX-3*freq) return 0;
            deadline=t+3*freq; last=t; reset=0;
        }
    }
    return 0;
}
