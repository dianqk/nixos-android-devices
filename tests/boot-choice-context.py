#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile the real firmware importer/publisher with host EFI allocation stubs.
Requires UBOOT_SOURCE pointing at an existing prepared source (no source writes).
"""
import ctypes as C
import importlib.util
import os
from pathlib import Path
import struct as S
import subprocess
import tempfile
import unittest
import zlib
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('fixture',ROOT/'tests/early-fdt-guard.py')
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
PROP='android-devices,boot-choice-intent'
class Consumer(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  src=Path(os.environ['UBOOT_SOURCE']);cls.tmp=tempfile.TemporaryDirectory();w=Path(cls.tmp.name)
  (w/'asm').mkdir();(w/'linux').mkdir()
  (w/'efi_loader.h').write_text('''#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
typedef uint32_t u32; typedef uint8_t u8; typedef unsigned long efi_status_t;
typedef struct { unsigned char bytes[16]; } efi_guid_t;
#define EFI_GUID(...) {{0}}
#define EFI_SUCCESS 0
#define EFI_INVALID_PARAMETER 2
#define EFI_BOOT_SERVICES_DATA 4
unsigned long efi_allocate_pool(int,size_t,void **);
unsigned long efi_install_configuration_table(const efi_guid_t *,void *);
unsigned long efi_free_pool(void *);
''')
  (w/'asm/global_data.h').write_text('struct fake_gd { const void *fdt_blob; }; extern struct fake_gd *gd;\n#define DECLARE_GLOBAL_DATA_PTR\n')
  (w/'linux/libfdt.h').write_text('#include <libfdt.h>\n')
  (w/'stub.c').write_text('''#include <efi_loader.h>
#include <asm/global_data.h>
struct fake_gd data; struct fake_gd *gd=&data; void *published;
unsigned long efi_allocate_pool(int t,size_t s,void **p){*p=malloc(s);return !*p;}
unsigned long efi_install_configuration_table(const efi_guid_t *g,void *p){free(published);published=p;return 0;}
unsigned long efi_free_pool(void *p){free(p);return 0;}
void set_tree(const void *p){data.fdt_blob=p;}
void *get_record(void){return published;}
''')
  libfdt=src/'scripts/dtc/libfdt'
  cmd=['cc','-O2','-shared','-fPIC','-Wall','-Wextra','-Wno-unused-parameter',
       '-I'+str(w),'-I'+str(ROOT/'pkgs/boot-choice-context'),'-I'+str(ROOT/'tools/early-entry'),'-I'+str(libfdt),
       str(ROOT/'pkgs/boot-choice-context/firmware.c'),str(ROOT/'tools/early-entry/commit-intent.c'),str(w/'stub.c'),
       *[str(libfdt/(n+'.c')) for n in ['fdt','fdt_ro','fdt_rw','fdt_wip','fdt_check','fdt_sw','fdt_strerror','fdt_empty_tree']],'-o',str(w/'consumer.so')]
  # Public header is installed under this name by the Nix recipe.
  (w/'boot-choice-context.h').write_text((ROOT/'pkgs/boot-choice-context/context.h').read_text())
  (w/'boot-choice-context-wire.h').write_text((ROOT/'tools/boot-choice/context-wire.h').read_text())
  subprocess.run(cmd,check=True)
  cls.lib=C.CDLL(str(w/'consumer.so'));cls.lib.mobile_boot_choice_copy.argtypes=[C.c_void_p,C.c_void_p,C.c_size_t]
  cls.lib.set_tree.argtypes=[C.c_void_p];cls.lib.get_record.restype=C.c_void_p
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def token(self,stored=1,selected=0,seq=7):
  t=bytearray(80);t[:8]=b'BCINTENT';S.pack_into('<II',t,8,1,80);t[16:48]=bytes(range(32))
  S.pack_into('<QIIIII',t,48,seq,stored,selected,int(stored!=selected),1,1)
  return self.crc(t)
 def crc(self,t):
  t=bytearray(t);t[76:80]=bytes(4);S.pack_into('<I',t,76,zlib.crc32(t));return bytes(t)
 def check(self,t,ok=True,duplicate=False):
  props=[(PROP,t)] if t is not None else []
  if duplicate:props*=2
  source=C.create_string_buffer(bytes(f.fixture(extra=[('chosen',props,())])))
  dest=C.create_string_buffer(65536)
  self.assertEqual(self.lib.fdt_create_empty_tree(dest,65536),0)
  self.assertGreaterEqual(self.lib.fdt_add_subnode(dest,0,b'chosen'),0)
  before=dest.raw
  self.assertEqual(self.lib.mobile_boot_choice_copy(source,dest,65536)==0,ok)
  if not ok:self.assertEqual(dest.raw,before);return
  self.lib.set_tree(dest)
  self.assertEqual(self.lib.efi_boot_choice_context_register(),0)
  record=C.string_at(self.lib.get_record(),96)
  self.assertEqual(S.unpack_from('<IIII',record),(1,96,1,0));self.assertEqual(record[16:],t)
  # Imported bytes are independent of original source lifetime/mutations.
  C.memset(source,0,len(source));self.assertEqual(C.string_at(self.lib.get_record(),96),record)
 def test_good(self):
  for stored,selected,seq in [(1,1,7),(1,0,7),(0,1,7),(1,1,2**64-1)]:self.check(self.token(stored,selected,seq))
 def test_bad(self):
  self.check(None,False);self.check(self.token(),False,True)
  for at,value in [(8,2),(12,81),(48,0),(56,2),(60,2),(64,2),(68,0),(68,3),(72,0),(72,2)]:
   t=bytearray(self.token());S.pack_into('<I',t,at,value);self.check(self.crc(t),False)
  t=bytearray(self.token());t[16:48]=bytes(32);self.check(self.crc(t),False)
  for i in range(80):
   t=bytearray(self.token());t[i]^=1;self.check(t,False)
  for stored,selected in [(1,1),(1,0),(0,1)]:
   t=bytearray(self.token(stored,selected));S.pack_into('<I',t,64,int(stored==selected));self.check(self.crc(t),False)
 def test_duplicate_chosen(self):
  source=C.create_string_buffer(bytes(f.fixture(extra=[("chosen",[(PROP,self.token())],()),("chosen",[(PROP,self.token())],())])))
  dest=C.create_string_buffer(65536);self.assertEqual(self.lib.fdt_create_empty_tree(dest,65536),0)
  self.assertGreaterEqual(self.lib.fdt_add_subnode(dest,0,b"chosen"),0)
  self.assertNotEqual(self.lib.mobile_boot_choice_copy(source,dest,65536),0)
 def test_dispatch(self):
  env=(ROOT/'pkgs/u-boot/sm8750/dodge/dodge.env').read_text()
  line=next(s for s in env.splitlines() if s.startswith('boot_linux='))
  self.assertIn('/EFI/android-devices/boot-choice.efi',line)
  self.assertNotIn('BOOTAA64',line);self.assertNotIn('reset',line)
  self.assertIn('bootefi ${loadaddr}; run boot_choice_failure; exit',line)
  self.assertTrue(line.endswith('run boot_choice_failure'))
if __name__=='__main__':unittest.main()
