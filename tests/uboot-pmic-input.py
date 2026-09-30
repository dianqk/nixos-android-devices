#!/usr/bin/env python3
"""Exercise actual SPMI formatters and PMIC input setup with register fixtures."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def block(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


root = Path(sys.argv[1])
spmi = (root / 'drivers/spmi/spmi-msm.c').read_text()
gpio = (root / 'drivers/gpio/qcom_pmic_gpio.c').read_text()
functions = '\n'.join([
    block(spmi, 'static u32 pmic_arb_fmt_cmd_v1('),
    block(spmi, 'static u32 pmic_arb_fmt_cmd_v2('),
    block(gpio, 'static int _qcom_gpio_set_direction('),
    block(gpio, 'static int qcom_gpio_set_direction('),
    block(gpio, 'static int qcom_pmic_pinctrl_pinconf_set('),
])
defines = '\n'.join(line for line in gpio.splitlines() if line.startswith('#define '))
fixture = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>
typedef uint8_t u8;
typedef uint32_t u32;
#define ENOTSUPP 524
enum { PIN_CONFIG_OUTPUT_ENABLE, PIN_CONFIG_OUTPUT, PIN_CONFIG_INPUT_ENABLE,
       PIN_CONFIG_BIAS_PULL_UP, PIN_CONFIG_BIAS_DISABLE, PIN_CONFIG_POWER_SOURCE };
struct udevice { struct udevice *parent; };
struct qcom_pmic_gpio_data {
    uint32_t pid;
    bool lv_mv_type;
    u32 pin_count;
    struct udevice *pmic;
};
static struct udevice pmic;
static struct qcom_pmic_gpio_data plat = { .pid = 0x8800, .lv_mv_type = true, .pmic = &pmic };
static u8 regs[0x10000];
static int failure = -1;
static void *dev_get_plat(struct udevice *dev) { (void)dev; return &plat; }
static int pmic_reg_write(struct udevice *dev, unsigned reg, unsigned value)
{
    assert(dev == &pmic && reg < sizeof(regs) && value <= 255);
    if ((int)reg == failure) return -EIO;
    regs[reg] = value;
    return 0;
}
static int pmic_clrsetbits(struct udevice *dev, unsigned reg, unsigned clear, unsigned set)
{
    return pmic_reg_write(dev, reg, (regs[reg] & ~clear) | set);
}
'''
main = r'''
int main(void)
{
    /* Arbiter bc is len-1; both APIs carry exactly one byte. */
    assert(pmic_arb_fmt_cmd_v1(1, 3, 0x8d, 0x41) == ((1U<<27)|(3U<<20)|(0x8dU<<12)|(0x41U<<4)));
    assert(pmic_arb_fmt_cmd_v2(0, 0x42) == 0x420);
    assert(pmic_arb_fmt_cmd_v2(1, 0xff) == ((1U<<27)|0xff0));
    struct udevice gpio = { .parent = &pmic };
    unsigned pin = 5, base = 0x8d00;
    regs[base + REG_EN_CTL] = 0x80;
    regs[base + 0x43] = 0x55; /* untouched neighbour sentinel */
    assert(!qcom_pmic_pinctrl_pinconf_set(&gpio, pin, PIN_CONFIG_INPUT_ENABLE, 1));
    assert(!qcom_pmic_pinctrl_pinconf_set(&gpio, pin, PIN_CONFIG_POWER_SOURCE, 1));
    assert(!qcom_pmic_pinctrl_pinconf_set(&gpio, pin, PIN_CONFIG_BIAS_PULL_UP, 0));
    assert(!qcom_gpio_set_direction(&gpio, pin, true, 0));
    assert(regs[base + REG_CTL] == 0);
    assert(regs[base + REG_DIG_VIN_CTL] == 1);
    assert(regs[base + REG_DIG_PULL_CTL] == 0);
    assert(regs[base + 0x43] == 0x55);
    assert(regs[base + REG_EN_CTL] == 0x80);
    /* Input direction alone also preserves an existing firmware pin state. */
    regs[base + REG_DIG_PULL_CTL] = 4;
    assert(!qcom_gpio_set_direction(&gpio, pin, true, 0));
    assert(regs[base + REG_DIG_PULL_CTL] == 4);
    assert(qcom_pmic_pinctrl_pinconf_set(&gpio, pin, PIN_CONFIG_POWER_SOURCE, 8) == -EINVAL);
    assert(qcom_pmic_pinctrl_pinconf_set(&gpio, pin, 999, 0) == -ENOTSUPP);
    failure = base + REG_CTL;
    assert(qcom_gpio_set_direction(&gpio, pin, true, 0) == -EIO);
    assert(regs[base + REG_DIG_PULL_CTL] == 4);
    failure = -1;
    /* Existing output policy still sets its own supply and no-pull state. */
    assert(!qcom_gpio_set_direction(&gpio, pin, false, 1));
    assert(regs[base + REG_CTL] == REG_CTL_LV_MV_MODE_INOUT);
    assert(regs[base + REG_DIG_PULL_CTL] == REG_DIG_PULL_NO_PU);
    assert(regs[base + REG_DIG_VIN_CTL] == 0);
    assert(regs[base + REG_LV_MV_OUTPUT_CTL] == 0x80);
    puts("SPMI byte count, PMIC input pinctrl, preserved bias/VIN, errors and output policy: PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='uboot-pmic-', dir=os.environ.get('TMPDIR')) as directory:
    source, binary = Path(directory) / 'pmic.c', Path(directory) / 'pmic'
    source.write_text(fixture + defines + '\n' + functions + main)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-g', '-O1',
                    '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
