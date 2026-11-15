/* SPDX-License-Identifier: GPL-2.0-only */
#include <stddef.h>
/* Volatile byte operations prevent compiler reintroduction of libc helpers.
 * Only ordinary image-owned RAM; never use these for device I/O. */
void *memset(void *dst, int value, size_t n)
{
    volatile unsigned char *p = dst;
    for (size_t i = 0; i < n; i++) p[i] = (unsigned char)value;
    return dst;
}
void *memcpy(void *dst, const void *src, size_t n)
{
    volatile unsigned char *d = dst;
    const volatile unsigned char *s = src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dst;
}
