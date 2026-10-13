/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "core.h"
#include <assert.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

static void put(const char *dir, const char *name, const char *value) {
    char path[512]; snprintf(path, sizeof(path), "%s/%s", dir, name);
    FILE *f = fopen(path, "w"); assert(f); fputs(value, f); assert(!fclose(f));
}
int main(void) {
    struct controller c;
    controller_init(&c, 0, false);
    assert(controller_step(&c, SUPPLY_UNKNOWN, 29999) == ACTION_DISPLAY);
    assert(controller_step(&c, SUPPLY_UNKNOWN, 30000) == ACTION_POWEROFF);
    controller_init(&c, 0, false);
    controller_key(&c, 1, 100); controller_key(&c, 2, 150);
    assert(controller_step(&c, SUPPLY_ONLINE, 2099) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_ONLINE, 2100) == ACTION_BOOT);
    assert(controller_step(&c, SUPPLY_ONLINE, 3100) == ACTION_NONE);
    controller_init(&c, 0, false);
    controller_key(&c, 1, 100); controller_key(&c, 0, 2200);
    assert(c.screen_on && controller_step(&c, SUPPLY_ONLINE, 2201) == ACTION_BOOT);
    controller_init(&c, 0, false);
    controller_key(&c, 1, 100); controller_key(&c, 0, 200);
    assert(controller_step(&c, SUPPLY_ONLINE, 2200) == ACTION_NONE && !c.screen_on);
    controller_init(&c, 0, false);
    controller_key(&c, 1, 100); controller_key(&c, 0, 200);
    assert(!c.screen_on);
    assert(controller_step(&c, SUPPLY_OFFLINE, 201) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 5200) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 5201) == ACTION_POWEROFF);
    controller_init(&c, 0, false);
    controller_key(&c, 1, 0);
    assert(controller_step(&c, SUPPLY_OFFLINE, 2000) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 7000) == ACTION_POWEROFF);
    controller_init(&c, 0, true);
    controller_key(&c, 1, 10);
    assert(controller_step(&c, SUPPLY_ONLINE, 2001) == ACTION_NONE);
    controller_key(&c, 0, 3000); assert(c.screen_on);
    controller_key(&c, 1, 3010); controller_key(&c, 0, 3110); assert(!c.screen_on);
    controller_key(&c, 1, 3200); controller_key(&c, 0, 3300); assert(c.screen_on);
    assert(controller_step(&c, SUPPLY_UNKNOWN, 3301) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_ONLINE, 3302) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 3303) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_ONLINE, 8302) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 8303) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_UNKNOWN, 9000) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 10000) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 14999) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 15000) == ACTION_POWEROFF);
    atomic_uint_fast64_t *sequence = mmap(NULL, sizeof(*sequence), PROT_READ | PROT_WRITE,
                                         MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    assert(sequence != MAP_FAILED); atomic_init(sequence, 0);
    uint_fast64_t observed = 0;
    controller_init(&c, 0, false);
    assert(qualify_supply(SUPPLY_OFFLINE, sequence, &observed, &c) == SUPPLY_UNKNOWN);
    assert(controller_step(&c, qualify_supply(SUPPLY_OFFLINE, sequence, &observed, &c), 30000) == ACTION_POWEROFF);
    controller_init(&c, 0, false);
    assert(qualify_supply(SUPPLY_ONLINE, sequence, &observed, &c) == SUPPLY_ONLINE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 1) == ACTION_NONE);
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        assert(qualify_supply(SUPPLY_ONLINE, sequence, &observed, &c) == SUPPLY_ONLINE);
        _exit(0);
    }
    int status; assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(qualify_supply(SUPPLY_OFFLINE, sequence, &observed, &c) == SUPPLY_OFFLINE);
    assert(!c.offline); /* another process saw restoration: old deadline cancelled */
    assert(controller_step(&c, SUPPLY_OFFLINE, 5001) == ACTION_NONE);
    assert(controller_step(&c, SUPPLY_OFFLINE, 10001) == ACTION_POWEROFF);
    assert(!munmap(sequence, sizeof(*sequence)));
    char dir[] = "/tmp/mobile-charger-test-XXXXXX"; assert(mkdtemp(dir));
    put(dir, "online", "1\n"); put(dir, "capacity", "67\n");
    put(dir, "voltage_now", "9020000\n"); put(dir, "current_now", "2430000\n");
    put(dir, "power_now", "64000000\n"); /* deliberately bogus, must never be consumed */
    struct sample s = read_sample(dir, dir, dir); double watts;
    assert(s.capacity == 67 && input_power(&s, &watts)); assert(fabs(watts - 21.9186) < 0.00001);
    put(dir, "current_now", "0\n"); s = read_sample(dir, dir, dir);
    assert(input_power(&s, &watts) && watts == 0);
    char state[] = "/tmp/mobile-charger-state-XXXXXX"; assert(mkdtemp(state));
    put(dir, "status", "Discharging\n"); put(state, "status", "Full\n"); put(state, "health", "Good\n");
    put(dir, "voltage_now", "0\n"); s = read_sample(dir, dir, state);
    assert(s.online == SUPPLY_ONLINE && s.capacity == 67 && !strcmp(s.status, "Full") && !strcmp(s.health, "Good"));
    assert(s.voltage_uv == -1 && s.current_ua == -1 && !input_power(&s, &watts));
    char path[512];
    snprintf(path, sizeof(path), "%s/status", state); assert(!unlink(path));
    snprintf(path, sizeof(path), "%s/health", state); assert(!unlink(path)); assert(!rmdir(state));
    put(dir, "voltage_now", "9020000\n");
    put(dir, "current_now", "-5\n"); s = read_sample(dir, dir, dir); assert(!input_power(&s, &watts));
    put(dir, "capacity", "101\n"); put(dir, "online", "1junk\n");
    s = read_sample(dir, dir, dir); assert(s.online == SUPPLY_UNKNOWN && s.capacity == -1);
    put(dir, "online", "0\n"); s = read_sample(dir, dir, dir);
    assert(s.online == SUPPLY_OFFLINE && s.voltage_uv == -1 && !input_power(&s, &watts));
    const char *names[] = {"online", "capacity", "voltage_now", "current_now", "power_now", "status"};
    for (unsigned i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        char path[512]; snprintf(path, sizeof(path), "%s/%s", dir, names[i]); assert(!unlink(path));
    }
    assert(!rmdir(dir));
    puts("mobile-charger: controller and telemetry checks passed");
}
