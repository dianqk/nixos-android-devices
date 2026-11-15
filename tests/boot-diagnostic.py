#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host raster/hold unit for opt-in diagnostic; no MMIO/device access."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=r'''
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "adapters/dodge/policy.c"
static volatile unsigned calls;
static unsigned slow,frozen,failed;
int eg_clock_read(uint64_t *hz,uint64_t *ticks){
 calls++;*hz=slow?19200000:1000;*ticks=frozen?7:slow?calls:1000*calls;return !failed;
}
int main(void){
 size_t size=640*480*4;unsigned char *p=malloc(size+128);assert(p);
 memset(p,0x5a,size+128);
 struct eg_framebuffer f={.base=(uintptr_t)(p+64),.size=size,.width=640,.height=480,.stride=2560,.rgb32=1};
 for(unsigned code=0;code<=5;code++){
  memset(p+64,0x5a,size);calls=0;diagnostic(&f,code,1);
#ifdef DODGE_DIAGNOSTIC_STAGES
  assert(calls==4);unsigned changed=0;
  for(unsigned i=0;i<size;i++)changed+=p[64+i]!=0x5a;
  assert(changed && changed<432*66*4+1);
#else
  assert(!calls);for(unsigned i=0;i<size;i++)assert(p[64+i]==0x5a);
#endif
  for(unsigned i=0;i<64;i++)assert(p[i]==0x5a && p[size+64+i]==0x5a);
 }
 /* Detail line must stay bounded, be read-only, and never paint by default. */
 memset(p+64,0x5a,size);calls=0;
 struct eg_bootconfig_report report={.error=EG_BC_CHECKSUM,.offset=0xFEDCBA9876543210ULL,.byte=0xAB};
 diagnostic_bootconfig(&f,&report);
#ifdef DODGE_DIAGNOSTIC_STAGES
 unsigned detail=0;for(unsigned i=0;i<size;i++)detail+=p[64+i]!=0x5a;
 assert(detail && detail<=528*36*4);
#else
 for(unsigned i=0;i<size;i++)assert(p[64+i]==0x5a);
#endif
 assert(!calls);for(unsigned i=0;i<64;i++)assert(p[i]==0x5a && p[size+64+i]==0x5a);
 /* Smallest admitted framebuffer also accommodates all telemetry. */
 f.width=392;f.height=248;f.stride=392*4;
 diagnostic_bootconfig(&f,&report);f.width=640;f.height=480;f.stride=2560;
#ifdef DODGE_DIAGNOSTIC_STAGES
#ifdef ACCELERATED_FROZEN
 frozen=1;calls=0;diagnostic(&f,2,1);assert(calls==33);
 failed=1;calls=0;diagnostic(&f,2,1);assert(calls==1);
#else
 /* One tick per poll at a real 19.2MHz rate: old1M budget would stop
  * before target; production1B budget must reach3s first. */
 slow=1;calls=0;diagnostic(&f,2,1);assert(calls==57600001);
#endif
#endif
 f.base=0;calls=0;diagnostic(&f,2,1);assert(!calls);
 free(p);return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
 w=Path(tmp);(w/'test.c').write_text(source)
 for flags in [[],['-DDODGE_DIAGNOSTIC_STAGES'],['-DDODGE_DIAGNOSTIC_STAGES','-DACCELERATED_FROZEN']]:
  text=source
  if '-DACCELERATED_FROZEN' in flags:
   policy=(root/'tools/early-entry/adapters/dodge/policy.c').read_text()
   assert policy.count('i<1000000000;')==1 and policy.count('i<100000000;')==1
   # Test-only copy with smaller constant budgets, exact same loop/control flow.
   (w/'policy.c').write_text(policy.replace('i<1000000000;','i<32;').replace('i<100000000;','i<32;'))
   text=text.replace('adapters/dodge/policy.c','policy.c')
  (w/'test.c').write_text(text)
  subprocess.run(['cc','-O2','-ffunction-sections','-fdata-sections','-Wl,--gc-sections',*flags,'-I'+str(root/'tools/early-entry'),'-I'+str(root/'tools/early-entry/adapters/dodge'),str(w/'test.c'),str(root/'tools/early-entry/draw.c'),'-o',str(w/'test')],check=True)
  subprocess.run([str(w/'test')],check=True,timeout=20)
print('PASS opt-in diagnostic codes0..5 bounded center raster/canaries/19.2MHz slow-progress reaches3s before cap, accelerated finite frozen/failure cases; default no paint/clock and invalid framebuffer refuses')
