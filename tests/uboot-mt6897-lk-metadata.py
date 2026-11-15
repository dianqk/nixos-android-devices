#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile production handover functions with real libfdt and fault injection."""
from pathlib import Path
import subprocess,hashlib,re,os,sys,tempfile
if len(sys.argv)!=2:raise SystemExit('Usage: uboot-mt6897-lk-metadata.py UBOOT_SOURCE')
source=Path(sys.argv[1]).resolve()
work=tempfile.TemporaryDirectory(prefix='uboot-lk-metadata-')
w=Path(work.name)
s=(source/'board/mediatek/mediatek-mobile/mediatek-mobile.c').read_text();a=s.index('/* LK descriptors are little-endian');b=s.index('/* Forward LK\'s fixed reservations',a)
def fn(name):
 m=re.search(r'^(?:static )?(?:int|void|bool)\s+'+name+r'\([^;]*?\)\n\{',s,re.M)
 assert m,name
 start=m.start();brace=m.end()-1;depth=1;i=brace+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]+'\n'
functions=fn('mtk_add_reserved')+fn('mtk_overlaps')+s[a:b]+fn('ft_board_setup')
preamble=r'''
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <errno.h>
#include <libfdt.h>
typedef uint8_t u8;typedef uint32_t u32;typedef unsigned long long u64;typedef int32_t s32;
#define SZ_4K 4096ULL
#define SZ_64K 65536ULL
#define U64_MAX UINT64_MAX
#define IS_ALIGNED(x,a) (!((x)&((a)-1)))
static uint32_t get_unaligned_le32(const void*p){uint32_t v;memcpy(&v,p,4);return v;}
static uint64_t get_unaligned_le64(const void*p){uint64_t v;memcpy(&v,p,8);return v;}
static uint64_t get_unaligned_be64(const void*p){return fdt64_ld(p);}
struct mtk_region {u64 start,size;bool nomap;};
static struct mtk_region mtk_banks[2],mtk_reserved[128];
static int mtk_bank_count,mtk_reserved_count;
static u64 mtk_lk_fdt,mtk_fb_start,mtk_fb_size;
struct bd_info {int unused;};
#define MTK_MAX_RESERVED 128
#define log_err(...) fprintf(stderr,__VA_ARGS__)
#define log_warning(...) fprintf(stderr,__VA_ARGS__)
static int alloc_fail,del_fail,set_fail,del_calls;
static void *test_malloc(size_t n){return alloc_fail?NULL:malloc(n);}
static int test_del(void*f,int n,const char*p){return ++del_calls==del_fail?-FDT_ERR_BADVALUE:fdt_delprop(f,n,p);}
static int test_set(void*f,int n,const char*p,const void*d,int len){return set_fail?-FDT_ERR_NOSPACE:fdt_setprop(f,n,p,d,len);}
#define malloc test_malloc
#define fdt_delprop test_del
#define fdt_setprop test_set
'''
tests=r'''
#undef malloc
#undef fdt_delprop
#undef fdt_setprop
static unsigned char src[8192] __attribute__((aligned(8))),dst[8192] __attribute__((aligned(8)));
static unsigned char descriptor[48];static int tests;
static void put32(void*p,uint32_t v){memcpy(p,&v,4);}static void put64(void*p,uint64_t v){memcpy(p,&v,8);}
static int node(void*f){return fdt_node_offset_by_compatible(f,-1,"mediatek,mddriver");}
static void make(void*f){assert(!fdt_create_empty_tree(f,8192));int n=fdt_add_subnode(f,0,"mddriver");assert(n>=0);assert(!fdt_setprop_string(f,n,"compatible","mediatek,mddriver"));assert(!fdt_setprop_u32(f,n,"mediatek,ap-plat-info",6897));}
static void reserve(void*f,u64 size,bool nomap){int p=fdt_add_subnode(f,0,"reserved-memory");assert(p>=0);assert(!fdt_setprop_u32(f,p,"#address-cells",2));assert(!fdt_setprop_u32(f,p,"#size-cells",2));int n=fdt_add_subnode(f,p,"lk-reserved@bf2f0000");assert(n>=0);fdt64_t reg[2]={cpu_to_fdt64(0xbf2f0000),cpu_to_fdt64(size)};assert(!fdt_setprop(f,n,"reg",reg,sizeof(reg)));if(nomap)assert(!fdt_setprop_empty(f,n,"no-map"));}
static void reset(void){make(src);make(dst);reserve(src,SZ_64K,1);reserve(dst,SZ_64K,1);memset(descriptor,0xa5,sizeof(descriptor));put64(descriptor,0xbf2f0000);put32(descriptor+8,0x1840);put32(descriptor+12,0);put32(descriptor+16,3);put32(descriptor+20,28);put32(descriptor+24,1);put32(descriptor+28,0);mtk_lk_fdt=(uintptr_t)src;mtk_bank_count=mtk_reserved_count=1;mtk_banks[0]=(struct mtk_region){0x40000000,0x300000000,0};mtk_reserved[0]=(struct mtk_region){0xbf2f0000,SZ_64K,1};alloc_fail=del_fail=set_fail=del_calls=0;assert(!fdt_setprop(dst,node(dst),"ccci,modem_info_v2",descriptor,48));assert(!fdt_setprop(dst,node(dst),"ccci,modem_info",descriptor,16));}
static void source(bool v2,int len){assert(!fdt_setprop(src,node(src),v2?"ccci,modem_info_v2":"ccci,modem_info",descriptor,len));}
static void disabled(void){assert(!mtk_forward_modem_info(dst));assert(!fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));assert(!fdt_getprop(dst,node(dst),"ccci,modem_info",NULL));assert(fdt_getprop(dst,node(dst),"mediatek,ap-plat-info",NULL));tests++;}
int main(void){
 reset();source(1,48);assert(!mtk_forward_modem_info(dst));int len;const void*p=fdt_getprop(dst,node(dst),"ccci,modem_info_v2",&len);assert(len==48&&!memcmp(p,descriptor,48));assert(!fdt_getprop(dst,node(dst),"ccci,modem_info",NULL));tests++;
 reset();source(1,48);assert(!mtk_forward_modem_info(src));p=fdt_getprop(src,node(src),"ccci,modem_info_v2",&len);assert(len==48&&!memcmp(p,descriptor,48));tests++;
 for(int v=1;v<=3;v++){reset();put32(descriptor+16,v);source(1,32);assert(!mtk_forward_modem_info(dst));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));tests++;}
 reset();put32(descriptor+16,INT32_MAX);source(1,48);assert(!mtk_forward_modem_info(dst));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));tests++;
 reset();put32(descriptor+12,28);source(0,16);assert(!mtk_forward_modem_info(dst));p=fdt_getprop(dst,node(dst),"ccci,modem_info",&len);assert(len==16&&!memcmp(p,descriptor,16));tests++;
 for(int n=0;n<32;n++){reset();source(1,n);disabled();}
 for(int n=0;n<16;n++){reset();source(0,n);disabled();}
 reset();disabled();reset();mtk_lk_fdt=0;disabled();
 for(int variant=0;variant<12;variant++){reset();switch(variant){case0:put64(descriptor,0xbf2f0001);break;case1:put64(descriptor,UINT64_MAX-4095);break;case2:put32(descriptor+8,0);break;case3:put32(descriptor+8,65537);break;case4:put32(descriptor+16,0);break;case5:put32(descriptor+16,0x80000000);break;case6:put32(descriptor+20,0xffffffff);break;case7:put32(descriptor+20,0);break;case8:put32(descriptor+20,65536);break;case9:mtk_reserved[0].size=0x1840;break;case10:mtk_reserved[0].nomap=0;break;case11:mtk_banks[0].size=1;break;}source(1,48);disabled();}
 reset();put64(descriptor,0);put32(descriptor+12,0);source(1,48);assert(!mtk_forward_modem_info(dst));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));tests++;
 reset();put64(descriptor,0);put32(descriptor+12,1);source(1,48);disabled();
 reset();source(0,16);source(1,3);disabled();
 reset();source(1,48);alloc_fail=1;disabled();
 reset();source(1,48);int n=fdt_add_subnode(src,0,"duplicate");assert(n>=0);assert(!fdt_setprop_string(src,n,"compatible","mediatek,mddriver"));disabled();
 reset();source(1,48);n=fdt_add_subnode(dst,0,"duplicate");assert(n>=0);assert(!fdt_setprop_string(dst,n,"compatible","mediatek,mddriver"));assert(mtk_forward_modem_info(dst)<0);tests++;
 reset();source(1,48);assert(!fdt_del_node(dst,node(dst)));assert(!mtk_forward_modem_info(dst));assert(node(dst)==-FDT_ERR_NOTFOUND);tests++;
 for(int n=1;n<=2;n++){reset();source(1,48);del_fail=n;assert(mtk_forward_modem_info(dst)<0);tests++;}
 reset();source(1,48);set_fail=1;assert(mtk_forward_modem_info(dst)<0);tests++;
 /* Exercise the actual reservation handover, not only its leaf helper. */
 reset();source(1,48);assert(!fdt_del_node(dst,fdt_path_offset(dst,"/reserved-memory")));assert(!ft_board_setup(dst,NULL));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));assert(mtk_modem_fdt_reserved(dst,0xbf2f0000));tests++;
 reset();source(1,48);mtk_reserved_count=0;mtk_add_reserved(0xbf2f0000,SZ_64K,0);mtk_add_reserved(0xbf2f0000,SZ_64K,1);assert(mtk_reserved_count==1&&mtk_reserved[0].nomap);assert(!fdt_del_node(dst,fdt_path_offset(dst,"/reserved-memory")));assert(!ft_board_setup(dst,NULL));assert(mtk_modem_fdt_reserved(dst,0xbf2f0000));tests++;
 reset();source(1,48);int rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_delprop(dst,rn,"no-map"));assert(!ft_board_setup(dst,NULL));assert(mtk_modem_fdt_reserved(dst,0xbf2f0000));tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");fdt64_t stale[2]={cpu_to_fdt64(0xbf2f0000),cpu_to_fdt64(0x1840)};assert(!fdt_setprop(dst,rn,"reg",stale,sizeof(stale)));assert(ft_board_setup(dst,NULL)<0);tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");stale[0]=cpu_to_fdt64(0xbf300000);stale[1]=cpu_to_fdt64(SZ_64K);assert(!fdt_setprop(dst,rn,"reg",stale,sizeof(stale)));assert(ft_board_setup(dst,NULL)<0);tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");stale[0]=cpu_to_fdt64(0xbf2f0000);stale[1]=cpu_to_fdt64(SZ_64K+4096);assert(!fdt_setprop(dst,rn,"reg",stale,sizeof(stale)));assert(!ft_board_setup(dst,NULL));assert(mtk_modem_fdt_reserved(dst,0xbf2f0000));tests++;
 reset();source(1,48);assert(!ft_board_setup(src,NULL));p=fdt_getprop(src,node(src),"ccci,modem_info_v2",&len);assert(len==48&&!memcmp(p,descriptor,48));tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_empty(dst,rn,"reusable"));assert(ft_board_setup(dst,NULL)<0);tests++;
 reset();source(1,48);assert(!fdt_del_node(dst,fdt_path_offset(dst,"/reserved-memory")));disabled();
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_delprop(dst,rn,"no-map"));disabled();
 reset();source(1,48);rn=fdt_path_offset(src,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_string(src,rn,"status","disabled"));disabled();
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_string(dst,rn,"status","disabled"));disabled();
 reset();source(1,48);rn=fdt_path_offset(src,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_empty(src,rn,"reusable"));disabled();
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_empty(dst,rn,"reusable"));disabled();
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_string(dst,rn,"status","ok"));assert(!ft_board_setup(dst,NULL));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop(dst,rn,"status","okay",4));disabled();
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");assert(!fdt_setprop_string(dst,rn,"status","disabled"));assert(ft_board_setup(dst,NULL)<0);tests++;
 reset();source(1,48);rn=fdt_path_offset(dst,"/reserved-memory/lk-reserved@bf2f0000");stale[0]=cpu_to_fdt64(0xbf2f0000);stale[1]=cpu_to_fdt64(UINT64_MAX);assert(!fdt_setprop(dst,rn,"reg",stale,sizeof(stale)));assert(ft_board_setup(dst,NULL)<0);tests++;
 reset();source(1,48);mtk_banks[0].size=UINT64_MAX;disabled();
 reset();source(1,48);mtk_reserved[0].size=UINT64_MAX;disabled();
 /* Deliberately force both reg property data pointers to 4 mod 8. */
 reset();source(1,48);for(int which=0;which<2;which++){void*f=which?dst:src;rn=fdt_path_offset(f,"/reserved-memory/lk-reserved@bf2f0000");const void*reg=fdt_getprop(f,rn,"reg",NULL);if(!((uintptr_t)reg%8))assert(!fdt_setprop_empty(f,rn,"alignment-pad"));reg=fdt_getprop(f,rn,"reg",NULL);assert((uintptr_t)reg%8==4);}assert(!ft_board_setup(dst,NULL));assert(fdt_getprop(dst,node(dst),"ccci,modem_info_v2",NULL));tests++;
 printf("PASS %d real-libfdt production forwarding scenarios\n",tests);
}
'''.replace('case0:','case 0:').replace('case1:','case 1:').replace('case2:','case 2:').replace('case3:','case 3:').replace('case4:','case 4:').replace('case5:','case 5:').replace('case6:','case 6:').replace('case7:','case 7:').replace('case8:','case 8:').replace('case9:','case 9:').replace('case10:','case 10:').replace('case11:','case 11:')
(w/'forward-test.c').write_text(preamble+functions+tests)
lib=source/'scripts/dtc/libfdt'
subprocess.run([os.environ.get('CC','cc'),'-std=gnu11','-Wall','-Wextra','-Werror',
 '-Wno-unused-parameter','-fsanitize=address,undefined','-I'+str(lib),
 str(w/'forward-test.c'),*[str(p) for p in sorted(lib.glob('*.c'))],
 '-o',str(w/'forward-test')],check=True)
subprocess.run([str(w/'forward-test')],check=True)
print('production source SHA256',hashlib.sha256(s.encode()).hexdigest())
work.cleanup()
