#!/usr/bin/env python3
"""Host-compile SM8750 UFS reset/calibration paths with recording hardware mocks.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-ufs-host-reset.py PATCHED_UBOOT
"""
from pathlib import Path
import re,subprocess,tempfile,sys
s=Path(sys.argv[1]).resolve()
workspace=tempfile.TemporaryDirectory(prefix='uboot-ufs-reset-')
o=Path(workspace.name)
def f(path,name):
 x=(s/path).read_text();m=re.search(r'(?m)^static (?:const )?[^\n]*\b'+name+r'\(',x);assert m,name;a=m.start();b=x.index('{',a);d=1;e=b+1
 while d:d+=(x[e]=='{')-(x[e]=='}');e+=1
 return x[a:e]+'\n'
phy='drivers/phy/qcom/phy-qcom-qmp-ufs.c';host='drivers/ufs/ufs-qcom.c'
# Compile the actual power-on path and provider functions with recording hardware stubs.
c=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stddef.h>
#define __iomem
#define REG_UFS_CFG1 0xdc
#define UFS_PHY_SOFT_RESET 2
#define SW_PWRDN 1
#define SW_RESET 1
#define SERDES_START 1
#define PCS_READY 1
#define PHY_INIT_COMPLETE_TIMEOUT 100
#define QPHY_PCS_POWER_DOWN_CONTROL 0
#define QPHY_SW_RESET 1
#define QPHY_START_CTRL 2
#define QPHY_PCS_READY_STATUS 3
#define dev_err(...) ((void)0)
#define dev_info(...) ((void)0)
typedef uint32_t u32;
struct udevice {void *priv; void *base; struct udevice *parent;};
struct reset_ctl {struct udevice *dev; unsigned long id;};
struct qmp_ufs_cfg {bool host_phy_reset,no_pcs_sw_reset; unsigned regs[4];};
struct qmp_ufs_priv {const struct qmp_ufs_cfg *cfg;void *pcs;struct reset_ctl host_reset;};
struct phy {struct udevice *dev;};
static int events[32],n,fail_assert,fail_deassert,fail_ready;
static u32 regval;
static void ev(int x){events[n++]=x;}
static void *dev_get_priv(struct udevice*d){return d->priv;}
static void *dev_read_addr_ptr(struct udevice*d){return d->base;}
static u32 readl(void*p){assert(p==(void*)0x10dc);ev(8);return regval;}
static void writel(u32 v,void*p){assert(p==(void*)0x10dc);regval=v;ev(9);}
static void mdelay(int d){assert(d==1);ev(10);}
static int reset_assert(struct reset_ctl*r){ev(2);return fail_assert;}
static int reset_deassert(struct reset_ctl*r){ev(4);return fail_deassert;}
static void qphy_setbits(void*p,unsigned r,unsigned v){ev(r==0?1:6);}
static void qphy_clrbits(void*p,unsigned r,unsigned v){assert(r==1);ev(5);}
static void qmp_ufs_init_registers(struct qmp_ufs_priv*q,const struct qmp_ufs_cfg*c){ev(3);}
static int qmp_ufs_do_reset(struct qmp_ufs_priv*q){ev(11);return 0;}
#define readl_poll_timeout(a,v,c,t) ((void)(a),(void)(v),ev(7),fail_ready)
#define UCLASS_RESET 1
struct ufs_qcom_priv {struct reset_ctl core_reset;};
struct ufs_hba {struct udevice *dev;};
static void udelay(int d){ev(d);}
static int binds,bind_error;
static bool compatible=true,has_reset_cells=true;
static bool dev_read_bool(struct udevice*d,const char*p){return has_reset_cells;}
static bool device_is_compatible(struct udevice*d,const char*p){return compatible;}
static int dev_ofnode(struct udevice*d){return 42;}
static int device_bind_driver_to_node(struct udevice*p,const char*a,const char*b,int node,void*out){assert(p==(void*)0x9000);assert(node==42);binds++;return bind_error;}
'''
c+=''.join(f(phy,nm) for nm in ['qmp_ufs_power_on'])
c+=''.join(f(host,nm) for nm in ['ufs_qcom_phy_reset_request','ufs_qcom_phy_reset_set','ufs_qcom_bind','ufs_qcom_reset'])
c+=r'''
int main(void){
 struct qmp_ufs_cfg cfg={true,false,{0,1,2,3}};struct qmp_ufs_priv q={&cfg,(void*)0x2000};struct udevice d={&q,(void*)0x1000,(void*)0x9000};struct phy p={&d};
 int expected[]={1,2,3,4,5,6,7};assert(!qmp_ufs_power_on(&p));assert(n==7);for(int i=0;i<n;i++)assert(events[i]==expected[i]);
 n=0;fail_assert=-EIO;assert(qmp_ufs_power_on(&p)==-EIO);assert(n==2);fail_assert=0;
 n=0;fail_deassert=-EIO;assert(qmp_ufs_power_on(&p)==-EIO);assert(n==4);fail_deassert=0;
 n=0;fail_ready=-ETIMEDOUT;assert(qmp_ufs_power_on(&p)==-ETIMEDOUT);assert(n==7);fail_ready=0;
 n=0;cfg.host_phy_reset=false;assert(!qmp_ufs_power_on(&p));assert(n==5);assert(events[0]==1&&events[1]==3&&events[2]==5);
 cfg.no_pcs_sw_reset=true;n=0;assert(!qmp_ufs_power_on(&p));assert(events[2]==11);
 struct reset_ctl r={&d,0};assert(!ufs_qcom_phy_reset_request(&r));n=0;regval=0xa5a50000;assert(!ufs_qcom_phy_reset_set(&r,true));assert(regval==0xa5a50002);assert(n==4&&events[0]==8&&events[1]==9&&events[2]==8&&events[3]==10);
 n=0;assert(!ufs_qcom_phy_reset_set(&r,false));assert(regval==0xa5a50000);assert(n==4);
 r.id=1;n=0;assert(ufs_qcom_phy_reset_request(&r)==-EINVAL);assert(ufs_qcom_phy_reset_set(&r,true)==-EINVAL);assert(!n);
 r.id=0;d.base=0;n=0;assert(ufs_qcom_phy_reset_set(&r,true)==-EINVAL);assert(!n);d.base=(void*)0x1000;
 assert(!ufs_qcom_bind(&d));assert(binds==1);
 compatible=false;assert(!ufs_qcom_bind(&d));assert(binds==1);compatible=true;
 has_reset_cells=false;assert(!ufs_qcom_bind(&d));assert(binds==1);has_reset_cells=true;
 bind_error=-ENOMEM;assert(ufs_qcom_bind(&d)==-ENOMEM);assert(binds==2);
 struct ufs_qcom_priv priv={0};struct udevice controller={&priv};struct ufs_hba hba={&controller};
 n=0;fail_deassert=-EIO;assert(ufs_qcom_reset(&hba)==-EIO);assert(n==4);fail_deassert=0;
 n=0;fail_assert=-EBUSY;assert(ufs_qcom_reset(&hba)==-EBUSY);assert(n==1);fail_assert=0;
 n=0;assert(!ufs_qcom_reset(&hba));assert(n==4);

}
'''
(o/'host-reset-test.c').write_text(c)
subprocess.run(['cc','-std=gnu11','-Wall','-Wno-unused-function',str(o/'host-reset-test.c'),'-o',str(o/'host-reset-test')],check=True)
subprocess.run([str(o/'host-reset-test')],check=True)
# Probe must propagate failed/missing provider acquisition before hardware power-on.
x=(s/phy).read_text();assert re.search(r'if \(qmp->cfg->host_phy_reset\) \{\s*ret = reset_get_by_name\(dev, "ufsphy", &qmp->host_reset\);\s*if \(ret\)\s*return ret;',x)
print('PASS: actual calibration ordering, both reset failures, PCS timeout, unchanged legacy paths, RMW/readback/1ms edges, invalid ID and sibling binding; missing-provider propagation source check')
