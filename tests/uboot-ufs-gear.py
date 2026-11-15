#!/usr/bin/env python3
"""Host-compile UFS gear selection and source table overlay dispatch.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-ufs-gear.py PATCHED_UBOOT
"""
from pathlib import Path
import re, subprocess, tempfile, sys
source=Path(sys.argv[1]).resolve()
def function(path,name):
    x=(source/path).read_text();m=re.search(r'(?m)^static [^\n]*\b'+name+r'\(',x);assert m,name
    a=m.start();b=x.index('{',a);depth=1;e=b+1
    while depth:depth+=(x[e]=='{')-(x[e]=='}');e+=1
    return x[a:e]+'\n'
boiler=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
typedef uint32_t u32;
#define GENMASK(h,l) ((~0U << (l)) & (~0U >> (31-(h))))
#define FIELD_GET(mask,x) (((x)&(mask)) >> __builtin_ctz(mask))
#define UFS_HS_G3 3
#define UFS_QCOM_MAX_GEAR(x) (((x)>>4)&7)
#define REG_UFS_PARAM0 0xe0
#define min(a,b) ((a)<(b)?(a):(b))
#define dev_info(...) ((void)0)
struct udevice {void *priv;};struct ufs_hba {struct udevice *dev;};
struct ufs_qcom_priv {struct {int major;}hw_ver;};
static u32 param0=5<<4,limit;static int reads;static bool compatible=true;
static void *dev_get_priv(struct udevice*d){return d->priv;}
static u32 dev_read_u32_default(struct udevice*d,const char*n,u32 fallback){return limit;}
static u32 ufshcd_readl(struct ufs_hba*h,int r){reads++;return param0;}
static bool device_is_compatible(struct udevice*d,const char*s){return compatible;}
enum phy_mode {PHY_MODE_UFS_HS_A,PHY_MODE_UFS_HS_B,OTHER_MODE};
struct qmp_ufs_cfg_tbls {int id;};
struct qmp_ufs_cfg {int max_supported_gear;struct qmp_ufs_cfg_tbls tbls,tbls_hs_g4,tbls_hs_g5,tbls_hs_b;};
struct qmp_ufs_priv {const struct qmp_ufs_cfg *cfg;int mode,submode;};
struct phy {struct udevice *dev;};
static int overlays[16],n;
static void qmp_ufs_init_all(struct qmp_ufs_priv*q,const struct qmp_ufs_cfg_tbls*t){overlays[n++]=t->id;}
static void qmp_ufs_serdes_init(struct qmp_ufs_priv*q,const struct qmp_ufs_cfg_tbls*t){overlays[n++]=10+t->id;}
static void qmp_ufs_lanes_init(struct qmp_ufs_priv*q,const struct qmp_ufs_cfg_tbls*t){overlays[n++]=20+t->id;}
static void qmp_ufs_pcs_init(struct qmp_ufs_priv*q,const struct qmp_ufs_cfg_tbls*t){overlays[n++]=30+t->id;}
'''
code=boiler+function('drivers/ufs/ufs-qcom.c','ufs_qcom_get_hs_gear')+function('drivers/ufs/ufs-qcom.c','ufs_qcom_get_phy_gear')+function('drivers/phy/qcom/phy-qcom-qmp-ufs.c','qmp_ufs_set_mode')+function('drivers/phy/qcom/phy-qcom-qmp-ufs.c','qmp_ufs_init_registers')+r'''
int main(void){
 struct ufs_qcom_priv host={{6}};struct udevice d={&host};struct ufs_hba h={&d};
 assert(ufs_qcom_get_hs_gear(&h)==5);assert(reads==1);limit=4;assert(ufs_qcom_get_hs_gear(&h)==4);
 limit=3;assert(ufs_qcom_get_phy_gear(&h)==5);assert(ufs_qcom_get_hs_gear(&h)==3);compatible=false;assert(ufs_qcom_get_phy_gear(&h)==3);
 host.hw_ver.major=4;limit=0;reads=0;assert(ufs_qcom_get_hs_gear(&h)==3);assert(!reads);
 struct qmp_ufs_cfg cfg={5,{1},{4},{5},{2}};struct qmp_ufs_priv q={&cfg};d.priv=&q;struct phy p={&d};
 assert(!qmp_ufs_set_mode(&p,PHY_MODE_UFS_HS_B,5));qmp_ufs_init_registers(&q,&cfg);assert(n==3&&overlays[0]==1&&overlays[1]==5&&overlays[2]==2);
 n=0;assert(!qmp_ufs_set_mode(&p,PHY_MODE_UFS_HS_B,4));qmp_ufs_init_registers(&q,&cfg);assert(n==3&&overlays[1]==4);
 assert(qmp_ufs_set_mode(&p,PHY_MODE_UFS_HS_B,6)==-EINVAL);assert(qmp_ufs_set_mode(&p,OTHER_MODE,5)==-EINVAL);
 n=0;cfg.max_supported_gear=0;assert(!qmp_ufs_set_mode(&p,OTHER_MODE,99));qmp_ufs_init_registers(&q,&cfg);assert(n==5&&overlays[0]==11&&overlays[1]==12&&overlays[2]==14&&overlays[3]==21&&overlays[4]==31);
}
'''
# Match the actual PARAM0 gear field; fail rather than testing a guessed encoding.
header=(source/'drivers/ufs/ufs-qcom.h').read_text()
assert '#define UFS_QCOM_MAX_GEAR(x)' in header
code=re.search(r'(?m)^#define MAX_HS_GEAR_MASK.*$',header)[0]+'\n'+code
code=code.replace('#define UFS_QCOM_MAX_GEAR(x) (((x)>>4)&7)', re.search(r'(?m)^#define UFS_QCOM_MAX_GEAR\(x\).*$',header)[0])
with tempfile.TemporaryDirectory(prefix='uboot-ufs-gear-') as tmp:
    p=Path(tmp);(p/'test.c').write_text(code);subprocess.run(['cc','-std=gnu11','-Wall',str(p/'test.c'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
dts=(source/'dts/upstream/src/arm64/qcom/sm8750-oneplus-dodge.dts').read_text();assert re.search(r'limit-hs-gear\s*=\s*<3>',dts)
print('PASS: actual PARAM0/default and explicit-limit selection, G5/G4 overlays, invalid modes/gears and legacy PHY sequence; SM8750 max PHY calibration remains independent of negotiated G3 cap')
