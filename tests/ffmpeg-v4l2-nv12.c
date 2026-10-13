/* Guard-page regression tests for the patched FFmpeg V4L2 NV12 copier.
 * Compile against libavcodec/ from a source tree with the package patch applied.
 */
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include "v4l2_nv12_copy.h"

struct guarded { uint8_t *map, *data; size_t length; };
static struct guarded allocate(size_t n)
{
    size_t page = sysconf(_SC_PAGESIZE), rounded = (n + page - 1) / page * page;
    struct guarded g = { .length = rounded + page };
    g.map = mmap(NULL, g.length, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(g.map != MAP_FAILED);
    assert(!mprotect(g.map + rounded, page, PROT_NONE));
    g.data = g.map + rounded - n;
    return g;
}
static void check(int w, int h, int stride, int storage_h, int negative)
{
    int uvw = 2 * (w / 2 + w % 2), uvh = h / 2 + h % 2;
    size_t size = (size_t)stride * (storage_h + storage_h / 2 + storage_h % 2);
    struct guarded y = allocate((size_t)w * h), uv = allocate((size_t)uvw * uvh);
    struct guarded dst = allocate(size);
    size_t used = 0;
    for (int i = 0; i < h; i++) memset(y.data + i * w, 32 + i % 100, w);
    for (int i = 0; i < uvh; i++) memset(uv.data + i * uvw, 64 + i % 100, uvw);
    const uint8_t *yp = y.data + (negative ? (h - 1) * w : 0);
    const uint8_t *up = uv.data + (negative ? (uvh - 1) * uvw : 0);
    assert(!ff_v4l2_copy_nv12(dst.data, size, stride, storage_h,
                            yp, negative ? -w : w, up, negative ? -uvw : uvw,
                            w, h, &used));
    assert(used == size);
    for (int i = 0; i < storage_h; i++)
        for (int j = 0; j < stride; j++)
            assert(dst.data[(size_t)i * stride + j] ==
                   (i < h && j < w ? 32 + (negative ? h - 1 - i : i) % 100 : 16));
    for (int i = 0; i < storage_h / 2 + storage_h % 2; i++)
        for (int j = 0; j < stride; j++)
            assert(dst.data[(size_t)(storage_h + i) * stride + j] ==
                   (i < uvh && j < uvw ? 64 + (negative ? uvh - 1 - i : i) % 100 : 128));
    memset(dst.data, 0xa5, size);
    assert(ff_v4l2_copy_nv12(dst.data, size - 1, stride, storage_h,
                           yp, w, up, uvw, w, h, &used) == -ENOSPC);
    for (size_t i = 0; i < size; i++) assert(dst.data[i] == 0xa5);
    assert(ff_v4l2_copy_nv12(dst.data, size, stride, h - 1,
                           yp, w, up, uvw, w, h, &used) == -EINVAL);
    assert(ff_v4l2_copy_nv12(dst.data, size, stride, storage_h,
                           yp, w - 1, up, uvw, w, h, &used) == -EINVAL);
    munmap(y.map, y.length); munmap(uv.map, uv.length); munmap(dst.map, dst.length);
}
int main(void)
{
    check(1280, 720, 1280, 736, 0);
    check(1920, 1080, 1920, 1088, 0);
    check(640, 480, 640, 480, 0);
    check(638, 478, 640, 480, 0);
    check(639, 479, 640, 480, 1);
    check(1280, 720, 1280, 736, 1);
    puts("NV12 copy: guarded 720p/1080p, padded stride, odd size, negative stride and bounds passed");
}
