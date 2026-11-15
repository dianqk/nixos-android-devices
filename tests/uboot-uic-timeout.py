#!/usr/bin/env python3
"""Host-compile the UIC poller and verify accumulated timeout diagnostics.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-uic-timeout.py PATCHED_UBOOT
"""
from pathlib import Path
import re, subprocess, tempfile, sys
source = Path(sys.argv[1]).resolve()
x = (source / 'drivers/ufs/ufs-uclass.c').read_text()
a = x.index('static int ufshcd_send_uic_cmd(')
b = x.index('\n}', a) + 2
function = x[a:b]
registers = (source / 'drivers/ufs/ufshci.h').read_text()
reg_names = sorted(set(re.findall(r'\bREG_[A-Z0-9_]+', function)))
reg_defs = '\n'.join('#define '+name+' '+re.search(r'\b'+name+r'\s*=\s*([^,\n]+)', registers)[1] for name in reg_names)
boiler = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
typedef uint32_t u32;
#define UFS_UIC_CMD_TIMEOUT 5
#define COMMAND_OPCODE_MASK 0xff
#define UFSHCD_ERROR_MASK 0x100
#define UFSHCD_UIC_MASK 0x400
#define debug(...) ((void)0)
struct udevice {int unused;};
struct ufs_hba {struct udevice *dev; u32 intr_mask;};
struct uic_command {u32 command,argument1,argument2,argument3;};
static int reads, clears, time_calls, mode;static bool compatible=true,ready=true;
static char logtext[4096];
static void logger(void*d,const char*format,...){va_list args;va_start(args,format);vsnprintf(logtext+strlen(logtext),sizeof(logtext)-strlen(logtext),format,args);va_end(args);}
#define dev_err logger
static bool device_is_compatible(struct udevice*d,const char*s){return compatible;}
static bool ufshcd_ready_for_uic_cmd(struct ufs_hba*h){return ready;}
static unsigned long get_timer(unsigned long start){return time_calls++>1?6:0;}
static u32 ufshcd_readl(struct ufs_hba*h,int reg){
 if(reg==REG_INTERRUPT_STATUS){reads++;return mode==1?0x400:mode==2?0x100:reads==1?8:0;}
 if(reg==REG_CONTROLLER_STATUS)return 0x123;
 if(reg==REG_CONTROLLER_ENABLE)return 1;
 if(reg==REG_INTERRUPT_ENABLE)return h->intr_mask;
 return 0;
}
static void ufshcd_writel(struct ufs_hba*h,u32 val,int reg){if(reg==REG_INTERRUPT_STATUS)clears++;}
static u32 ufshcd_get_uic_cmd_result(struct ufs_hba*h){return 0;}
static u32 ufshcd_get_dme_attr_val(struct ufs_hba*h){return 0xabc;}
'''
main = r'''
static void reset(void){reads=clears=time_calls=0;logtext[0]=0;}
int main(void){
 struct udevice d={0};struct ufs_hba h={&d,0x500};struct uic_command cmd={0x16};
 assert(ufshcd_send_uic_cmd(&h,&cmd)==-ETIMEDOUT);assert(reads==2&&clears==2);
 assert(strstr(logtext,"HCS=0x123 HCE=0x1 IS=0 IE=0x500 observed_IS=0x8"));
 assert(strstr(logtext,"UIC errors PA=0 DL=0 N=0 T=0 DME=0"));
 reset();compatible=false;assert(ufshcd_send_uic_cmd(&h,&cmd)==-ETIMEDOUT);assert(!strstr(logtext,"observed_IS"));
 reset();compatible=true;mode=1;assert(!ufshcd_send_uic_cmd(&h,&cmd));assert(reads==1&&clears==1&&cmd.argument3==0xabc);
 reset();mode=2;assert(ufshcd_send_uic_cmd(&h,&cmd)==-1);assert(reads==1&&clears==1);
 reset();ready=false;assert(ufshcd_send_uic_cmd(&h,&cmd)==-EIO);assert(!reads&&!clears);
}
'''
with tempfile.TemporaryDirectory(prefix='uboot-uic-timeout-') as tmp:
    p=Path(tmp);(p/'test.c').write_text(reg_defs+'\n'+boiler+'\n'+function+'\n'+main)
    subprocess.run(['cc','-std=gnu11','-Wall',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
print('PASS: actual UIC poller retains early cleared IS bits at timeout, bounds polling, preserves successful/error/not-ready and generic-board paths')
