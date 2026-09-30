#!/usr/bin/env python3
"""Compile actual ACM callbacks with USB mocks; no phone or boot image needed."""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
if source.is_dir():
    source /= 'drivers/usb/gadget/f_acm.c'
text = source.read_text()

def function(name):
    pos = text.index(name + '(')
    start = text.rfind('\nstatic ', 0, pos) + 1
    body = text.index('{', pos)
    depth = 1
    end = body + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#define ACM_CTRL_DTR 1
#define REQ_SIZE_MAX 512
struct udevice { int unused; };
struct usb_ep { int unused; };
struct usb_function { int unused; };
struct usb_request { void *buf; void *context; int status, actual, length; };
struct stdio_dev { void *priv; };
struct ring { unsigned size; };
struct f_acm {
 struct udevice *udc;
 struct usb_function usb_function;
 struct usb_ep *ep_in, *ep_out, *ep_notify;
 struct usb_request *req_in, *req_out;
 struct ring rx_buf, tx_buf;
 bool connected, tx_on;
 unsigned handshake_bits;
};
static struct f_acm state, *default_acm_function = &state;
static struct udevice controller;
static int polls, queued, schedules, event, registrations;
static bool complete_tx = true;
static struct f_acm *stdio_to_acm(struct stdio_dev *dev) { return dev->priv; }
static struct f_acm *func_to_acm(struct usb_function *f) { return &state; }
static void pr_err(const char *fmt, int value) { assert(!"unexpected USB error"); }
static int udc_device_get_by_index(int index, struct udevice **dev) {
 assert(index == 0); *dev = &controller; return 0;
}
static void g_dnl_clear_detach(void) {}
static int g_dnl_register(const char *name) { registrations++; return 0; }
static int ctrlc(void) { return 0; }
static void schedule(void) { assert(++schedules < 4); }
static bool acm_connected(struct stdio_dev *dev) { return state.connected; }
static void dm_usb_gadget_handle_interrupts(struct udevice *dev) {
 polls++;
 if (event == 1) { state.connected = true; state.handshake_bits = ACM_CTRL_DTR; state.tx_on = true; }
 if (event == 2) { state.connected = false; state.handshake_bits = 0; state.req_in = NULL; }
 event = 0;
}
static int buf_pop(struct ring *buf, void *dest, int count) {
 int n = buf->size < (unsigned)count ? buf->size : (unsigned)count;
 buf->size -= n; return n;
}
static void buf_push(struct ring *buf, const void *src, int count) { buf->size += count; }
static int usb_ep_queue(struct usb_ep *ep, struct usb_request *req, int flags) {
 queued++; return 0;
}
static void usb_ep_disable(struct usb_ep *ep) {}
static void usb_ep_free_request(struct usb_ep *ep, struct usb_request *req) { free(req); }
'''
# The TX callback is completed by the mock's next interrupt poll.
prefix = prefix.replace('polls++;', 'assert(++polls < 100); if (complete_tx) state.tx_on = true;')
names = ['acm_rx_complete', 'acm_disable', '__acm_tx', 'acm_stdio_tstc', 'acm_stdio_start']
suffix = r'''
int main(void) {
 struct stdio_dev console = {0};
 struct usb_ep ep = {0};
 struct usb_request req = { .context = &state, .actual = 1 };
 assert(acm_stdio_start(&console) == 0);
 assert(console.priv == &state && registrations == 1 && schedules == 0);
 assert(acm_stdio_start(&console) == 0 && registrations == 1);
 state.tx_buf.size = 8;
 __acm_tx(&state); /* no host, no request buffers: must return safely */
 assert(polls == 1 && queued == 0 && state.tx_buf.size == 8);
 char data[512];
 struct usb_request tx = { .buf = data };
 state.req_in = &tx; event = 1;
 __acm_tx(&state); /* late enumeration must allow buffered output */
 assert(queued == 1 && state.tx_buf.size == 0);
 state.tx_buf.size = 8; state.tx_on = false; complete_tx = false;
 __acm_tx(&state); /* configured host stopped reading: must not block */
 assert(queued == 1 && state.tx_buf.size == 8);
 complete_tx = true;
 assert(acm_stdio_tstc(&console) == 0); /* input polls flush late output */
 assert(queued == 2 && state.tx_buf.size == 0);
 state.tx_buf.size = 8; event = 2;
 __acm_tx(&state); /* disconnect during poll must not touch freed req_in */
 assert(queued == 2 && state.tx_buf.size == 8 && !state.connected);
 queued = 0;
 req.status = -ESHUTDOWN; acm_rx_complete(&ep, &req);
 req.status = -ECONNRESET; acm_rx_complete(&ep, &req);
 assert(queued == 0 && state.rx_buf.size == 0);
 req.status = 0; acm_rx_complete(&ep, &req);
 assert(queued == 1 && state.rx_buf.size == 1 && req.actual == 0);
 state.req_in = calloc(1, sizeof(*state.req_in));
 state.req_out = calloc(1, sizeof(*state.req_out));
 state.connected = true; state.handshake_bits = ACM_CTRL_DTR; state.tx_on = true;
 acm_disable(&state.usb_function);
 assert(!state.connected && !state.handshake_bits && !state.tx_on);
 assert(!state.req_in && !state.req_out);
 puts("ACM: no-host start, stalled/late host, disconnect and cancelled RX passed");
}
'''
temporary_root = pathlib.Path.cwd() / 'tmp'
temporary_root.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='uboot-acm-', dir=temporary_root) as directory:
    root = pathlib.Path(directory)
    c = root / 'check.c'
    binary = root / 'check'
    c.write_text(prefix + '\n'.join(function(name) for name in names) + suffix)
    subprocess.run(['cc', '-std=c11', '-O1', '-g', '-fsanitize=address,undefined',
                    str(c), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=5)
