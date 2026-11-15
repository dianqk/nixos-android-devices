#!/usr/bin/env python3
"""Exercise actual FastRPC buffer callbacks after poisoning the user object.

Host-only regression: no DSP/device access. On the old implementation the
PROT_NONE user page faults in mmap/free; the raw DMA-handle fix must pass.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def function(source, name):
    match = re.search(rf"(?m)^static [^;\n]*\b{name}\(", source)
    if not match:
        raise ValueError(f"Missing function: {name}")
    start = source.index("{", match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


PRELUDE = r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
typedef uint64_t u64;
typedef uint64_t dma_addr_t;
struct device { int unused; };
struct list_head { void *next, *prev; };
struct mutex { int unused; };
struct sg_table { int unused; };
struct vm_area_struct { uintptr_t vm_start, vm_end; };
struct dma_buf { void *priv, *resv; };
struct dma_buf_attachment { struct device *dev; void *priv; };
struct fastrpc_soc_data { unsigned sid_pos; };
struct rpmsg_device { struct device dev; };
struct fastrpc_channel_ctx { struct fastrpc_soc_data *soc_data; struct rpmsg_device *rpdev; };
struct fastrpc_session_ctx { unsigned sid; };
struct fastrpc_user { struct fastrpc_channel_ctx *cctx; struct fastrpc_session_ctx *sctx; };
#define GFP_KERNEL 0
#define kzalloc_obj(obj) calloc(1, sizeof(obj))
#define kfree(ptr) free(ptr)
#define INIT_LIST_HEAD(ptr) ((void)(ptr))
#define mutex_init(ptr) ((void)(ptr))
#define mutex_destroy(ptr) ((void)(ptr))
#define mutex_lock(ptr) ((void)(ptr))
#define mutex_unlock(ptr) ((void)(ptr))
#define list_add(a,b) ((void)(a), (void)(b))
#define list_del(a) ((void)(a))
#define sg_free_table(a) ((void)(a))
#define dev_err(...) ((void)0)
#define dma_resv_assert_held(a) ((void)(a))
#define GENMASK_ULL(h,l) ((UINT64_MAX >> (63-(h))) & (UINT64_MAX << (l)))
static dma_addr_t raw_handle;
static int fail_alloc, coherent_live, free_calls, mmap_calls, attach_calls;
static void *dma_alloc_coherent(struct device *dev, u64 size, dma_addr_t *handle, int flags) {
    (void)dev; (void)flags;
    if (fail_alloc) return NULL;
    *handle = raw_handle;
    coherent_live++;
    return calloc(1, size);
}
static void dma_free_coherent(struct device *dev, u64 size, void *ptr, dma_addr_t handle) {
    (void)dev; (void)size;
    assert(handle == raw_handle);
    assert(ptr && coherent_live > 0);
    coherent_live--; free_calls++;
    free(ptr);
}
static int dma_get_sgtable(struct device *dev, struct sg_table *table, void *ptr, dma_addr_t handle, u64 size) {
    (void)dev; (void)table; (void)size;
    assert(handle == raw_handle && ptr);
    attach_calls++;
    return 0;
}
static int dma_mmap_coherent(struct device *dev, struct vm_area_struct *vma, void *ptr, dma_addr_t handle, size_t size) {
    (void)dev; (void)vma;
    assert(handle == raw_handle && ptr && size == 4096);
    mmap_calls++;
    return 0;
}
static inline u64 fastrpc_sid_offset(struct fastrpc_channel_ctx *cctx, struct fastrpc_session_ctx *sctx) {
    return (u64)sctx->sid << cctx->soc_data->sid_pos;
}
'''
MAIN = r'''
static void check_buffer(unsigned sid_pos, unsigned sid, dma_addr_t raw, int remote) {
    size_t pagesize = sysconf(_SC_PAGESIZE);
    struct fastrpc_user *fl = mmap(NULL, pagesize, PROT_READ | PROT_WRITE,
                                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(fl != MAP_FAILED);
    struct fastrpc_soc_data soc = { sid_pos };
    struct rpmsg_device rpdev = {0};
    struct fastrpc_channel_ctx cctx = { &soc, &rpdev };
    struct fastrpc_session_ctx sctx = { sid };
    struct device dev = {0};
    fl->cctx = &cctx; fl->sctx = &sctx;
    struct fastrpc_buf *buf = NULL;
    raw_handle = raw;
    int rc = remote ? fastrpc_remote_heap_alloc(fl, &dev, 4096, &buf)
                    : fastrpc_buf_alloc(fl, &dev, 4096, &buf);
    assert(rc == 0 && buf);
    assert(buf->dma_addr == raw + (remote ? 0 : ((u64)sid << sid_pos)));
    struct dma_buf dbuf = { .priv = buf };
    // Stronger than a freed/slab-reused user: any dereference is an immediate fault.
    assert(mprotect(fl, pagesize, PROT_NONE) == 0);
    struct vm_area_struct vma = { .vm_start = 0x1000, .vm_end = 0x2000 };
    struct dma_buf_attachment attachment = { .dev = &dev };
    assert(fastrpc_mmap(&dbuf, &vma) == 0);
    assert(fastrpc_dma_buf_attach(&dbuf, &attachment) == 0);
    fastrpc_dma_buf_detatch(&dbuf, &attachment);
    fastrpc_release(&dbuf);
    assert(coherent_live == 0);
    assert(munmap(fl, pagesize) == 0);
}
int main(void) {
    check_buffer(32, 4, 0x23456000, 0);
    check_buffer(48, 3, 0x123456789ULL, 0);
    check_buffer(32, 0, 0x34567000, 0);
    check_buffer(32, 4, 0x45678000, 1);
    struct fastrpc_buf *buf = NULL;
    struct device dev = {0};
    struct fastrpc_soc_data soc = {32};
    struct fastrpc_channel_ctx cctx = { .soc_data = &soc };
    struct fastrpc_session_ctx sctx = {1};
    struct fastrpc_user fl = { &cctx, &sctx };
    fail_alloc = 1;
    assert(fastrpc_buf_alloc(&fl, &dev, 4096, &buf) == -ENOMEM);
    assert(buf == NULL && coherent_live == 0);
    fastrpc_buf_free(NULL);
    assert(free_calls == 4 && mmap_calls == 4 && attach_calls == 4);
    puts("PASS: actual FastRPC allocate/mmap/attach/detach/release callbacks survive dead user; raw DMA handles, SID tags, remote heap and allocation failure checked");
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="kernel tree or fastrpc.c")
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    path = args.source if args.source.is_file() else args.source / "drivers/misc/fastrpc.c"
    source = path.read_text()
    structs = "\n".join(re.search(rf"struct {name} \{{.*?\n\}};", source, re.S)[0]
                        for name in ["fastrpc_buf", "fastrpc_dma_buf_attachment"])
    functions = "\n".join(function(source, name) for name in [
        "fastrpc_ipa_to_dma_addr", "fastrpc_buf_free", "__fastrpc_buf_alloc", "fastrpc_buf_alloc",
        "fastrpc_remote_heap_alloc", "fastrpc_release", "fastrpc_dma_buf_attach",
        "fastrpc_dma_buf_detatch", "fastrpc_mmap"])
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "check.c").write_text(PRELUDE + structs + functions + MAIN)
        subprocess.run([args.cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                        "-g", str(root / "check.c"), "-o", str(root / "check")], check=True)
        subprocess.run([str(root / "check")], check=True, timeout=10)


if __name__ == "__main__":
    main()
