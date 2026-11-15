#!/usr/bin/env python3
"""Exercise the actual MT6363 button callback with delayed/failing PMIF MMIO."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
source = (root / 'drivers/button/button-mt6363-HACK.c').read_text()
uclass = (root / 'drivers/button/button-uclass.c').read_text()
assert 'case KEY_POWER:\n\t\treturn KEY_ENTER;' in uclass
dtb_source = (root / 'arch/arm/dts/mt6897-alldocube-t880.dts').read_text()
assert 'mediatek,mt6363-buttons-raw' in dtb_source
assert 'linux,code = <KEY_POWER>' in dtb_source
start = source.index('static enum button_state_t button_mt6363_get_state(')
end = source.index('\nstatic int button_mt6363_get_code', start)
callback = source[start:end]
constants = "\n".join(line for line in source.splitlines()
                      if line.startswith(("#define PMIF_", "#define MT6363_"))) + "\n"
fixture = r'''
#include <assert.h>
#include <stdint.h>
#include <errno.h>
typedef uint32_t u32;
#define __iomem
#define BIT(n) (1u << (n))
#define KEY_POWER 116
#define KEY_VOLUMEUP 115
enum button_state_t { BUTTON_OFF, BUTTON_ON };
struct button_mt6363_priv { int linux_code; };
struct udevice { struct button_mt6363_priv priv; };
static void *dev_get_priv(struct udevice *dev) { return &dev->priv; }
static u32 data, states[32];
static int pos, nstates, commands, reads, clears;
static u32 readl(uintptr_t addr) {
    if (addr == 0x1cc04828) {
        assert(pos < nstates);
        return states[pos++];
    }
    assert(addr == 0x1cc04814);
    assert(commands == 1 && PMIF_FSM(states[pos - 1]) == 6);
    ++reads; return data;
}
static void writel(u32 value, uintptr_t addr) {
    if (addr == 0x1cc04800) {
        assert(value == 0xc400001e && PMIF_FSM(states[pos - 1]) == 0);
        ++commands;
    } else { assert(addr == 0x1cc04824 && value == 1); ++clears; }
}
#define readl_poll_timeout(addr, val, cond, timeout) ({ \
    int err = -ETIMEDOUT; \
    for (int i = 0; i < 8; ++i) { val = readl((uintptr_t)(addr)); \
        if (cond) { err = 0; break; } } err; })
static void reset(u32 value, int mode) {
    data = value; pos = commands = reads = clears = 0; nstates = 32;
    for (int i = 0; i < 32; ++i) states[i] = mode == 1 ? 12 : 0;
    if (!mode) { states[0] = 2; states[1] = 0; states[2] = 4; states[3] = 12; }
}
'''
main = r'''
int main(void) {
    struct udevice dev = { {KEY_POWER} };
    for (u32 value = 0; value < 256; ++value) {
        reset(value, 0);
        assert(button_mt6363_get_state(&dev) == ((value & BIT(1)) ? BUTTON_OFF : BUTTON_ON));
        assert(commands == 1 && reads == 1 && clears == 1 && pos == 4);
    }
    dev.priv.linux_code = KEY_VOLUMEUP;
    reset(0xfffffff7, 0); assert(button_mt6363_get_state(&dev) == BUTTON_ON);
    reset(0xffffffff, 0); assert(button_mt6363_get_state(&dev) == BUTTON_OFF);
    dev.priv.linux_code = KEY_POWER;
    reset(0, 1); assert((int)button_mt6363_get_state(&dev) == -ETIMEDOUT);
    assert(commands == 0 && reads == 0 && clears == 1);
    /* Next poll succeeds after clearing a stale valid transaction. */
    reset(0x1c, 0); assert(button_mt6363_get_state(&dev) == BUTTON_ON);
    reset(0, 2); assert((int)button_mt6363_get_state(&dev) == -ETIMEDOUT);
    assert(commands == 1 && reads == 0 && clears == 0);
    return 0;
}
'''
with tempfile.TemporaryDirectory() as directory:
    c = pathlib.Path(directory) / 'test.c'
    exe = pathlib.Path(directory) / 'test'
    c.write_text(fixture.replace('enum button_state_t', constants + 'enum button_state_t', 1) + callback + main)
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', '-o', str(exe), str(c)], check=True)
    subprocess.run([str(exe)], check=True)
print('MT6363 PMIF delay, bit decoding, timeout and stale-valid tests passed')
