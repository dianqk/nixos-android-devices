#!/usr/bin/env python3
"""Compile actual button_read_keys/input_tstc with a checked input API fixture."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def function(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


root = Path(sys.argv[1])
button = function((root / 'drivers/input/button_kbd.c').read_text(), 'int button_read_keys(')
tstc = function((root / 'drivers/input/input.c').read_text(), 'int input_tstc(')
fixture = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;
#define BUTTON_OFF 0
#define BUTTON_ON 1
#define UCLASS_BUTTON 0
#define debug(...) do {} while (0)
struct button_uc_plat { const char *label; };
struct udevice { struct button_uc_plat plat; int code, state; };
struct uclass { int unused; };
struct input_config {
    struct udevice *dev;
    int fifo_in, fifo_out;
    int (*read_keys)(struct input_config *);
};
struct button_kbd_priv { struct input_config *input; u32 button_size; u32 *old_state; };
static struct udevice buttons[] = {
    {{NULL}, 0, 0}, {{"unmapped"}, 0, 0}, {{"volume"}, 2, 0},
};
static struct uclass cls;
static u32 old_states[3];
static struct button_kbd_priv priv = { .button_size = 3, .old_state = old_states };
#define uclass_id_foreach_dev(id, dev, uc) \
    for (uc = &cls, dev = buttons; dev < buttons + 3; ++dev)
static void *dev_get_priv(struct udevice *dev) { (void)dev; return &priv; }
static void *dev_get_uclass_plat(struct udevice *dev) { return &dev->plat; }
static int button_get_code(struct udevice *dev) { return dev->code; }
static int button_get_state(struct udevice *dev) { return dev->state; }
static bool held[4];
static int presses, releases;
/* input_add_keycode contract: release=true cannot enqueue characters. */
static int input_add_keycode(struct input_config *input, int code, bool release)
{
    assert(code > 0 && code < 4);
    if (release) { held[code] = false; ++releases; return 0; }
    assert(!held[code]);
    held[code] = true;
    ++presses;
    ++input->fifo_in;
    return 1;
}
'''
main = r'''
int main(void)
{
    struct input_config input = { .read_keys = button_read_keys };
    assert(!input_tstc(&input));
    assert(presses == 0 && releases == 0);
    buttons[2].state = BUTTON_ON;
    assert(input_tstc(&input)); /* visible on first poll, not after a false empty */
    assert(presses == 1 && held[2]);
    assert(old_states[0] == 0 && old_states[1] == BUTTON_ON);
    input.fifo_out = input.fifo_in;
    assert(!input_tstc(&input)); /* held button is not a new press */
    buttons[2].state = -5;
    assert(!input_tstc(&input));
    assert(held[2] && old_states[1] == BUTTON_ON && releases == 0);
    buttons[2].state = 2; /* neither a press nor release */
    assert(!input_tstc(&input));
    buttons[2].state = BUTTON_ON;
    assert(!input_tstc(&input));
    buttons[1].code = -5; /* earlier unreadable code must not move state slots */
    buttons[2].state = BUTTON_OFF;
    assert(!input_tstc(&input));
    assert(!held[2] && releases == 1 && presses == 1 && old_states[1] == 0);
    /* A console flush must consume a newly queued press on its first poll. */
    buttons[2].state = BUTTON_ON;
    int drained = 0;
    while (input_tstc(&input)) { ++input.fifo_out; ++drained; }
    assert(drained == 1 && presses == 2);
    buttons[2].state = BUTTON_OFF;
    assert(!input_tstc(&input));
    assert(releases == 2 && !held[2]);
    puts("button press/release, immediate input visibility, error isolation and flush: PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='uboot-button-', dir=os.environ.get('TMPDIR')) as directory:
    source = Path(directory) / 'button.c'
    binary = Path(directory) / 'button'
    source.write_text(fixture + button + '\n' + tstc + main)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-g', '-O1',
                    '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
