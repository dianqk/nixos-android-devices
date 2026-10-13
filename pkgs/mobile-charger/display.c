/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "display.h"
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/kd.h>
#include <linux/vt.h>
#include <linux/tiocl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef KD_FONT_OP_SET_TALL
#define KD_FONT_OP_SET_TALL 4
#define KD_FONT_OP_GET_TALL 5
#endif
struct display {
    int fd, tty;
    const char *backlight;
    int brightness;
    unsigned columns, rows;
    char previous[UI_MAX_COLUMNS * UI_MAX_ROWS];
};
static int write_all(int fd, const char *p, size_t n) {
    while (n) {
        ssize_t done = write(fd, p, n);
        if (done < 0 && errno == EINTR) continue;
        if (done <= 0) return -1;
        p += done; n -= (size_t)done;
    }
    return 0;
}
static int backlight_write(struct display *d, const char *attr, int value) {
    char path[4096], buf[32];
    if (snprintf(path, sizeof(path), "%s/%s", d->backlight, attr) >= (int)sizeof(path)) return -1;
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    int len = snprintf(buf, sizeof(buf), "%d\n", value);
    int result = write_all(fd, buf, (size_t)len);
    close(fd); return result;
}
/* Select a readable 1:2 font while preserving the complete centered layout.
 * Prefer roughly 5 mm glyphs when panel metadata is plausible; otherwise aim
 * for 40 rows. Layout fit always wins over the preferred physical size. */
static unsigned font_width(unsigned width, unsigned height, unsigned mm_width,
                           unsigned mm_height, unsigned requested) {
    if (!width || !height || width > 16384 || height > 16384) return 0;
    unsigned preferred = height / 80;
    if (mm_width >= 20 && mm_width <= 2000 && mm_height >= 20 && mm_height <= 2000) {
        double dpi_x = width * 25.4 / mm_width, dpi_y = height * 25.4 / mm_height;
        if (dpi_x >= 50 && dpi_x <= 1000 && dpi_y >= 50 && dpi_y <= 1000 &&
            dpi_x / dpi_y >= 0.8 && dpi_x / dpi_y <= 1.25)
            preferred = (unsigned)((double)height * 5 / mm_height / 2);
    }
    unsigned best = 0;
    for (unsigned w = 8; w <= 64; w += 8) {
        unsigned columns = width / w, rows = height / (w * 2);
        if (columns < 40 || columns > UI_MAX_COLUMNS || rows < 32 || rows > UI_MAX_ROWS) continue;
        if (requested) { if (w == requested) return w; }
        else if (!best || w <= preferred) best = w;
    }
    return requested ? 0 : best;
}
/* Scale the kernel's existing bitmap font; no font files or font library. */
static int set_font(int tty, unsigned width) {
    unsigned height = width * 2, pitch = (width + 7) / 8;
    unsigned char *source = calloc(512, 128 * 8), *target = calloc(512, height * pitch);
    if (!source || !target) { free(source); free(target); return -1; }
    struct console_font_op get = {.op = KD_FONT_OP_GET_TALL, .width = 64, .height = 128,
                                  .charcount = 512, .data = source};
    int result = -1;
    if (ioctl(tty, KDFONTOP, &get) || !get.width || !get.height || get.width > 64 || get.height > 128 ||
        (get.charcount != 256 && get.charcount != 512)) goto out;
    unsigned stride = (get.width + 7) / 8;
    for (unsigned g = 0; g < get.charcount; g++) for (unsigned y = 0; y < height; y++) for (unsigned x = 0; x < width; x++) {
        unsigned sx = x * get.width / width, sy = y * get.height / height;
        if (source[g * 128 * stride + sy * stride + sx / 8] & (0x80U >> (sx % 8)))
            target[g * height * pitch + y * pitch + x / 8] |= 0x80U >> (x % 8);
    }
    struct console_font_op set = {.op = KD_FONT_OP_SET_TALL, .width = width, .height = height,
                                  .charcount = get.charcount, .data = target};
    result = ioctl(tty, KDFONTOP, &set);
out:
    free(source); free(target); return result;
}
int display_power(struct display *d, bool on) {
    if (!on) {
        int a = backlight_write(d, "bl_power", 4);
        int b = ioctl(d->fd, FBIOBLANK, FB_BLANK_POWERDOWN);
        return a || b ? -1 : 0;
    }
    if (ioctl(d->fd, FBIOBLANK, FB_BLANK_UNBLANK)) return -1;
    if (backlight_write(d, "brightness", d->brightness)) return -1;
    return backlight_write(d, "bl_power", 0);
}
struct display *display_open(const char *wanted, const char *backlight,
                             const struct display_geometry *geometry) {
    struct display *d = calloc(1, sizeof(*d));
    if (!d) return NULL;
    d->fd = d->tty = -1; d->backlight = backlight;
    unsigned index = 0;
    for (unsigned i = 0; i < 16; i++) {
        char path[64]; snprintf(path, sizeof(path), "/dev/fb%u", i);
        int fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0) continue;
        struct fb_fix_screeninfo info = {0};
        if (!ioctl(fd, FBIOGET_FSCREENINFO, &info) && !strncmp(info.id, wanted, sizeof(info.id))) {
            d->fd = fd; index = i; break;
        }
        close(fd);
    }
    if (d->fd < 0) goto fail;
    struct fb_var_screeninfo pixels = {0};
    if (ioctl(d->fd, FBIOGET_VSCREENINFO, &pixels)) goto fail;
    unsigned mm_width = geometry->width_mm ? geometry->width_mm : pixels.width;
    unsigned mm_height = geometry->height_mm ? geometry->height_mm : pixels.height;
    unsigned width = font_width(pixels.xres, pixels.yres, mm_width, mm_height, geometry->font_width);
    if (!width) { errno = EINVAL; goto fail; }
    if (getenv("CHARGER_DEBUG")) fprintf(stderr, "mobile-charger: panel=%ux%u mm=%ux%u font=%ux%u\n",
        pixels.xres, pixels.yres, mm_width, mm_height, width, width * 2);
    d->tty = open("/dev/tty1", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (d->tty < 0) goto fail;
    int logs = open("/dev/tty2", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (logs < 0) goto fail;
    close(logs);
    /* console=tty2 alone does not redirect printk away from the foreground VT. */
    unsigned char redirect[] = {TIOCL_SETKMSGREDIRECT, 2};
    if (ioctl(d->tty, TIOCLINUX, redirect)) goto fail;
    struct fb_con2fbmap mapping = {.console = 1, .framebuffer = index};
    if (ioctl(d->fd, FBIOPUT_CON2FBMAP, &mapping) || ioctl(d->fd, FBIOGET_CON2FBMAP, &mapping) ||
        mapping.framebuffer != index || ioctl(d->tty, KDSETMODE, KD_TEXT) ||
        ioctl(d->tty, VT_ACTIVATE, 1) || ioctl(d->tty, VT_WAITACTIVE, 1) || set_font(d->tty, width)) goto fail;
    unsigned char palette[48];
    if (ioctl(d->tty, GIO_CMAP, palette)) goto fail;
    memset(palette, 0, 3);
    memset(palette + 7 * 3, 255, 3);
    memset(palette + 15 * 3, 255, 3);
    if (ioctl(d->tty, PIO_CMAP, palette)) goto fail;
    struct winsize size = {0};
    if (ioctl(d->tty, TIOCGWINSZ, &size) || size.ws_col < 40 || size.ws_col > UI_MAX_COLUMNS ||
        size.ws_row < 32 || size.ws_row > UI_MAX_ROWS) goto fail;
    d->columns = size.ws_col; d->rows = size.ws_row;
    int max = (int)read_integer(backlight, "max_brightness", -1);
    if (max <= 0) goto fail;
    d->brightness = max / 4;
    if (!d->brightness) d->brightness = 1;
    /* White foreground, black background, hidden cursor, no line wrapping. */
    static const char setup[] = "\033[0;97;40m\033[?25l\033[?7l\033[2J\033[H";
    if (write_all(d->tty, setup, sizeof(setup) - 1)) goto fail;
    memset(d->previous, ' ', sizeof(d->previous));
    return d;
fail:
    if (getenv("CHARGER_DEBUG")) fprintf(stderr, "mobile-charger: tty setup failed: %s\n", strerror(errno));
    display_close(d); return NULL;
}
unsigned display_width(const struct display *d) { return d->columns; }
unsigned display_height(const struct display *d) { return d->rows; }
int display_show(struct display *d, const struct canvas *c) {
    if (c->width != d->columns || c->height != d->rows) return -1;
    for (unsigned y = 0; y < c->height; y++) {
        unsigned row = y * c->width;
        if (!memcmp(d->previous + row, c->cells + row, c->width)) continue;
        /* Write only the changed span; full-screen pixel copies are unnecessary. */
        unsigned left = 0, right = c->width;
        while (left < right && d->previous[row + left] == c->cells[row + left]) left++;
        while (right > left && d->previous[row + right - 1] == c->cells[row + right - 1]) right--;
        char line[UI_MAX_COLUMNS * 8 + 64];
        int n = snprintf(line, sizeof(line), "\033[%u;%uH", y + 1, left + 1);
        bool solid = false;
        for (unsigned x = left; x < right; x++) {
            bool next = c->cells[row + x] == '#';
            if (next != solid) {
                const char *style = next ? "\033[107m" : "\033[40m";
                size_t len = strlen(style);
                memcpy(line + n, style, len); n += (int)len; solid = next;
            }
            line[n++] = next ? ' ' : c->cells[row + x];
        }
        memcpy(line + n, "\033[40m", 5); n += 5;
        if (write_all(d->tty, line, (size_t)n)) return -1;
        memcpy(d->previous + row, c->cells + row, c->width);
    }
    return 0;
}
void display_close(struct display *d) {
    if (!d) return;
    if (d->tty >= 0) close(d->tty);
    if (d->fd >= 0) close(d->fd);
    free(d);
}
