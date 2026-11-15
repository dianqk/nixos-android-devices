/* SPDX-License-Identifier: GPL-2.0-only */
#include "profile.h"
#include "runtime-template.h"
#include "boot-choice.h"
#include "menu.h"
#include "display.h"
#include "intent-selection.h"
#include "paint.h"
#include "bootconfig.h"
#ifdef DODGE_INTENT_PROTOTYPE
extern unsigned char eg_fdt_workspace[] __attribute__((visibility("hidden")));
extern unsigned char eg_fdt_workspace_end[] __attribute__((visibility("hidden")));
#endif
static int match(const unsigned char *p,size_t n,const char *s)
{ size_t i=0; while(s[i]) { if(i==n || p[i]!=(unsigned char)s[i]) return 0; i++; } return i==n; }
/* Captured Dodge boot paths attest reboot and normal (OEM fastboot RAM boot).
 * Unknown, absent, duplicate or conflicting mode keys preserve original Android
 * before keys, preferences, counter or display. */
int dodge_normal_mode(const unsigned char *a,size_t n)
{
    unsigned found=0;
    if(!a) return 0;
    for(size_t i=0;i<n;) {
        while(i<n && a[i]==' ') i++;
        size_t start=i; while(i<n && a[i]!=' ') i++;
        size_t len=i-start,eq=0; while(eq<len && a[start+eq]!='=') eq++;
        if(match(a+start,eq,"oplusboot.mode")) {
            if(found++ || eq==len ||
               (!match(a+start+eq+1,len-eq-1,"reboot") &&
                !match(a+start+eq+1,len-eq-1,"normal"))) return 0;
        } else if(match(a+start,eq,"androidboot.mode") || match(a+start,eq,"bootmonitor.bootmode")) {
            /* No exact captured normal value for these alternate cmdline keys. */
            return 0;
        }
    }
    return found==1;
}
extern int eg_clock_read(uint64_t *,uint64_t *);
struct menu_context { const struct eg_spmi_io *io; struct eg_framebuffer fb; uint16_t pon,gpio; struct dodge_paint_state paint; };
static int clock_read(void *ctx,uint64_t *hz,uint64_t *ticks)
{ (void)ctx; return eg_clock_read(hz,ticks); }
static int keys_read(void *ctx,unsigned *keys)
{
    struct menu_context *c=ctx; uint8_t pon,gpio;
    if(!eg_spmi_read_byte_bounded(c->io,c->pon,0x1310,&pon,1000) ||
       !eg_spmi_read_byte_bounded(c->io,c->gpio,0x8d10,&gpio,1000)) return 0;
    *keys=((pon&0x40)?1:0) | ((gpio&1)?0:2) | ((pon&0x80)?4:0);
    return 1;
}
static void paint(void *ctx,unsigned choice,unsigned count)
{ struct menu_context *c=ctx; dodge_paint(&c->fb,&c->paint,choice,count); }
extern const unsigned char eg_request_generation[] __attribute__((visibility("hidden")));
extern const unsigned char eg_request_pages[] __attribute__((visibility("hidden")));
/* Precise synchronous abort only. No claim to contain SError, stalled bus
 * transactions or firmware ownership errors; hardware early access unproven. */
static int read32(void *ctx, uint64_t address, uint32_t *v)
{ (void)ctx; return eg_mmio_read32(address,v); }
static int write32(void *ctx, uint64_t address, uint32_t v)
{ (void)ctx; return eg_mmio_write32(address,&v); }
/* Diagnostic-only: call ONLY after full profile, normal-mode and framebuffer
 * envelope admission. Never decode raw arguments or paint a rejected FDT. */
static void diagnostic(const struct eg_framebuffer *f,unsigned code,unsigned hold)
{
#ifdef DODGE_DIAGNOSTIC_STAGES
    unsigned scale=6,w=72*scale,h=11*scale;
    if(code>5 || !eg_draw_valid(f) || f->width<w || f->height<h)return;
    unsigned x=(f->width-w)/2,y=(f->height-h)/2;
    char text[]="Android - 0";text[10]=(char)('0'+code);
    eg_draw_fill_rect(f,x,y,w,h,0);eg_draw_text(f,x+scale,y+2*scale,scale,text);
    if(hold) {
        uint64_t hz,start,rate,now;
        if(eg_clock_read(&hz,&start) && hz>=1000 && hz<=1000000000) {
            for(unsigned i=0;i<1000000000;i++) {
                if(!eg_clock_read(&rate,&now) || rate!=hz || now<start)break;
                if(now-start>=3*hz)return;
            }
        }
        /* Finite visibility budget when the very clock under diagnosis fails.
         * Iteration bound, NOT a promise of three wall-clock seconds. */
        for(unsigned i=0;i<100000000;i++)__asm__ volatile("nop");
    }
#else
    (void)f;(void)code;(void)hold;
#endif
}
/* Report only admitted initrd refusal metadata, never raw bootconfig text.
 * Decimal reason / 64-bit hex initrd-relative offset / hex offending byte.
 * No parser acceptance change and no persistent logging or MMIO. */
static inline void diagnostic_bootconfig(const struct eg_framebuffer *f,
                                 const struct eg_bootconfig_report *r)
{
#ifdef DODGE_DIAGNOSTIC_STAGES
    if(!r || !eg_draw_valid(f) || f->width<392 || f->height<248)return;
    const char hex[]="0123456789ABCDEF";
    char text[]="00-0000000000000000-00";
    text[0]='0'+r->error/10;text[1]='0'+r->error%10;
    for(unsigned i=0;i<16;i++)text[3+i]=hex[((uint64_t)r->offset>>(60-4*i))&15];
    text[20]=hex[(r->byte>>4)&15];text[21]=hex[r->byte&15];
    unsigned scale=f->width>=560?4:2,w=22*6*scale,h=9*scale;
    unsigned x=(f->width-w)/2,y=(f->height-66)/2+72;
    eg_draw_fill_rect(f,x,y,w,h,0);eg_draw_text(f,x,y+scale,scale,text);
#else
    (void)f;(void)r;
#endif
}
/* Injectable observer for system emulation; never Qualcomm emulation. */
unsigned dodge_select(uint64_t fdt, uint64_t image, uint64_t image_size,
                      uint64_t workspace, uint64_t workspace_size,
                      const struct eg_spmi_io *io
#ifdef DODGE_INTENT_PROTOTYPE
                      ,uint64_t *replacement
#endif
                      )
{
#ifdef DODGE_INTENT_PROTOTYPE
    if(!replacement)return 0;
    *replacement=0;
#endif
    struct eg_handoff handoff={0};
    struct eg_display_profile display=dodge_display_profile();
    struct eg_input in={.handoff=&handoff,.blob=(const void *)(uintptr_t)fdt,.fdt_pa=fdt,
        .image={image,image_size},.workspace={workspace,workspace_size},
        .display=&display};
    /* Bound accessible bytes by trusted bank end before reading even header.
     * mapped is an upper bound, not a speculative 2MiB read. The parser checks
     * validated totalsize against it before traversing the blob. */
    for(unsigned i=0;i<sizeof(dodge_observed_banks)/sizeof(*dodge_observed_banks);i++) {
        struct eg_range b=dodge_observed_banks[i];
        if(fdt>=b.base && fdt-b.base<b.size) {
            uint64_t left=b.size-(fdt-b.base);
            in.mapped=left<2*1024*1024?left:2*1024*1024;
            break;
        }
    }
    if(!dodge_profile_guard(&in)) return 0; /* BEFORE any observer access */
    if(!dodge_normal_mode(handoff.bootargs,handoff.bootargs_len) ||
       !eg_draw_valid(&handoff.fb) || handoff.fb.width<392 || handoff.fb.height<248) return 0;
    /* Explicit caller profile or matching descriptor; never inferred geometry. Entire framebuffer
     * allocation must also be disjoint from image/FDT (guard protects suffix). */
    struct eg_framebuffer f=handoff.fb;
    if((f.base<image+image_size && image<f.base+f.size) ||
       (f.base<fdt+in.mapped && fdt<f.base+f.size)) return 0;
    unsigned mapped_fb=0;
    for(unsigned i=0;i<sizeof(dodge_observed_banks)/sizeof(*dodge_observed_banks);i++) {
        struct eg_range b=dodge_observed_banks[i];
        if(f.base>=b.base && f.base-b.base<=b.size && f.size<=b.size-(f.base-b.base)) mapped_fb=1;
    }
    if(!mapped_fb) return 0;
    diagnostic(&f,0,0);
#ifdef DODGE_INTENT_PROTOTYPE
    uint64_t dst=(uintptr_t)eg_fdt_workspace,cap=(uintptr_t)eg_fdt_workspace_end-dst;
    if((dst&7) || cap!=2*1024*1024 || dst<workspace ||
       dst-workspace>workspace_size || cap>workspace_size-(dst-workspace)){diagnostic(&f,1,1);return 0;}
#ifdef DODGE_DIAGNOSTIC_STAGES
    struct eg_bootconfig_report report;
    unsigned slot=eg_bootconfig_slot_report((void *)(uintptr_t)handoff.initrd.base,handoff.initrd.size,&report);
    if(!slot){diagnostic_bootconfig(&f,&report);diagnostic(&f,2,1);return 0;}
#else
    unsigned slot=eg_bootconfig_slot((void *)(uintptr_t)handoff.initrd.base,handoff.initrd.size);
    if(!slot)return 0; /* no active-GPT fallback, no fabricated context */
#endif
#endif
    /* Cache both validated APIDs once per invocation, never during polling.
     * PON is sampled once for both Up and Power; GPIO6 is active-low Down. */
    struct menu_context ctx={.io=io,.fb=f};
    if(!eg_spmi_find(io,0x013,&ctx.pon) || !eg_spmi_find(io,0x18d,&ctx.gpio)) {diagnostic(&f,3,1);return 0;}
    struct eg_menu_io menu={.ctx=&ctx,.clock=clock_read,.keys=keys_read,.paint=paint};
#ifdef DODGE_INTENT_PROTOTYPE
    unsigned char token[EG_INTENT_BYTES];
    enum eg_choice_route route=eg_intent_selection(&menu,eg_request_pages,eg_request_generation,token);
    switch(route) {
    case EG_UBOOT_UNCHANGED: /* copied context, NOPREFWRITE (not a pending commit) */
    case EG_UBOOT_COMMIT_ANDROID:
    case EG_UBOOT_COMMIT_UBOOT:
        if(!eg_intent_bind_slot(token,eg_request_generation,slot) ||
           !eg_fdt_copy_intent(in.blob,in.mapped,(void *)(uintptr_t)dst,cap,token)){diagnostic(&f,5,1);return 0;}
        *replacement=dst;return 1;
    case EG_ORIGINAL_ANDROID: return 0;
    case EG_CHOICE_REFUSED: diagnostic(&f,4,1);return 0;
    }
    return 0;
#else
    return eg_menu(&menu,eg_request_select(eg_request_pages,eg_request_generation));
#endif
}
unsigned eg_bootstrap_policy(uint64_t fdt,uint64_t image,uint64_t image_size,
                             uint64_t workspace,uint64_t workspace_size
#ifdef DODGE_INTENT_PROTOTYPE
                             ,uint64_t *replacement
#endif
                             )
{
    struct eg_spmi_io io={.read=read32,.write=write32};
    dodge_spmi_maps(&io);
    return dodge_select(fdt,image,image_size,workspace,workspace_size,&io
#ifdef DODGE_INTENT_PROTOTYPE
                        ,replacement
#endif
                        );
}
