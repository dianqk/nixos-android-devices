/* SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include "core.h"
#include "display.h"
#include "ui.h"
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/netlink.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}
static int input_open(const char *wanted, bool *held) {
    for (int i = 0; i < 64; i++) {
        char path[64], name[256] = {0};
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0 && !strcmp(name, wanted)) {
            unsigned char keys[KEY_MAX / 8 + 1] = {0};
            if (ioctl(fd, EVIOCGKEY(sizeof(keys)), keys) < 0) { close(fd); return -1; }
            *held = (keys[KEY_POWER / 8] & (1U << (KEY_POWER % 8))) != 0;
            int clock = CLOCK_MONOTONIC;
            if (ioctl(fd, EVIOCSCLOCKID, &clock) < 0) { close(fd); return -1; }
            return fd;
        }
        close(fd);
    }
    return -1;
}
static int uevent_open(void) {
    int fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, NETLINK_KOBJECT_UEVENT);
    if (fd < 0) return -1;
    struct sockaddr_nl addr = {.nl_family = AF_NETLINK, .nl_pid = (unsigned)getpid(), .nl_groups = 1};
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr))) { close(fd); return -1; }
    return fd;
}
static bool charger_cmdline(void) {
    FILE *f = fopen("/proc/cmdline", "re");
    if (!f) return false;
    char token[4096]; bool found = false;
    while (fscanf(f, "%4095s", token) == 1)
        if (!strcmp(token, "android_charger=1")) found = true;
    fclose(f);
    return found;
}
static void power_action(enum action action, const char *reason) {
    fprintf(stderr, "mobile-charger: %s\n", action == ACTION_BOOT ? "boot requested" : "power off requested");
    fprintf(stderr, "mobile-charger: reason=%s pid=%ld\n", reason, (long)getpid());
    sync(); /* no persistent filesystems are mounted in the charging initramfs */
    reboot(action == ACTION_BOOT ? RB_AUTOBOOT : RB_POWER_OFF);
    perror("mobile-charger: reboot syscall");
    exit(1); /* PID1 supervisor powers off on any application failure */
}
static void watch_power(const char *input, atomic_uint_fast64_t *online_sequence) {
    int events = uevent_open();
    struct controller c;
    controller_init(&c, now_ms(), false);
    int64_t previous = -2;
    uint_fast64_t observed_sequence = 0;
    for (;;) {
        int64_t value = read_integer(input, "online", -1);
        if (getenv("CHARGER_DEBUG") && value != previous)
            fprintf(stderr, "mobile-charger: watcher online=%lld\n", (long long)value);
        previous = value;
        enum supply_state online = value == 0 ? SUPPLY_OFFLINE : value == 1 ? SUPPLY_ONLINE : SUPPLY_UNKNOWN;
        online = qualify_supply(online, online_sequence, &observed_sequence, &c);
        if (controller_step(&c, online, now_ms()) == ACTION_POWEROFF) power_action(ACTION_POWEROFF, "supply monitor");
        struct pollfd fd = {.fd = events, .events = POLLIN};
        if (poll(&fd, 1, 1000) < 0 && errno != EINTR) power_action(ACTION_POWEROFF, "supply event poll");
        if (fd.revents & POLLIN) {
            char buf[8192];
            for (int i = 0; i < 64 && recv(events, buf, sizeof(buf), 0) > 0; i++) {}
        }
    }
}
static bool drain_input(int *fd, struct controller *control) {
    if (*fd < 0) return false;
    bool changed = false, dropped = false;
    struct input_event ev;
    ssize_t n;
    while ((n = read(*fd, &ev, sizeof(ev))) == sizeof(ev)) {
        if (ev.type == EV_SYN && ev.code == SYN_DROPPED) {
            control->pressed = false;
            control->boot_pending = false;
            control->ignore_until_release = true;
            dropped = true;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT && dropped) {
            close(*fd); *fd = -1;
            return true; /* reopen and query EVIOCGKEY before accepting another press */
        } else if (!dropped && ev.type == EV_KEY && ev.code == KEY_POWER) {
            uint64_t at = (uint64_t)ev.time.tv_sec * 1000 + (uint64_t)ev.time.tv_usec / 1000;
            controller_key(control, ev.value, at);
            changed = true;
        }
    }
    if (dropped || n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) {
        close(*fd); *fd = -1; control->pressed = false; control->boot_pending = false;
    }
    return changed;
}
static bool parse_unsigned(const char *text, unsigned max, unsigned *out) {
    char *end;
    if (!text[0] || text[0] < '0' || text[0] > '9') return false;
    errno = 0;
    unsigned long value = strtoul(text, &end, 10);
    if (errno || *end || value > max) return false;
    *out = (unsigned)value;
    return true;
}
int main(int argc, char **argv) {
    if ((argc == 4 || argc == 6) && !strcmp(argv[1], "--preview")) {
        unsigned columns = 50, rows = 40;
        if (argc == 6 && (!parse_unsigned(argv[4], UI_MAX_COLUMNS, &columns) ||
                          !parse_unsigned(argv[5], UI_MAX_ROWS, &rows))) return 2;
        struct sample s = {.online = SUPPLY_ONLINE, .capacity = 67,
                           .voltage_uv = 9020000, .current_ua = 2430000, .status = "Charging", .health = "Good"};
        if (!strcmp(argv[3], "full")) { s.capacity = 100; s.current_ua = 0; strcpy(s.status, "Full"); }
        else if (!strcmp(argv[3], "unknown")) s = (struct sample){.online = SUPPLY_UNKNOWN, .capacity = -1, .voltage_uv = -1, .current_ua = -1};
        else if (strcmp(argv[3], "charging")) return 2;
        return write_preview(argv[2], &s, columns, rows) ? 1 : 0;
    }
    if (argc != 10) {
        fprintf(stderr, "Usage: mobile-charger BATTERY_SYSFS INPUT_SYSFS INPUT_NAME FRAMEBUFFER_ID BACKLIGHT_SYSFS STATE_SYSFS WIDTH_MM HEIGHT_MM FONT_WIDTH\n"
                        "       mobile-charger --preview FILE.txt charging|full|unknown [COLUMNS ROWS]\n");
        return 2;
    }
    struct display_geometry geometry = {0};
    if (!parse_unsigned(argv[7], 2000, &geometry.width_mm) ||
        !parse_unsigned(argv[8], 2000, &geometry.height_mm) ||
        !parse_unsigned(argv[9], 64, &geometry.font_width) ||
        (!!geometry.width_mm != !!geometry.height_mm) ||
        (geometry.font_width && geometry.font_width % 8)) return 2;
    if (!charger_cmdline()) { fprintf(stderr, "mobile-charger: dedicated charger boot required\n"); return 2; }
    bool debug = getenv("CHARGER_DEBUG") != NULL;
    if (debug) fprintf(stderr, "mobile-charger: starting dedicated RAM charging environment\n");
    /* Supply-loss handling must continue even if rendering or a modeset stalls. */
    _Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "shared supply latch must be lock-free");
    atomic_uint_fast64_t *online_sequence = mmap(NULL, sizeof(*online_sequence), PROT_READ | PROT_WRITE,
                                    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (online_sequence == MAP_FAILED) return 1;
    atomic_init(online_sequence, 0);
    pid_t watcher = fork();
    if (watcher < 0) return 1;
    if (!watcher) { watch_power(argv[2], online_sequence); _exit(1); }
    uint64_t started = now_ms(), next_sample = started, next_supply = started, next_open = started;
    uint_fast64_t observed_sequence = 0;
    struct controller control;
    controller_init(&control, started, false);
    struct sample sample = {.online = SUPPLY_UNKNOWN, .capacity = -1, .voltage_uv = -1, .current_ua = -1};
    struct display *display = NULL;
    struct canvas canvas = {0};
    int input = -1, events = uevent_open();
    bool shown = false, power_known = false, rendered = false;
    for (;;) {
        uint64_t now = now_ms();
        if (waitpid(watcher, NULL, WNOHANG) != 0) power_action(ACTION_POWEROFF, "supply monitor exited");
        bool dirty = false;
        if (control.screen_on && now >= next_sample) {
            struct sample fresh = read_sample(argv[1], argv[2], argv[6]);
            fresh.online = qualify_supply(fresh.online, online_sequence, &observed_sequence, &control);
            dirty = memcmp(&sample, &fresh, sizeof(sample)) != 0;
            sample = fresh;
            next_sample = now_ms() + 5000;
            next_supply = now_ms() + 1000;
            if (debug) fprintf(stderr, "mobile-charger: online=%d capacity=%d input_uv=%lld input_ua=%lld status=%s\n",
                sample.online, sample.capacity, (long long)sample.voltage_uv, (long long)sample.current_ua, sample.status);
        } else if (now >= next_supply) {
            /* Supply safety is independent of the slower display telemetry. */
            int64_t value = read_integer(argv[2], "online", -1);
            enum supply_state online = value == 0 ? SUPPLY_OFFLINE : value == 1 ? SUPPLY_ONLINE : SUPPLY_UNKNOWN;
            online = qualify_supply(online, online_sequence, &observed_sequence, &control);
            dirty = online != sample.online;
            sample.online = online;
            if (online != SUPPLY_ONLINE) sample.voltage_uv = sample.current_ua = -1;
            if (dirty && online == SUPPLY_ONLINE) next_sample = 0;
            next_supply = now_ms() + 1000;
        }
        /* Consume timestamped releases/SYN_DROPPED after potentially blocking
         * firmware reads, BEFORE applying a wall-clock long-press deadline. */
        bool was_on = control.screen_on;
        if (drain_input(&input, &control)) rendered = false;
        if (!was_on && control.screen_on) next_sample = 0;
        now = now_ms();
        refresh_supply(online_sequence, &observed_sequence, &control);
        enum action action = controller_step(&control, sample.online, now);
        if (action == ACTION_BOOT || action == ACTION_POWEROFF) power_action(action, "main controller");
        if (now >= next_open && (!display || input < 0)) {
            if (input < 0) {
                bool held = false;
                input = input_open(argv[3], &held);
                if (input >= 0) control.ignore_until_release = held;
            }
            if (!display) {
                display = display_open(argv[4], argv[5], &geometry);
                if (display) {
                    canvas.width = display_width(display); canvas.height = display_height(display);
                    dirty = true;
                }
            }
            next_open = now + 1000;
            if ((!display || input < 0) && now - started >= 30000) power_action(ACTION_POWEROFF, "display or input unavailable");
        }
        if (display && control.screen_on && (dirty || !shown || !rendered)) {
            if (render(&canvas, &sample, control.pressed ? "Hold to start..." : NULL) || display_show(display, &canvas))
                power_action(ACTION_POWEROFF, "render or framebuffer copy");
            rendered = true;
        }
        if (display && (!power_known || shown != control.screen_on)) {
            if (display_power(display, control.screen_on)) power_action(ACTION_POWEROFF, "display power transition");
            shown = control.screen_on;
            power_known = true;
            if (debug) fprintf(stderr, "mobile-charger: display=%s\n", shown ? "on" : "off");
        }
        struct pollfd fds[] = {{.fd = input, .events = POLLIN}, {.fd = events, .events = POLLIN}};
        if (poll(fds, 2, 100) < 0 && errno != EINTR) power_action(ACTION_POWEROFF, "main event poll");
        if (fds[1].revents & POLLIN) {
            char buf[8192];
            for (int i = 0; i < 64 && recv(events, buf, sizeof(buf), 0) > 0; i++) {}
            next_supply = 0; /* Events refresh supply, not all telemetry properties. */
        }
        if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
            close(input); input = -1; control.pressed = false; control.boot_pending = false;
        }
    }
}
