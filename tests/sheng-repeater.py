#!/usr/bin/env python3
"""Run the actual patched PM8550B driver with fault-injecting PMIC APIs.

Usage: python tests/sheng-repeater.py /path/to/patched/u-boot
Only regular files under the repository's tmp directory are written.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (Path(sys.argv[1]) / 'drivers/phy/qcom/phy-pm8550b-eusb2.c').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('#include'))
shim = r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32;
typedef uint8_t u8;
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define BIT(n) (1U << (n))
#define UCLASS_PHY 1
#define U_BOOT_DRIVER(n) struct driver n
struct udevice { struct udevice *parent; void *priv; };
struct phy { struct udevice *dev; };
struct phy_ops { int (*init)(struct phy *); int (*exit)(struct phy *); };
struct udevice_id { const char *compatible; };
struct driver { const char *name; int id; const void *of_match, *ops;
                int (*probe)(struct udevice *); unsigned long priv_auto; };
static struct udevice pmic;
static int writes, reads, delays, fail_at, read_result, property_result;
static unsigned int property_value;
static struct { unsigned int reg, val; } written[16];
static void *dev_get_priv(struct udevice *d) { return d->priv; }
static int dev_read_u32(struct udevice *d, const char *key, u32 *out) {
    assert(strcmp(key, "reg") == 0); *out = property_value; return property_result;
}
static int pmic_reg_write(struct udevice *d, unsigned int reg, unsigned int val) {
    assert(d == &pmic && writes < 16);
    written[writes].reg = reg; written[writes].val = val;
    return writes++ == fail_at ? -EIO : 0;
}
static int pmic_reg_read(struct udevice *d, unsigned int reg) {
    assert(d == &pmic && reg == 0xfd08); reads++; return read_result;
}
static void udelay(unsigned int us) { assert(us == 50); delays++; }
static void clear(int fail, int status) {
    writes = reads = delays = 0; fail_at = fail; read_result = status;
}
'''
checks = r'''
int main(void) {
    struct pm8550b_eusb2_priv priv;
    struct udevice d = { .parent = &pmic, .priv = &priv };
    struct phy phy = { .dev = &d };
    const unsigned int regs[] = {0xfd46,0xfd51,0xfd54,0xfd57,0xfde8,0xfded};
    const unsigned int vals[] = {0x80,8,3,5,0,0};
    property_value = 0xfd00;
    assert(pm8550b_eusb2_probe(&d) == 0);
    clear(-1, 0x80);
    assert(pm8550b_eusb2_init(&phy) == 0);
    assert(writes == 6 && reads == 1 && delays == 0);
    for (int i = 0; i < 6; i++) {
        assert(written[i].reg == regs[i] && written[i].val == vals[i]);
    }
    assert(pm8550b_eusb2_exit(&phy) == 0);
    assert(written[6].reg == 0xfd46 && written[6].val == 0);
    for (int i = 0; i < 6; i++) {
        clear(i, 0x80);
        assert(pm8550b_eusb2_init(&phy) == -EIO);
        assert(writes == i + 2 && reads == 0);
        assert(written[writes-1].reg == 0xfd46 && written[writes-1].val == 0);
    }
    clear(-1, -EIO);
    assert(pm8550b_eusb2_init(&phy) == -EIO);
    assert(reads == 1 && delays == 0 && writes == 7);
    clear(-1, 0);
    assert(pm8550b_eusb2_init(&phy) == -ETIMEDOUT);
    assert(reads == 100 && delays == 100 && writes == 7);
    assert(written[6].reg == 0xfd46 && written[6].val == 0);
    clear(0, 0x80);
    assert(pm8550b_eusb2_exit(&phy) == -EIO);
    property_result = -EINVAL;
    assert(pm8550b_eusb2_probe(&d) == -EINVAL);
    property_result = 0; property_value = 0xffff;
    assert(pm8550b_eusb2_probe(&d) == -EINVAL);
    puts("PM8550B: init/exit, all six write failures, read failure, bounded timeout and invalid DT pass");
}
'''
with tempfile.TemporaryDirectory(prefix='sheng-repeater-', dir=repo / 'tmp') as td:
    td = Path(td)
    (td / 'driver.c').write_text(shim + source + checks)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=gnu11', '-g',
                    '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                    str(td / 'driver.c'), '-o', str(td / 'test')], check=True)
    subprocess.run([str(td / 'test')], check=True)
