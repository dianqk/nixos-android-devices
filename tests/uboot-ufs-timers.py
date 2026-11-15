#!/usr/bin/env python3
"""Host-compile UFS core-clock selection and pre-link timer programming.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-ufs-timers.py PATCHED_UBOOT
"""
from pathlib import Path
import re,subprocess,tempfile,sys
s=Path(sys.argv[1]).resolve()
workspace=tempfile.TemporaryDirectory(prefix='uboot-ufs-timers-')
o=Path(workspace.name)
def f(name):
 x=(s/'drivers/ufs/ufs-qcom.c').read_text();m=re.search(r'(?m)^static [^\n]*\b'+name+r'\(',x);assert m,name;a=m.start();b=x.index('{',a);d=1;e=b+1
 while d:d+=(x[e]=='{')-(x[e]=='}');e+=1
 return x[a:e]+'\n'
c=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <string.h>
typedef uint32_t u32;typedef unsigned long ulong;
#define REG_UFS_SYS1CLK_1US 0xc0
#define REG_UFS_CFG1 0xdc
#define dev_info(...) ((void)0)
#define dev_err(...) ((void)0)
#define UFS_UNIPRO_VER_1_41 0x141
#define UIC_ARG_MIB(x) (x)
#define PA_LOCAL_TX_LCC_ENABLE 0x155e
struct udevice {void *priv;};
struct ufs_hba {struct udevice *dev;};
struct ufs_qcom_priv {ulong core_clk_rate;};
struct clk {int id;};
enum ufs_notify_change_status {PRE_CHANGE,POST_CHANGE};
static int events[32],n,core_error,clk_get_error;static long selected=100000000;static bool compatible=true;
static u32 timer;
static void ev(int e){events[n++]=e;}
static void *dev_get_priv(struct udevice*d){return d->priv;}
static bool device_is_compatible(struct udevice*d,const char*p){return compatible;}
static void ufshcd_writel(struct ufs_hba*h,u32 v,int r){assert(r==0xc0);timer=v;ev(1);}
static u32 ufshcd_readl(struct ufs_hba*h,int r){assert(r==0xc0);ev(2);return timer;}
static int ufs_qcom_set_core_clk_ctrl(struct ufs_hba*h){ev(3);return core_error;}
static int ufs_qcom_get_local_unipro_ver(struct ufs_hba*h){return 0x180;}
static int ufshcd_dme_set(struct ufs_hba*h,int a,u32 v){assert(a==0x155e&&v==0);ev(4);return 0;}
static int clk_get_by_name(struct udevice*d,const char*name,struct clk*c){assert(!strcmp(name,"core_clk"));ev(5);return clk_get_error;}
static ulong ufs_qcom_get_clk_max_freq(struct ufs_hba*h,const char*name){assert(!strcmp(name,"core_clk"));return 100000000;}
static ulong clk_set_rate(struct clk*c,ulong r){assert(r==100000000);ev(6);return selected;}
'''
c+=''.join(f(n) for n in ['ufs_qcom_cfg_sys1clk','ufs_qcom_link_startup_notify','ufs_qcom_set_host_clk'])
c+=r'''
int main(void){
 struct ufs_qcom_priv priv={0};struct udevice d={&priv};struct ufs_hba h={&d};
 assert(!ufs_qcom_set_host_clk(&h));assert(priv.core_clk_rate==100000000);assert(n==2&&events[0]==5&&events[1]==6);
 n=0;assert(!ufs_qcom_link_startup_notify(&h,PRE_CHANGE));assert(timer==100);assert(n==4);for(int i=0;i<4;i++)assert(events[i]==i+1);
 n=0;selected=75000000;assert(!ufs_qcom_set_host_clk(&h));assert(priv.core_clk_rate==75000000);assert(!ufs_qcom_cfg_sys1clk(&h));assert(timer==75);selected=100000000;assert(!ufs_qcom_set_host_clk(&h));
 n=0;core_error=-EIO;assert(ufs_qcom_link_startup_notify(&h,PRE_CHANGE)==-EIO);assert(n==3);core_error=0;
 n=0;priv.core_clk_rate=0;assert(ufs_qcom_link_startup_notify(&h,PRE_CHANGE)==-EINVAL);assert(n==0);
 priv.core_clk_rate=100000001;assert(ufs_qcom_cfg_sys1clk(&h)==-EINVAL);assert(n==0);
 selected=-ERANGE;assert(ufs_qcom_set_host_clk(&h)==-ERANGE);selected=0;assert(ufs_qcom_set_host_clk(&h)==-EINVAL);selected=999999;assert(ufs_qcom_set_host_clk(&h)==-EINVAL);selected=100000001;assert(ufs_qcom_set_host_clk(&h)==-EINVAL);
 clk_get_error=-ENOENT;n=0;assert(ufs_qcom_set_host_clk(&h)==-ENOENT);assert(n==1);clk_get_error=0;
 n=0;compatible=false;assert(!ufs_qcom_set_host_clk(&h));assert(!n);assert(!ufs_qcom_link_startup_notify(&h,PRE_CHANGE));assert(n==2&&events[0]==3&&events[1]==4);
 n=0;compatible=true;assert(!ufs_qcom_link_startup_notify(&h,POST_CHANGE));assert(!n);
}
'''
(o/'timer-test.c').write_text(c)
subprocess.run(['cc','-std=gnu11','-Wall','-Wno-unused-variable','-Wno-unused-but-set-variable',str(o/'timer-test.c'),'-o',str(o/'timer-test')],check=True);subprocess.run([str(o/'timer-test')],check=True)
print('PASS: actual core clock selection, returned rate/lookup errors, 100-cycle timer/readback before DME, DME failure preserved, invalid rates rejected, generic-board and POST_CHANGE behavior preserved')
