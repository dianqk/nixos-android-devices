/* SPDX-License-Identifier: GPL-2.0-only */
#include "fdt-guard.h"
#define MAX_FDT (2U * 1024U * 1024U)
#define MAX_DEPTH 32
#define MAX_BANKS 32
static uint32_t u32(const unsigned char *p)
{ return (uint32_t)p[0]<<24 | (uint32_t)p[1]<<16 | (uint32_t)p[2]<<8 | p[3]; }
static uint64_t u64(const unsigned char *p)
{ return (uint64_t)u32(p)<<32 | u32(p+4); }
static int valid(struct eg_range r) { return r.size && r.base <= UINT64_MAX-r.size; }
static int inside(struct eg_range r, struct eg_range b)
{ return valid(r) && valid(b) && r.base >= b.base && r.base-b.base <= b.size && r.size <= b.size-(r.base-b.base); }
static int overlap(struct eg_range a, struct eg_range b)
{ return a.base < b.base+b.size && b.base < a.base+a.size; }
static int inbanks(struct eg_range r, const struct eg_range *b, size_t n)
{ for (size_t i=0;i<n;i++) if (inside(r,b[i])) return 1; return 0; }
static int eq(const unsigned char *s, size_t n, const char *t)
{ size_t i=0; while (t[i]) { if (i>=n || s[i]!=(unsigned char)t[i]) return 0; i++; } return i==n; }
static int named(const unsigned char *s,size_t n,const char *t)
{ size_t i=0; while(t[i]) { if(i>=n || s[i]!=(unsigned char)t[i]) return 0; i++; } return i==n || s[i]=='@'; }
static int span(uint32_t o,uint32_t n,uint32_t total)
{ return o<=total && n<=total-o; }
struct node {
    unsigned kind, child, ac, sc, ranges, reg_seen, dynamic, fb, memtype;
    const unsigned char *reg;
    uint32_t len;
    struct eg_dynamic dyn;
    struct eg_framebuffer geometry;
    unsigned geometry_seen, disabled, rotation, rot_seen;
};
/* Kinds: ordinary, root, memory, reserved-memory, reservation, chosen. */
static int guard(const struct eg_input *in, int exact)
{
    const unsigned char *p=in->blob;
    struct eg_range fdt={in->fdt_pa,40}, dtbanks[MAX_BANKS];
    struct node nodes[MAX_DEPTH];
    uint32_t total,so,ss,st,sn,ro,at,end; unsigned depth=0, roots=0, nb=0, chosen=0,reserved=0;
    uint64_t initstart=0,initend=0; unsigned initmask=0, framebuffers=0, profile_reserved=0;
    struct eg_handoff handoff={0};
    if (!p || in->mapped<40 || in->bank_count>MAX_BANKS || !in->bank_count ||
        in->live_count>64 || !inbanks(fdt,in->banks,in->bank_count) ||
        !inside(in->workspace,in->image) || !inbanks(in->image,in->banks,in->bank_count)) return 0;
    for(size_t i=0;i<in->live_count;i++)
        if(!valid(in->live[i]) || overlap(in->live[i],in->workspace)) return 0;
    total=u32(p+4);
    if(u32(p)!=0xd00dfeed || total<40 || total>MAX_FDT || total>in->mapped) return 0;
    fdt.size=total;
    if(!inbanks(fdt,in->banks,in->bank_count) || overlap(fdt,in->workspace)) return 0;
    /* Only v17, canonical disjoint block order. No totalsize-driven reads yet. */
    so=u32(p+8); st=u32(p+12); ro=u32(p+16); sn=u32(p+32); ss=u32(p+36);
    if(u32(p+20)!=17 || u32(p+24)>17 || ro<40 || ro%8 || so%4 || ss%4 ||
       !span(so,ss,total) || !span(st,sn,total) || ro>so || so+ss>st) return 0;
    at=ro;
    for(;;) {
        struct eg_range r;
        if(!span(at,16,so)) return 0;
        r.base=u64(p+at); r.size=u64(p+at+8); at+=16;
        if(!r.base && !r.size) break;
        if(!valid(r) || overlap(r,in->workspace)) return 0;
    }
    at=so; end=so+ss;
    while(span(at,4,end)) {
        uint32_t token=u32(p+at); at+=4;
        if(token==1) {
            uint32_t start=at; unsigned kind=0;
            if(depth==MAX_DEPTH) return 0;
            while(at<end && p[at]) at++;
            if(at==end) return 0;
            if(!depth) { if(roots++ || at!=start) return 0; kind=1; }
            else {
                struct node *parent=&nodes[depth-1]; parent->child=1;
                if(depth==1 && named(p+start,at-start,"memory")) kind=2;
                if(depth==1 && named(p+start,at-start,"reserved-memory")) {
                    if(!eq(p+start,at-start,"reserved-memory") || reserved++) return 0;
                    kind=3;
                }
                if(depth==1 && eq(p+start,at-start,"chosen")) { if(chosen++) return 0; kind=5; }
                if(parent->kind==3) kind=4;
            }
            nodes[depth++]=(struct node){.kind=kind, .dyn={.name=p+start,.name_len=at-start}};
            at=(at+4)&~3U; if(at>end) return 0;
        } else if(token==3) {
            uint32_t len,no,start; struct node *n;
            if(!depth || !span(at,8,end)) return 0;
            len=u32(p+at); no=u32(p+at+4); at+=8;
            if(!span(at,len,end) || no>=sn) return 0;
            start=no; while(no<sn && p[st+no]) no++; if(no==sn) return 0;
            n=&nodes[depth-1]; if(n->child) return 0;
#define PROP(s) eq(p+st+start,no-start,s)
            if(n->kind==1 && (PROP("model") || PROP("qcom,board-id"))) {
                const unsigned char **v=PROP("model")?&handoff.model:&handoff.board_id;
                size_t *z=PROP("model")?&handoff.model_len:&handoff.board_id_len;
                if(*v || !len) return 0;
                *v=p+at; *z=len;
            } else if(PROP("width") || PROP("height") || PROP("stride")) {
                unsigned bit=PROP("width")?1:PROP("height")?2:4;
                if((n->geometry_seen&bit) || len!=4) return 0;
                n->geometry_seen|=bit;
                if(bit==1) n->geometry.width=u32(p+at);
                else if(bit==2) n->geometry.height=u32(p+at);
                else n->geometry.stride=u32(p+at);
            } else if(PROP("format")) {
                if(n->geometry_seen&8) return 0;
                n->geometry_seen|=8;
                n->geometry.rgb32=0;
                if(len==9 && !p[at+8]) {
                    if(eq(p+at,8,"a8r8g8b8")) n->geometry.rgb32=1;
                    if(eq(p+at,8,"x8r8g8b8")) n->geometry.rgb32=2;
                    if(eq(p+at,8,"a8b8g8r8")) n->geometry.rgb32=3;
                    if(eq(p+at,8,"x8b8g8r8")) n->geometry.rgb32=4;
                }
            } else if(PROP("rot")) {
                if(n->rot_seen++ || len!=4) return 0;
                n->rotation=u32(p+at);
            } else if(PROP("status")) {
                n->disabled=!(len==5 && eq(p+at,4,"okay") && !p[at+4]);
            } else if(n->kind==5 && PROP("bootargs")) {
                if(handoff.bootargs || !len || p[at+len-1]) return 0;
                handoff.bootargs=p+at; handoff.bootargs_len=len-1;
            } else if(PROP("#address-cells") || PROP("#size-cells")) {
                unsigned *v=PROP("#address-cells")?&n->ac:&n->sc;
                if(*v || len!=4) return 0;
                *v=u32(p+at); if((n->kind==1 || n->kind==3) && *v!=2) return 0;
            } else if(PROP("ranges") && (n->kind==3 || n->kind==5)) { if(n->ranges++ || len) return 0;
            } else if(PROP("reg")) {
                if(n->reg_seen++) return 0;
                n->reg=p+at; n->len=len;
            } else if(PROP("size") && n->kind==4) {
                if(n->dynamic++ || len!=8) return 0;
                n->dyn.size=u64(p+at); if(!n->dyn.size) return 0;
            } else if(n->kind==4 && PROP("alignment")) {
                if(n->dyn.alignment || len!=8) return 0;
                n->dyn.alignment=p+at; n->dyn.alignment_len=len;
            } else if(n->kind==4 && PROP("alloc-ranges")) {
                if(n->dyn.alloc_ranges || !len || len%16) return 0;
                n->dyn.alloc_ranges=p+at; n->dyn.alloc_ranges_len=len;
            } else if((PROP("no-map") || PROP("reusable")) && n->kind==4) {
                unsigned *v=PROP("no-map")?&n->dyn.no_map:&n->dyn.reusable;
                if(len || (*v)++) return 0;
            }
            else if(PROP("device_type")) {
                if(len==7 && eq(p+at,6,"memory") && !p[at+6] && n->kind!=2) return 0;
                if(n->kind==2 && (n->memtype++ || len!=7 || !eq(p+at,6,"memory") || p[at+6])) return 0;
            } else if(PROP("compatible")) {
                uint32_t j=0;
                if(n->dyn.compatible) return 0;
                n->dyn.compatible=p+at; n->dyn.compatible_len=len;
                if(n->kind==1) { handoff.compatible=p+at; handoff.compatible_len=len; }
                while(j<len) {
                    uint32_t k=j; while(j<len && p[at+j]) j++; if(j==len) return 0;
                    if(eq(p+at+k,j-k,"simple-framebuffer")) n->fb=1;
                    j++;
                }
            } else if(n->kind==5 && (PROP("linux,initrd-start") || PROP("linux,initrd-end"))) {
                unsigned bit=PROP("linux,initrd-start")?1:2;
                if((initmask&bit) || len!=8) return 0;
                initmask|=bit; if(bit==1) initstart=u64(p+at); else initend=u64(p+at);
            } else if(n->kind==5 && (PROP("linux,usable-memory-range") || PROP("linux,elfcorehdr"))) return 0;
#undef PROP
            if(len>UINT32_MAX-3) return 0;
            at+=(len+3)&~3U; if(at>end) return 0;
        } else if(token==2) {
            struct node *n;
            if(!depth) return 0;
            n=&nodes[--depth];
            if((n->kind==1 || n->kind==3) && (n->ac!=2 || n->sc!=2)) return 0;
            if(n->kind==3 && !n->ranges) return 0;
            if(n->kind==2 && !n->memtype) return 0;
            if(n->kind==4 && n->child) return 0;
            if(n->kind==4 && n->dynamic) {
                if(n->reg_seen || !in->allow_dynamic || !in->allow_dynamic(&n->dyn)) return 0;
                continue;
            }
            if(in->display && n->fb && (n->disabled || n->rotation)) return 0;
            if(in->display && n->kind==4 && in->display->reservation_name &&
               eq(n->dyn.name,n->dyn.name_len,in->display->reservation_name)) {
                if(profile_reserved++ || !n->reg || n->len!=16 ||
                   u64(n->reg)!=in->display->reservation.base ||
                   u64(n->reg+8)!=in->display->reservation.size) return 0;
            }
            if(n->fb && !n->disabled) {
                if(framebuffers++) return 0;
                if(n->geometry_seen==15 && n->geometry.rgb32 && n->len==16 && n->reg) {
                    handoff.fb=n->geometry;
                    handoff.fb.base=u64(n->reg); handoff.fb.size=u64(n->reg+8);
                }
            }
            if(n->kind==2 || n->kind==4 || n->fb) {
                if(!n->reg_seen || !n->len || n->len%16) return 0;
                /* No address translation; framebuffer only root or chosen child. */
                if(n->fb && !(depth==1 || (depth==2 && nodes[1].kind==5 &&
                    nodes[1].ac==2 && nodes[1].sc==2))) return 0;
                for(uint32_t j=0;j<n->len;j+=16) {
                    struct eg_range r={u64(n->reg+j),u64(n->reg+j+8)};
                    /* Empty tuples describe no bytes. Skip before ANY range
                     * arithmetic; never fill holes or widen adjacent banks. */
                    if(!r.size) continue;
                    if(!valid(r)) return 0;
                    if(n->kind==2) { if(nb==MAX_BANKS) return 0; dtbanks[nb++]=r; }
                    else if(overlap(r,in->workspace)) return 0;
                }
            }
        } else if(token==4) continue;
        else if(token==9) {
            if(depth || roots!=1 || at!=end || !nb || (initmask && initmask!=3)) return 0;
            if(initmask && (initend<=initstart || overlap((struct eg_range){initstart,initend-initstart},in->workspace))) return 0;
            if (exact) {
                if (nb != in->bank_count) return 0;
                for (unsigned i=0;i<nb;i++)
                    if (dtbanks[i].base!=in->banks[i].base ||
                        dtbanks[i].size!=in->banks[i].size) return 0;
            }
            if(!inbanks(in->image,dtbanks,nb) || !inbanks(fdt,dtbanks,nb)) return 0;
            if(initmask) {
                struct eg_range r={initstart,initend-initstart};
                if(!inbanks(r,in->banks,in->bank_count) || !inbanks(r,dtbanks,nb) ||
                   overlap(r,in->image) || overlap(r,fdt)) return 0;
                for(size_t i=0;i<in->live_count;i++) if(overlap(r,in->live[i])) return 0;
                handoff.initrd=r;
            }
            if(in->display) {
                const struct eg_display_profile *d=in->display;
                struct eg_framebuffer f=d->fb;
                struct eg_range r={f.base,f.size};
                if(!profile_reserved || !d->matches || !d->matches(&handoff) ||
                   !inside(r,d->reservation) || !inbanks(r,dtbanks,nb) ||
                   !f.width || f.width>8192 || !f.height || f.height>8192 ||
                   !f.rgb32 || f.rgb32>4 || (f.base&3) || (f.stride&3) ||
                   f.stride<(uint64_t)f.width*4 || f.stride>65536 ||
                   (uint64_t)f.stride*f.height>f.size ||
                   overlap(r,in->image) || overlap(r,fdt) ||
                   (initmask && overlap(r,(struct eg_range){initstart,initend-initstart}))) return 0;
                for(size_t i=0;i<in->live_count;i++) if(overlap(r,in->live[i])) return 0;
                if(framebuffers && (handoff.fb.base!=f.base || handoff.fb.size!=f.size ||
                   handoff.fb.width!=f.width || handoff.fb.height!=f.height ||
                   handoff.fb.stride!=f.stride || handoff.fb.rgb32!=f.rgb32)) return 0;
                handoff.fb=f;
            }
            if(in->handoff) *in->handoff=handoff;
            return 1;
        } else return 0;
    }
    return 0;
}

int eg_fdt_guard(const struct eg_input *in) { return guard(in,0); }
int eg_fdt_guard_exact(const struct eg_input *in) { return guard(in,1); }
