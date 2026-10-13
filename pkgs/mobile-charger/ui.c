/* SPDX-License-Identifier: MIT */
#include "ui.h"
#include <stdio.h>
#include <string.h>

static void put(struct canvas *c, int x, int y, char ch) {
    if (x >= 0 && y >= 0 && (unsigned)x < c->width && (unsigned)y < c->height)
        c->cells[(unsigned)y * c->width + (unsigned)x] = ch;
}
static void centered(struct canvas *c, int cx, int y, const char *text, unsigned max) {
    unsigned n = (unsigned)strlen(text);
    if (n > max) n = max;
    for (unsigned i = 0; i < n; i++) {
        char ch = text[i];
        /* Firmware strings must not become terminal escape sequences. */
        if (ch < 32 || ch > 126 || ch == '#') ch = '?';
        put(c, cx - (int)n / 2 + (int)i, y, ch);
    }
}
static const unsigned char digits[][7] = {
    {14,17,19,21,25,17,14}, {4,12,4,4,4,4,14}, {14,17,1,2,4,8,31},
    {30,1,1,14,1,1,30}, {2,6,10,18,31,2,2}, {31,16,16,30,1,1,30},
    {14,16,16,30,17,17,14}, {31,1,2,4,8,8,8}, {14,17,17,14,17,17,14},
    {14,17,17,15,1,1,14}, {24,25,2,4,8,19,3}, {0,0,0,31,0,0,0}
};
int render(struct canvas *c, const struct sample *s, const char *message) {
    if (c->width < 40 || c->height < 32 || c->width > UI_MAX_COLUMNS || c->height > UI_MAX_ROWS) return -1;
    memset(c->cells, ' ', c->width * c->height);
    int cx = (int)c->width / 2, top = ((int)c->height - 32) / 2;
    centered(c, cx, top, "BATTERY", c->width - 2);
    char soc[16];
    if (s->capacity >= 0) snprintf(soc, sizeof(soc), "%d%%", s->capacity);
    else snprintf(soc, sizeof(soc), "--%%");
    int n = (int)strlen(soc), left = cx - (n * 6 - 1) / 2;
    for (int i = 0; i < n; i++) {
        int d = soc[i] == '%' ? 10 : soc[i] == '-' ? 11 : soc[i] - '0';
        for (int y = 0; y < 7; y++) for (int x = 0; x < 5; x++)
            if (digits[d][y] & (1U << (4 - x))) put(c, left + i * 6 + x, top + 3 + y, '#');
    }
    /* A 24-cell battery gauge, with a two-cell terminal on its right. */
    int battery_left = cx - 14;
    int filled = s->capacity >= 0 ? s->capacity * 24 / 100 : 0;
    for (int y = 0; y < 4; y++) for (int x = 0; x < 26; x++)
        if (y == 0 || y == 3 || x == 0 || x == 25 || (x <= filled && s->capacity >= 0))
            put(c, battery_left + x, top + 12 + y, '#');
    for (int y = 13; y <= 14; y++) for (int x = 26; x <= 27; x++)
        put(c, battery_left + x, top + y, '#');
    if (s->capacity < 0) put(c, battery_left + 12, top + 13, '?');
    const char *status = s->online == SUPPLY_UNKNOWN ? "Preparing charging" :
                         s->online == SUPPLY_OFFLINE ? "Power lost; shutting down" :
                         !strcmp(s->status, "Full") ? "Fully charged" :
                         !strcmp(s->status, "Charging") ? "Charging" : "External power connected";
    if (s->health[0] && strcmp(s->health, "Good") && strcmp(s->health, "Unknown")) status = s->health;
    centered(c, cx, top + 18, message ? message : status, c->width - 2);
    for (unsigned x = 2; x < c->width - 2; x++) put(c, (int)x, top + 20, '-');
    centered(c, cx, top + 22, "USB INPUT", c->width - 2);
    const char *labels[] = {"VOLTAGE", "CURRENT", "POWER"};
    char values[3][24] = {"-- V", "-- A", "-- W"}; double watts;
    if (s->voltage_uv > 0) snprintf(values[0], sizeof(values[0]), "%.2f V", s->voltage_uv / 1e6);
    if (s->current_ua >= 0) snprintf(values[1], sizeof(values[1]), "%.2f A", s->current_ua / 1e6);
    if (input_power(s, &watts)) snprintf(values[2], sizeof(values[2]), "%.2f W", watts);
    for (int i = 0; i < 3; i++) {
        int x = (int)c->width * (2 * i + 1) / 6;
        centered(c, x, top + 24, labels[i], c->width / 3 - 1);
        centered(c, x, top + 26, values[i], c->width / 3 - 1);
    }
    centered(c, cx, top + 29, "Press power: screen off / on", c->width - 2);
    centered(c, cx, top + 31, "Hold power 2 seconds: start", c->width - 2);
    return 0;
}
int write_preview(const char *path, const struct sample *s, unsigned columns, unsigned rows) {
    struct canvas c = {.width = columns, .height = rows};
    if (render(&c, s, NULL)) return -1;
    FILE *f = fopen(path, "we");
    if (!f) return -1;
    bool ok = true;
    for (unsigned y = 0; y < c.height; y++) {
        if (fwrite(c.cells + y * c.width, 1, c.width, f) != c.width || fputc('\n', f) == EOF) { ok = false; break; }
    }
    if (fclose(f)) ok = false;
    return ok ? 0 : -1;
}
