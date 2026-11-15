#!/usr/bin/env python3
"""Host-compile per-LUN SCSI scan interruption and first UTP diagnostics.

Usage: TMPDIR=PROJECT_TMP python3 tests/uboot-scsi-interrupt.py PATCHED_UBOOT
"""
from pathlib import Path
import re, subprocess, tempfile, sys
source=Path(sys.argv[1]).resolve()
def function(path,name):
    x=(source/path).read_text();m=re.search(r'(?m)^(?:static )?[^\n]*\b'+name+r'\(',x);assert m,name
    a=m.start();b=x.index('{',a);depth=1;e=b+1
    while depth:depth+=(x[e]=='{')-(x[e]=='}');e+=1
    return x[a:e]+'\n'
boiler=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
typedef uint32_t u32;
struct scsi_plat {int max_id,max_lun;};struct udevice {struct scsi_plat *plat;};
struct ufs_hba {struct udevice *dev;bool transfer_error_logged;};
static int probes,interrupt_after=-1,probe_error,logs,reads;static bool compatible=true;
static int device_probe(struct udevice*d){return probe_error;}
static void *dev_get_uclass_plat(struct udevice*d){return d->plat;}
static int ctrlc(void){return interrupt_after>=0&&probes>=interrupt_after;}
static int do_scsi_scan_one(struct udevice*d,int id,int lun,bool verbose){probes++;return -ENODEV;}
static bool device_is_compatible(struct udevice*d,const char*s){return compatible;}
static u32 ufshcd_readl(struct ufs_hba*h,int reg){reads++;return 0;}
#define dev_err(d,...) (logs++,logger(__VA_ARGS__))
static void logger(const char*f,...){ }
'''
f=function('drivers/ufs/ufs-uclass.c','ufshcd_log_transfer_error_once')
header=(source/'drivers/ufs/ufshci.h').read_text();regs=sorted(set(re.findall(r'\bREG_[A-Z0-9_]+',f)));defines='\n'.join('#define '+n+' '+re.search(r'\b'+n+r'\s*=\s*([^,\n]+)',header)[1] for n in regs)
code=defines+'\n'+boiler+function('drivers/scsi/scsi.c','scsi_scan_dev')+f+r'''
int main(void){
 struct scsi_plat p={1,127};struct udevice d={&p};
 interrupt_after=0;assert(scsi_scan_dev(&d,true)==-EINTR);assert(!probes);
 interrupt_after=1;assert(scsi_scan_dev(&d,true)==-EINTR);assert(probes==1);
 probes=0;interrupt_after=6;assert(scsi_scan_dev(&d,true)==-EINTR);assert(probes==6);
 probes=0;interrupt_after=-1;assert(!scsi_scan_dev(&d,true));assert(probes==127);
 probes=0;probe_error=-EIO;assert(scsi_scan_dev(&d,true)==-EIO);assert(!probes);
 struct ufs_hba h={&d,false};ufshcd_log_transfer_error_once(&h,4);assert(logs==2&&reads==6&&h.transfer_error_logged);
 ufshcd_log_transfer_error_once(&h,0);assert(logs==2&&reads==6);
 h.transfer_error_logged=false;compatible=false;ufshcd_log_transfer_error_once(&h,4);assert(logs==2&&reads==6&&!h.transfer_error_logged);
}
'''
with tempfile.TemporaryDirectory(prefix='uboot-scsi-interrupt-') as tmp:
    p=Path(tmp);(p/'test.c').write_text(code);subprocess.run(['cc','-std=gnu11','-Wall',str(p/'test.c'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
print('PASS: actual scan loop stops before subsequent LUN inquiry, handles initial interruption/probe error, retains normal scan; first UTP diagnostics read/log only once on SM8750')
