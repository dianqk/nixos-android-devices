/* SPDX-License-Identifier: GPL-2.0-only */
#include "intent-selection.h"
/* The legacy menu returns Android on error. Never turn that fallback into a
 * persistent Android commit: observe callback validity separately. No change
 * to the active selector/menu ABI or its compiled source binding. */
struct checked_menu {
    const struct eg_menu_io *io;
    uint64_t hz,last;
    unsigned clocks,stalls,fault,painted;
};
static int checked_clock(void *p,uint64_t *hz,uint64_t *ticks)
{
    struct checked_menu *c=p;
    if(!c->io->clock(c->io->ctx,hz,ticks) || *hz<1000 || *hz>1000000000 ||
       *ticks>UINT64_MAX-3*(*hz) || (c->clocks && (*hz!=c->hz || *ticks<c->last)) ||
       ++c->clocks>=1000000) { c->fault=1;return 0; }
    if(c->clocks>1 && *ticks==c->last) {
        if(++c->stalls>=10000){c->fault=1;return 0;}
    } else c->stalls=0;
    c->hz=*hz;c->last=*ticks;return 1;
}
static int checked_keys(void *p,unsigned *keys)
{
    struct checked_menu *c=p;
    if(!c->io->keys(c->io->ctx,keys) || *keys>7){c->fault=1;return 0;}
    return 1;
}
static void checked_paint(void *p,unsigned selected,unsigned count)
{
    struct checked_menu *c=p;c->painted=1;
    c->io->paint(c->io->ctx,selected,count);
}
enum eg_choice_route eg_intent_selection(const struct eg_menu_io *io,
    const unsigned char *pages,const unsigned char *generation,unsigned char *token)
{
    struct eg_choice_observation o;
    if(!io || !io->clock || !io->keys || !io->paint ||
       !eg_request_observe(pages,generation,&o))return EG_CHOICE_REFUSED;
    struct checked_menu c={.io=io};
    struct eg_menu_io checked={&c,checked_clock,checked_keys,checked_paint};
    unsigned selected=eg_menu(&checked,o.mode);
    if(c.fault || !c.painted)return EG_CHOICE_REFUSED;
    /* Physical selection is local to this boot, never a persistence request.
     * Android preserves the original ABL handoff without entering firmware. */
    if(!selected)return EG_ORIGINAL_ANDROID;
    if(!eg_intent_encode_readonly(token,generation,&o))return EG_CHOICE_REFUSED;
    return EG_UBOOT_UNCHANGED;
}
