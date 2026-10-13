/* SPDX-License-Identifier: MIT */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

enum supply_state { SUPPLY_UNKNOWN = -1, SUPPLY_OFFLINE = 0, SUPPLY_ONLINE = 1 };
enum action { ACTION_NONE, ACTION_DISPLAY, ACTION_BOOT, ACTION_POWEROFF };
struct sample {
    enum supply_state online;
    int capacity; /* -1 means unavailable */
    int64_t voltage_uv, current_ua; /* -1 means unavailable; input domain only */
    char status[64], health[64];
};
struct controller {
    bool screen_on, pressed, ignore_until_release, finished, boot_pending;
    uint64_t pressed_at, touched_at, unknown_at;
    bool unknown;
    bool offline;
    uint64_t offline_at;
};
void controller_init(struct controller *, uint64_t now, bool initially_pressed);
void controller_key(struct controller *, int value, uint64_t now);
enum action controller_step(struct controller *, enum supply_state, uint64_t now);
int64_t read_integer(const char *directory, const char *attribute, int64_t fallback);
struct sample read_sample(const char *battery, const char *input, const char *state);
bool input_power(const struct sample *, double *watts);
enum supply_state qualify_supply(enum supply_state, atomic_uint_fast64_t *online_sequence,
                                 uint_fast64_t *observed_sequence, struct controller *);
uint_fast64_t refresh_supply(atomic_uint_fast64_t *, uint_fast64_t *, struct controller *);
