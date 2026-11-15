#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Actual compiler-free CLI + explicit exported template, no block devices.
NATIVE_CLI, BOOT_TEMPLATE and BOOT_BASELINE are required input paths. An optional
BOOT_OLD_OWNED exercises migration from a prior prelinked owned generation.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('experiment',ROOT/'tools/boot-image-experiment.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
cli=Path(os.environ['NATIVE_CLI']);template=Path(os.environ['BOOT_TEMPLATE']);baseline=Path(os.environ['BOOT_BASELINE'])
original=e.c.read_regular(baseline,e.c.LIMIT);digest=hashlib.sha256(original).hexdigest()
def call(*args,ok=True):
 p=subprocess.run([str(cli),*map(str,args)],capture_output=True,timeout=60)
 assert (p.returncode==0)==ok,(args,p.stdout,p.stderr)
 return p.stdout.decode()
with tempfile.TemporaryDirectory() as temp:
 d=Path(temp);info=e.c.boot4(original);stored=info['kernel']['stored_bytes']+4096
 assert stored<=48*1024*1024
 body=bytearray(e.c.align(4096+stored));body[:4096+info['kernel']['stored_bytes']]=original[:4096+info['kernel']['stored_bytes']]
 struct.pack_into('<I',body,8,stored);struct.pack_into('<I',body,16,info['os_version_raw']^1)
 body[44:67]=b'bootchoice.synthetic=1\0'
 struct.pack_into('<Q',body,4096+16,max(info['kernel']['image_size'],e.c.align(stored)))
 target=info['kernel']['branch_target']+4;body[4100:4104]=e.branch(4,target)
 body[4096+info['kernel']['stored_bytes']:4096+stored]=bytes((i%251)+1 for i in range(4096))
 changed=e.seal(body,len(original)+8192);e.c.boot4(changed);(d/'changed-baseline').write_bytes(changed)
 for name,source in [('current',baseline),('changed',d/'changed-baseline')]:
  call('image','embed',template,source,d/(name+'.img'))
  call('image','restore',d/(name+'.img'),d/(name+'.restored'))
  assert (d/(name+'.restored')).read_bytes()==source.read_bytes()
  report=call('owned-inspect',d/(name+'.img'));assert 'sequence=1 mode=1' in report
  call('image','update',template,d/(name+'.img'),d/(name+'.noop'))
  assert (d/(name+'.noop')).read_bytes()==(d/(name+'.img')).read_bytes()
  # Explicit existing/symlink/FIFO refusals: no accidental device/file mutation.
  before=(d/(name+'.img')).read_bytes();call('image','embed',template,source,d/(name+'.img'),ok=False)
  assert (d/(name+'.img')).read_bytes()==before
  call('image','embed',template,d/(name+'.img'),d/(name+'.nested'),ok=False)
 (d/'source-link').symlink_to(baseline);call('image','embed',template,d/'source-link',d/'bad-link',ok=False)
 os.mkfifo(d/'source-fifo');call('image','embed',template,d/'source-fifo',d/'bad-fifo',ok=False)
 for offset in [12,40,1580,1584,4096+24,4096+56]:
  bad=bytearray(original);bad[offset]^=1;(d/'bad').write_bytes(bad);call('image','embed',template,d/'bad',d/'bad-output',ok=False)
 old=os.environ.get('BOOT_OLD_OWNED')
 if old:
  report=call('owned-inspect',old);seq=int(report.split('sequence=')[1].split()[0]);mode=int(report.split('mode=')[1].split()[0])
  call('image','update',template,old,d/'migrated');new=call('owned-inspect',d/'migrated')
  assert f'sequence={seq+1} mode={mode}' in new
  call('image','restore',d/'migrated',d/'migrated-original');assert (d/'migrated-original').read_bytes()==original
 output=os.environ.get('BOOT_TEST_OUTPUT')
 if output:
  out=Path(output);out.mkdir(mode=0o700)
  for name,data in [('changed-baseline.img',changed),('changed-embedded.img',(d/'changed.img').read_bytes())]:e.c.write_new(out/name,data)
 assert hashlib.sha256(baseline.read_bytes()).hexdigest()==digest
 print('PASS actual baseline and changed size/header/kernel/entry/AVB: exact restore, no-op, non-nesting, filesystem/input faults and optional prior-owned migration')
