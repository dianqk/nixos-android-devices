/* SPDX-License-Identifier: MIT */
#include "core.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint_fast64_t refresh_supply(atomic_uint_fast64_t *online_sequence,
                            uint_fast64_t *observed_sequence, struct controller *c) {
    uint_fast64_t sequence = atomic_load(online_sequence);
    if (sequence != *observed_sequence) {
        /* Either process observing restored power cancels both pending timers. */
        c->offline = false;
        c->unknown = false;
        *observed_sequence = sequence;
    }
    return sequence;
}
enum supply_state qualify_supply(enum supply_state state, atomic_uint_fast64_t *online_sequence,
                                 uint_fast64_t *observed_sequence, struct controller *c) {
    if (state == SUPPLY_ONLINE) atomic_fetch_add(online_sequence, 1);
    uint_fast64_t sequence = refresh_supply(online_sequence, observed_sequence, c);
    /* A new provider may report zero before USB discovery. Only an established
     * supply can be lost; unresolved startup retains the UNKNOWN timeout. */
    if (state == SUPPLY_OFFLINE && !sequence) return SUPPLY_UNKNOWN;
    return state;
}

void controller_init(struct controller *c, uint64_t now, bool held) {
    *c = (struct controller){.screen_on = true, .ignore_until_release = held,
                            .touched_at = now, .unknown_at = now, .unknown = true};
}
void controller_key(struct controller *c, int value, uint64_t now) {
    if (c->finished || value == 2) return; /* autorepeat is not a new press */
    if (c->ignore_until_release) {
        if (value == 0) c->ignore_until_release = false;
        return;
    }
    if (value == 1 && !c->pressed) {
        c->pressed = true;
        c->pressed_at = now;
    } else if (value == 0 && c->pressed) {
        /* A delayed event batch can contain both ends of a long hold. */
        c->pressed = false;
        if (now - c->pressed_at >= 2000) c->boot_pending = true;
        else c->screen_on = !c->screen_on;
        c->touched_at = now;
    }
}
enum action controller_step(struct controller *c, enum supply_state online, uint64_t now) {
    if (c->finished) return ACTION_NONE;
    /* Require five seconds of confirmed loss; restored power cancels shutdown.
     * Never turn a pending loss into a normal boot through a simultaneous key. */
    if (online == SUPPLY_OFFLINE) {
        if (!c->offline) { c->offline_at = now; c->offline = true; }
        if (now - c->offline_at >= 5000) { c->finished = true; return ACTION_POWEROFF; }
        return ACTION_NONE;
    }
    c->offline = false;
    if (online == SUPPLY_UNKNOWN) {
        if (!c->unknown) { c->unknown_at = now; c->unknown = true; }
        if (now - c->unknown_at >= 30000) { c->finished = true; return ACTION_POWEROFF; }
    } else c->unknown = false;
    if (c->boot_pending || (c->pressed && now - c->pressed_at >= 2000)) {
        c->finished = true;
        return ACTION_BOOT;
    }
    if (c->screen_on && !c->pressed && now - c->touched_at >= 20000) {
        c->screen_on = false;
        return ACTION_DISPLAY;
    }
    return ACTION_NONE;
}
static bool read_text(const char *dir, const char *attr, char *out, size_t size) {
    char path[4096];
    if (snprintf(path, sizeof(path), "%s/%s", dir, attr) >= (int)sizeof(path)) return false;
    FILE *f = fopen(path, "re");
    if (!f) return false;
    bool ok = fgets(out, (int)size, f) != NULL;
    fclose(f);
    if (ok) out[strcspn(out, "\r\n")] = 0;
    return ok;
}
int64_t read_integer(const char *dir, const char *attr, int64_t fallback) {
    char buf[96], *end;
    if (!read_text(dir, attr, buf, sizeof(buf))) return fallback;
    errno = 0;
    long long value = strtoll(buf, &end, 10);
    if (errno || end == buf || *end) return fallback;
    return value;
}
struct sample read_sample(const char *battery, const char *input, const char *state) {
    struct sample s = {.online = SUPPLY_UNKNOWN, .capacity = -1,
                       .voltage_uv = -1, .current_ua = -1};
    int64_t online = read_integer(input, "online", -1);
    if (online == 0 || online == 1) s.online = (enum supply_state)online;
    /* Never delay confirmed unplug shutdown behind battery/firmware queries. */
    if (s.online != SUPPLY_ONLINE) return s;
    int64_t capacity = read_integer(battery, "capacity", -1);
    if (capacity >= 0 && capacity <= 100) s.capacity = (int)capacity;
    read_text(state, "status", s.status, sizeof(s.status));
    read_text(state, "health", s.health, sizeof(s.health));
    if (s.online == SUPPLY_ONLINE) {
        int64_t v = read_integer(input, "voltage_now", -1);
        int64_t i = read_integer(input, "current_now", -1);
        /* Sanity limits reject malformed telemetry; these never control charging. */
        if (v > 0 && v <= 60000000) s.voltage_uv = v;
        /* Require a valid input voltage to qualify current measurements; some
         * providers return a zero pair when measurement is unavailable. */
        if (s.voltage_uv > 0 && i >= 0 && i <= 20000000) s.current_ua = i;
    }
    return s;
}
bool input_power(const struct sample *s, double *watts) {
    if (s->online != SUPPLY_ONLINE || s->voltage_uv <= 0 || s->current_ua < 0) return false;
    *watts = (double)s->voltage_uv * (double)s->current_ua / 1e12;
    return true;
}
