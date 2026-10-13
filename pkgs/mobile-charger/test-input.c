/* SPDX-License-Identifier: MIT */
/* Exercise the real event-queue consumer, including delayed delivery. */
#define main charger_program_main
#include "main.c"
#undef main
#include <assert.h>

static void event(int fd, unsigned type, unsigned code, int value, unsigned ms) {
    struct input_event e = {.type = type, .code = code, .value = value,
                           .time = {.tv_sec = ms / 1000, .tv_usec = (ms % 1000) * 1000}};
    assert(write(fd, &e, sizeof(e)) == sizeof(e));
}
int main(void) {
    int fds[2]; assert(!pipe2(fds, O_NONBLOCK | O_CLOEXEC));
    struct controller c; controller_init(&c, 0, false);
    event(fds[1], EV_KEY, KEY_POWER, 1, 100);
    assert(drain_input(&fds[0], &c) && c.pressed);
    event(fds[1], EV_KEY, KEY_POWER, 0, 200);
    assert(drain_input(&fds[0], &c));
    assert(controller_step(&c, SUPPLY_ONLINE, 2200) == ACTION_NONE && !c.screen_on);
    event(fds[1], EV_KEY, KEY_POWER, 1, 2300);
    event(fds[1], EV_KEY, KEY_POWER, 2, 2400);
    event(fds[1], EV_KEY, KEY_POWER, 0, 4400);
    assert(drain_input(&fds[0], &c));
    assert(controller_step(&c, SUPPLY_ONLINE, 4401) == ACTION_BOOT);
    controller_init(&c, 0, false);
    event(fds[1], EV_KEY, KEY_POWER, 1, 100);
    assert(drain_input(&fds[0], &c));
    event(fds[1], EV_SYN, SYN_DROPPED, 0, 150);
    event(fds[1], EV_KEY, KEY_POWER, 0, 200);
    event(fds[1], EV_SYN, SYN_REPORT, 0, 210);
    assert(drain_input(&fds[0], &c) && fds[0] == -1);
    assert(controller_step(&c, SUPPLY_ONLINE, 2200) == ACTION_NONE);
    close(fds[1]);
    puts("mobile-charger: delayed evdev queue and sync-loss checks passed");
}
