#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile extracted production macros/callbacks against a byte-addressed model.

Usage: python3 tests/mt6363-registers.py /path/to/linux

Extracts the production descriptors, regmap configuration, disable callback,
BUCK key helper and complete VEMC set-voltage callback. Stubbed regmap operations
model byte-addressed transfers, not electrical SET/CLR behavior or the regmap
implementation. The VEMC cases check key transfers on its two successful trap
paths, not voltage selection semantics. No hardware access is performed.
Dedicated VSRAM physical addresses follow the MT6363 vendor register contract;
the driver addresses subtract its existing 0x30 base. This is a host-only test.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='Linux source tree containing the production driver')
parser.add_argument('--output-dir', type=Path, help='retain generated C and executable in this directory')
args = parser.parse_args()
kernel = args.source
source = kernel / 'drivers/regulator/mt6363-regulator.c'
header = (kernel / 'include/linux/regulator/mt6363-regulator.h').read_text()
header = re.sub(r'^#include.*$', '', header, flags=re.M)

def function(text, name):
    start = re.search(r'^static .*\b' + name + r'\(', text, re.M).start()
    end = text.index('\n}', start) + 2
    return text[start:end]

prefix = r'''
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
typedef uint16_t u16;
typedef uint16_t __le16;
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define cpu_to_le16(x) ((uint16_t)(x))
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define cpu_to_le16(x) __builtin_bswap16((uint16_t)(x))
#else
#error Unsupported byte order
#endif
#define FIELD_PREP(mask, value) ((value) << (__builtin_ffs(mask) - 1))
struct linear_range { unsigned min_sel, max_sel; };
static unsigned linear_range_values_in_range(const struct linear_range *r) {
 return r->max_sel - r->min_sel + 1;
}
#define BIT(x) (1U << (x))
#define GENMASK(h,l) (((~0U) >> (31-(h))) & ((~0U) << (l)))
#define of_match_ptr(x) (x)
#define THIS_MODULE 0
#define REGULATOR_VOLTAGE 0
struct regmap_config { int reg_bits, val_bits, max_register; bool fast_io; };
struct regulator_desc {
 const char *name, *supply_name, *of_match; const int *ops;
 int type,id,owner,n_voltages,min_uV,uV_step;
 int n_linear_ranges;
 unsigned vsel_range_mask, vsel_range_reg;
 const struct linear_range *linear_ranges;
 const unsigned *linear_range_selectors_bitfield;
 unsigned enable_reg,enable_mask,vsel_reg,vsel_mask; int of_map_mode;
};
struct mt6363_regulator_info {
 struct regulator_desc desc;
 unsigned lp_mode_reg,lp_mode_mask,hw_lp_mode_reg,hw_lp_mode_mask;
 unsigned modeset_reg,modeset_mask,lp_imax_uA,op_en_reg,hwirq;
};
static int mt6363_vreg_setclr_ops,mt6363_ldo_linear_ops;
#define mt6363_map_mode 0
struct regmap { unsigned char bytes[0x2000]; };
struct regulator_dev { struct regmap *regmap; const struct regulator_desc *desc; };
static unsigned bulk_bytes, key_count, key_lengths[4];
static unsigned char key_bytes[4][2];
static unsigned trap;
static int regmap_read(struct regmap *map, unsigned reg, unsigned *val) {
 (void)map; (void)reg; *val = trap; return 0;
}
static int regmap_update_bits(struct regmap *map, unsigned reg, unsigned mask, unsigned val) {
 (void)map; (void)reg; (void)mask; (void)val; return 0;
}
static int regmap_bulk_write(struct regmap *map, unsigned reg, const void *p, unsigned n);
static int regmap_write(struct regmap *map, unsigned reg, unsigned val);
'''

def generate(text):
    enum = re.search(r'enum \{.*?\n\};', text, re.S).group()
    macros = text[text.index('#define MT6363_BUCK('):text.index('#define MT6363_LDO_LINEAR_CAL_OPS(')]
    entries = re.findall(r'\tMT6363_(?:BUCK|LDO_L|LDO_L_SC)\(.*?\),', text, re.S)
    config = re.search(r'struct regmap_config mt6363_regmap_config = \{.*?\n\t\};',text,re.S).group()
    defs = '\n'.join(re.findall(r'^#define (?:EN_CLR_OFFSET|(?:MT6363_BUCK_TOP_UNLOCK_VALUE|MT6363_TMA_UNLOCK_VALUE))\s+.*',text,re.M))
    code = prefix + header + enum + '\n' + macros + defs + '\n' + config
    code += '\nstatic struct mt6363_regulator_info rails[] = {\n' + '\n'.join(entries) + '\n};\n'
    code += r'''
static int regmap_write(struct regmap *map, unsigned reg, unsigned val) {
 unsigned width = mt6363_regmap_config.val_bits / 8;
 for (unsigned i=0;i<width;i++) map->bytes[reg+0x30+i] = val >> (8*i);
 return 0;
}
static int regmap_bulk_write(struct regmap *map, unsigned reg, const void *p, unsigned n) {
 if (key_count >= 4) return -1;
 bulk_bytes = n * mt6363_regmap_config.val_bits / 8;
 key_lengths[key_count] = bulk_bytes;
 /* Refuse an over-read of the production helper's two-byte stack key. */
 if (bulk_bytes > 2) return -1;
 memcpy(key_bytes[key_count++], p, bulk_bytes);
 memcpy(map->bytes + reg + 0x30, p, bulk_bytes); return 0;
}
'''
    code += function(text, 'mt6363_vreg_disable_setclr') + '\n' + function(text, 'mt6363_buck_unlock') + '\n' + function(text, 'mt6363_vemc_set_voltage_sel')
    tests = r'''
static int failures, checks;
#define CHECK(c,label) do { checks++; if (!(c)) { failures++; puts("FAIL " label); } } while(0)
int main(void) {
 struct regmap map; memset(&map,0xa5,sizeof(map));
 struct regulator_dev dev = { .regmap=&map, .desc=&rails[MT6363_ID_VS2].desc };
 mt6363_vreg_disable_setclr(&dev);
 CHECK(map.bytes[0x243]==0xa5,"VS2 CLR preserves BUCK1 enable byte");
 CHECK(mt6363_buck_unlock(&map,true)==0,"BUCK key consumes only two bytes");
 CHECK(bulk_bytes==2,"BUCK key transfer length");
 CHECK(map.bytes[MT6363_BUCK_TOP_KEY_PROT_LO+0x30]==0x43 &&
       map.bytes[MT6363_BUCK_TOP_KEY_PROT_LO+0x31]==0x55,"BUCK unlock bytes 43 55");
 CHECK(mt6363_buck_unlock(&map,false)==0,"BUCK relock consumes only two bytes");
 CHECK(map.bytes[MT6363_BUCK_TOP_KEY_PROT_LO+0x30]==0 &&
       map.bytes[MT6363_BUCK_TOP_KEY_PROT_LO+0x31]==0,"BUCK relock bytes 00 00");
'''
    # MT6363 vendor register definitions, MiCode/MTK_kernel_device_modules
    # revision 3c4ccd07d5624879555ec710c11bb8818e5cb5c6.
    for rail, addr in [('CPUB',0x1e07),('CPUM',0x1e1d),('CPUL',0x1e87),('APU',0x1e9d)]:
        for field,expected in [('desc.enable_reg',addr-0x30),('lp_mode_reg',addr-0x30),('desc.enable_mask',1),('lp_mode_mask',2)]:
            tests += f' CHECK(rails[MT6363_ID_VSRAM_{rail}].{field}=={expected},"{rail} {field} register contract");\n'
    for rail in ['DIGRF','MDFE','MODEM']:
        tests += f' CHECK(rails[MT6363_ID_VSRAM_{rail}].desc.enable_reg==0x213 && rails[MT6363_ID_VSRAM_{rail}].lp_mode_reg==0x219,"{rail} shared BUCK1 retained");\n'
    tests += r'''
 struct linear_range linear = { .min_sel=0, .max_sel=1 };
 unsigned selector = 0;
 struct regulator_desc vemc = { .n_linear_ranges=1, .linear_ranges=&linear,
  .linear_range_selectors_bitfield=&selector, .vsel_mask=1, .vsel_range_mask=1 };
 dev.desc = &vemc;
 for (trap=0; trap<2; trap++) {
  key_count=0;
  CHECK(mt6363_vemc_set_voltage_sel(&dev,0)==0,"TMA callback succeeds");
  CHECK(key_count==2,"TMA unlock and relock transferred");
  CHECK(key_lengths[0]==2 && key_lengths[1]==2,"TMA key transfer lengths");
  CHECK(key_bytes[0][0]==0x9c && key_bytes[0][1]==0x9c,"TMA unlock bytes 9c 9c");
  CHECK(key_bytes[1][0]==0 && key_bytes[1][1]==0,"TMA relock bytes 00 00");
 }
'''
    tests += 'printf("%d checks, %d failures\\n",checks,failures); return failures ? 1 : 0; }\n'
    return code + tests


def run(out):
    out.mkdir(parents=True, exist_ok=True)
    c = out / 'mt6363-registers.c'
    exe = out / 'mt6363-registers'
    c.write_text(generate(source.read_text()))
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-Wall', '-Wextra',
                    '-Werror', str(c), '-o', str(exe)], check=True)
    return subprocess.run([str(exe.resolve())]).returncode

if args.output_dir:
    raise SystemExit(run(args.output_dir))
with tempfile.TemporaryDirectory(prefix='mt6363-registers-') as directory:
    raise SystemExit(run(Path(directory)))
