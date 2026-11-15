#!/usr/bin/env python3
"""Compile actual DWC3/ACM shutdown functions against bounded MMIO fixtures."""
from pathlib import Path
import re, subprocess, sys, tempfile
source = Path(sys.argv[1]).resolve()
def function(path, name):
    text = (source / path).read_text()
    matches = list(re.finditer(r'(?m)^static [^\n]*\b' + name + r'\([^;]*?\)\n\{', text))
    assert len(matches) == 1, name
    start = matches[0].start(); end = text.index('{', start); depth = 1; end += 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}'); end += 1
    return text[start:end] + '\n'
header = (source / 'drivers/usb/dwc3/core.h').read_text()
names = ['DWC3_DCTL','DWC3_DSTS','DWC3_DCTL_RUN_STOP','DWC3_DCTL_KEEP_CONNECT',
         'DWC3_DCTL_TRGTULST_MASK','DWC3_DCTL_TRGTULST_RX_DET','DWC3_DSTS_DEVCTRLHLT',
         'DWC3_GEVNTCOUNT_MASK','DWC3_GEVNTSIZ_INTMASK','DWC3_ENDPOINTS_NUM',
         'DWC3_DEPCMD_ENDTRANSFER','DWC3_DEPCMD_HIPRI_FORCERM','DWC3_DEPCMD_CMDIOC',
         'DWC3_EP_BUSY','DWC3_DEPCMD_PARAM_SHIFT','DWC3_REVISION_187A','DWC3_REVISION_194A',
         'DWC3_EVENT_SIZE','DWC3_EVENT_MAX_NUM','DWC3_EVENT_BUFFERS_SIZE']
macros = []
for n in names:
    m = re.search(r'^#define\s+' + n + r'\s+(.+)$', header, re.M); assert m,n
    macros.append('#define ' + n + ' ' + m[1])
for n in ['DWC3_GEVNTCOUNT','DWC3_GEVNTSIZ','DWC3_DEPCMD_PARAM','DWC3_DCTL_TRGTULST','DWC3_NUM_INT']:
    m=re.search(r'^#define\s+'+n+r'(\([^\n]+)$',header,re.M);assert m,n
    macros.append('#define '+n+m[1])
c=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <errno.h>
#include <string.h>
typedef uint32_t u32;
#define IS_ENABLED(x) (x)
#define BIT(x) (1U<<(x))
#define dev_vdbg(...) ((void)0)
#define WARN_ON_ONCE(x) ((void)(x))
#define spin_lock_irqsave(lock,flags) ((void)(flags))
#define spin_unlock_irqrestore(lock,flags) ((void)(flags))
#define DWC3_EVENT_PENDING 1U
'''+ '\n'.join(macros)+r'''
struct dwc3_event_buffer { unsigned length,lpos,count,flags; };
struct dwc3_ep { unsigned resource_index,flags,number; };
struct usb_gadget { void *owner; };
struct dwc3 { void *regs,*dev; int lock,num_event_buffers,revision; bool has_hibernation,pullups_connected;
 void *gadget_driver; struct dwc3_event_buffer **ev_buffs; struct dwc3_ep *eps[DWC3_ENDPOINTS_NUM]; struct usb_gadget gadget; };
struct dwc3_gadget_ep_cmd_params { u32 param0,param1,param2; };
static u32 regs[0x10000/4];
static unsigned dstatus_reads,delays,ends,acks,trace[64],nt,queue,push;
static bool auto_halt=true;static int command_error;
static void event(unsigned n){if(nt<64)trace[nt++]=n;}
static void udelay(unsigned n){delays+=n;}
static u32 dwc3_readl(void *unused,u32 off){
 if(off==DWC3_DSTS){dstatus_reads++; if(regs[DWC3_DCTL/4]&DWC3_DCTL_RUN_STOP)return 0;
  if(auto_halt && !regs[DWC3_GEVNTCOUNT(0)/4] && !regs[DWC3_GEVNTCOUNT(1)/4])return DWC3_DSTS_DEVCTRLHLT;
  return 0;}
 return regs[off/4];}
static void dwc3_writel(void *unused,u32 off,u32 v){
 if(off==DWC3_GEVNTCOUNT(0)||off==DWC3_GEVNTCOUNT(1)){
  assert(v<=regs[off/4]);regs[off/4]-=v;acks++;event(3);
 }else regs[off/4]=v;}
static void dwc3_gadget_dctl_write_safe(struct dwc3*d,u32 v){event(2);regs[DWC3_DCTL/4]=v;}
static int dwc3_send_gadget_ep_cmd(struct dwc3*d,unsigned ep,u32 cmd,struct dwc3_gadget_ep_cmd_params*p){
 assert(ep>=2 && ep<DWC3_ENDPOINTS_NUM);assert(!(cmd&0xf)||((cmd&0xf)==DWC3_DEPCMD_ENDTRANSFER));ends++;event(1);return command_error;}
static struct dwc3 *gadget_to_dwc(struct usb_gadget*g){return g->owner;}
'''
path='drivers/usb/dwc3/gadget.c'
for name in ['dwc3_stop_active_transfer','dwc3_gadget_discard_events','dwc3_gadget_run_stop','dwc3_gadget_end_transfers','dwc3_gadget_pullup']:
    c+=function(path,name)
c+=r'''
struct usb_ep {int unused;};
struct f_acm {int rx_buf;};
struct usb_request {void *context,*buf; unsigned actual; int status;};
static void buf_push(int*b,void*d,unsigned n){push++;}
static int usb_ep_queue(struct usb_ep*e,struct usb_request*r,int flags){queue++;return 0;}
'''+function('drivers/usb/gadget/f_acm.c','acm_rx_complete')+r'''
int main(void){
 struct dwc3_event_buffer a={16,12,8,5},b={16,4,4,1};
 struct dwc3_event_buffer *buffers[]={&a,&b};struct dwc3_ep ep={1,DWC3_EP_BUSY,2};
 struct dwc3 d={.regs=regs,.num_event_buffers=2,.revision=DWC3_REVISION_194A,.ev_buffs=buffers};
 d.gadget.owner=&d;d.eps[2]=&ep;regs[DWC3_DCTL/4]=DWC3_DCTL_RUN_STOP|0x400;
 regs[DWC3_GEVNTCOUNT(0)/4]=8;regs[DWC3_GEVNTCOUNT(1)/4]=4;
 regs[DWC3_GEVNTSIZ(0)/4]=DWC3_GEVNTSIZ_INTMASK|16;regs[DWC3_GEVNTSIZ(1)/4]=DWC3_GEVNTSIZ_INTMASK|16;
 if(CONFIG_QCOM_DODGE){
  assert(!dwc3_gadget_pullup(&d.gadget,0));assert(ends==1&&acks==2);assert(trace[0]==1&&trace[1]==2&&trace[2]==3);
  assert(a.lpos==4&&b.lpos==8&&!a.count&&!b.count&&a.flags==4&&!b.flags);
  assert(regs[DWC3_GEVNTSIZ(0)/4]==16&&regs[DWC3_GEVNTSIZ(1)/4]==16);
  assert(!(regs[DWC3_DCTL/4]&DWC3_DCTL_RUN_STOP));
  // Reconnect does not consume/advance a fresh event, or rerun ENDTRANSFER.
  regs[DWC3_GEVNTCOUNT(0)/4]=4;unsigned oldends=ends,oldacks=acks,oldpos=a.lpos;
  assert(!dwc3_gadget_pullup(&d.gadget,1));assert(ends==oldends&&acks==oldacks&&a.lpos==oldpos);
  assert(regs[DWC3_DCTL/4]&DWC3_DCTL_RUN_STOP);
  // Invalid counts/state must not acknowledge arbitrary bytes; failure propagates.
  regs[DWC3_GEVNTCOUNT(0)/4]=20;assert(dwc3_gadget_pullup(&d.gadget,0)==-EINVAL);assert(acks==oldacks);
  regs[DWC3_GEVNTCOUNT(0)/4]=3;assert(dwc3_gadget_pullup(&d.gadget,0)==-EINVAL);assert(acks==oldacks);
  // A valid first ring may be drained before an invalid second is rejected.
  regs[DWC3_GEVNTCOUNT(0)/4]=4;regs[DWC3_GEVNTCOUNT(1)/4]=20;
  oldacks=acks;assert(dwc3_gadget_pullup(&d.gadget,0)==-EINVAL);
  assert(acks==oldacks+1&&regs[DWC3_GEVNTCOUNT(1)/4]==20);
  regs[DWC3_GEVNTCOUNT(1)/4]=0;
  regs[DWC3_GEVNTCOUNT(0)/4]=0;a.length=0;assert(dwc3_gadget_discard_events(&d)==-EINVAL);a.length=16;
  a.lpos=16;assert(dwc3_gadget_discard_events(&d)==-EINVAL);a.lpos=0;
  a.count=3;assert(dwc3_gadget_discard_events(&d)==-EINVAL);a.count=0;
  a.length=DWC3_EVENT_BUFFERS_SIZE+4;assert(dwc3_gadget_discard_events(&d)==-EINVAL);a.length=16;
  buffers[0]=NULL;assert(dwc3_gadget_discard_events(&d)==-EINVAL);buffers[0]=&a;
  d.num_event_buffers=0;assert(dwc3_gadget_discard_events(&d)==-EINVAL);d.num_event_buffers=2;
  auto_halt=false;dstatus_reads=delays=0;assert(dwc3_gadget_pullup(&d.gadget,0)==-ETIMEDOUT);
  assert(dstatus_reads==2000&&delays==4000000);
  // ENDTRANSFER failure clears legacy bookkeeping, but cannot fake HALT.
  command_error=-ETIMEDOUT;ep.resource_index=1;dstatus_reads=0;
  assert(dwc3_gadget_pullup(&d.gadget,0)==-ETIMEDOUT);
  assert(!ep.resource_index&&dstatus_reads==2000);
 }else{
  // Existing non-Dodge stop neither ends transfers nor discards events.
  assert(dwc3_gadget_pullup(&d.gadget,0)==-ETIMEDOUT);assert(!ends&&!acks&&a.lpos==12&&a.count==8);
  assert(!dwc3_gadget_pullup(&d.gadget,1));assert(!ends&&!acks);
 }
 struct f_acm acm={0};struct usb_ep out={0};struct usb_request req={.context=&acm,.actual=8};
 req.status=-ESHUTDOWN;acm_rx_complete(&out,&req);req.status=-ECONNRESET;acm_rx_complete(&out,&req);
 if(CONFIG_QCOM_DODGE)assert(!queue&&!push);else assert(queue==2&&push==2);
 queue=push=0;req.status=0;req.actual=8;acm_rx_complete(&out,&req);assert(queue==1&&push==1&&!req.actual);
}
'''
with tempfile.TemporaryDirectory(prefix='uboot-dwc3-shutdown-') as temp:
    p=Path(temp);(p/'test.c').write_text(c)
    for dodge in [0,1]:
        subprocess.run(['cc','-std=gnu11','-Wall','-Wno-unused-function',f'-DCONFIG_QCOM_DODGE={dodge}',str(p/'test.c'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True)
print('PASS actual C: ENDTRANSFER before RUN_STOP; bounded two-ring drain/wrap/pending/mask; reconnect; malformed counts/state and timeout failure; cancelled ACM RX never resubmits; success RX and non-Dodge/connect unchanged')
