/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_DRAW_H
#define EG_DRAW_H
#include "fdt-guard.h"
/* Explicit mapped linear memory only; caller proves ownership/accessibility.
 * No display initialization, address discovery, allocation or device policy. */
int eg_draw_valid(const struct eg_framebuffer *fb);
void eg_draw_clear(const struct eg_framebuffer *fb);
int eg_draw_fill_rect(const struct eg_framebuffer *fb, unsigned x, unsigned y,
                      unsigned width, unsigned height, uint32_t color);
int eg_draw_outline(const struct eg_framebuffer *fb, unsigned x, unsigned y,
                    unsigned width, unsigned height, uint32_t color);
int eg_draw_text(const struct eg_framebuffer *fb, unsigned x, unsigned y,
                 unsigned scale, const char *text);
int eg_draw_rect(const struct eg_framebuffer *fb, unsigned x, unsigned y,
                 unsigned width, unsigned height);
#endif
