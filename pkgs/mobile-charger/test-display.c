/* SPDX-License-Identifier: MIT */
/* Exercise actual VT output through an in-memory file, without hardware ioctls. */
#include "display.c"
#include <assert.h>
#include <sys/mman.h>
#include <sys/stat.h>

static void check(unsigned columns, unsigned rows, int capacity) {
    struct canvas c = {.width = columns, .height = rows};
    struct sample s = {.online = SUPPLY_ONLINE, .capacity = capacity,
                       .voltage_uv = 9020000, .current_ua = 2430000, .status = "Charging"};
    assert(!render(&c, &s, NULL));
    struct display d = {.columns = columns, .rows = rows};
    memset(d.previous, ' ', sizeof(d.previous));
    d.tty = memfd_create("charger-vt-test", MFD_CLOEXEC); assert(d.tty >= 0);
    assert(!display_show(&d, &c));
    off_t size = lseek(d.tty, 0, SEEK_CUR); assert(size > 0 && size < 10000);
    char data[10000], screen[UI_MAX_COLUMNS * UI_MAX_ROWS];
    assert(pread(d.tty, data, (size_t)size, 0) == size);
    memset(screen, ' ', sizeof(screen));
    unsigned x = 0, y = 0; bool solid = false;
    for (off_t i = 0; i < size;) {
        if (data[i] == '\033') {
            assert(i + 2 < size && data[i + 1] == '['); i += 2;
            unsigned a = 0, b = 0;
            while (i < size && data[i] >= '0' && data[i] <= '9') a = a * 10 + (unsigned)(data[i++] - '0');
            assert(i < size);
            if (data[i] == ';') {
                i++;
                while (i < size && data[i] >= '0' && data[i] <= '9') b = b * 10 + (unsigned)(data[i++] - '0');
                assert(i < size && data[i++] == 'H' && a && b); y = a - 1; x = b - 1;
            } else {
                assert(data[i++] == 'm' && (a == 40 || a == 107)); solid = a == 107;
            }
        } else {
            assert(x < columns && y < rows && data[i] >= 32 && data[i] <= 126);
            screen[y * columns + x++] = solid ? '#' : data[i]; i++;
        }
    }
    assert(!memcmp(screen, c.cells, columns * rows));
    assert(!display_show(&d, &c) && lseek(d.tty, 0, SEEK_CUR) == size);
    s.voltage_uv = 12020000; assert(!render(&c, &s, NULL));
    assert(!display_show(&d, &c));
    off_t delta = lseek(d.tty, 0, SEEK_CUR) - size;
    /* Voltage also changes calculated power, on the same numeric row. */
    assert(delta > 0 && delta <= (off_t)columns + 32);
    strcpy(s.health, "bad\033[2Jstatus"); assert(!render(&c, &s, NULL));
    for (unsigned i = 0; i < columns * rows; i++) assert(c.cells[i] >= 32 && c.cells[i] <= 126);
    close(d.tty);
}
int main(void) {
    assert(font_width(1600, 2560, 118, 190, 32) == 32);
    assert(font_width(1600, 2560, 118, 190, 0) == 32);
    assert(font_width(1080, 2160, 68, 136, 0) == 24);
    assert(font_width(1080, 2160, 0, 0, 0) == 24);
    assert(font_width(1080, 2160, UINT32_MAX, UINT32_MAX, 0) == 24);
    assert(font_width(1080, 2160, 1, 500, 0) == 24);
    assert(font_width(720, 1280, 0, 0, 0) == 16);
    assert(font_width(1080, 2160, 68, 136, 32) == 0);
    assert(font_width(319, 512, 0, 0, 0) == 0);
    assert(font_width(UINT32_MAX, UINT32_MAX, 0, 0, 0) == 0);
    assert(font_width(3840, 2160, 0, 0, 0) == 32);
    check(45, 45, 0); check(45, 45, 67); check(45, 45, 100); check(45, 45, -1);
    check(40, 32, 0); check(50, 40, 50); check(50, 40, 67);
    check(50, 40, 100); check(128, 128, -1);
    struct canvas c = {.width = 39, .height = 32}; struct sample s = {0};
    assert(render(&c, &s, NULL) == -1);
    puts("mobile-charger: VT layout, escaping and changed-span checks passed");
}
