/* SPDX-License-Identifier: MIT
 * Filled by the Python runner with actual patched driver and DRM functions.
 * MMIO, regulators, DCS transport and atomic dispatch are fakes. Mutexes assert
 * against recursive acquisition; these are deterministic, single-thread tests.
 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stddef.h>
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint64_t u64;
#define BIT(n) (1U << (n))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define container_of(p,t,m) ((t *)((char *)(p) - offsetof(t,m)))
#define READ_ONCE(x) (x)
#define IS_ERR(x) ((uintptr_t)(x) >= (uintptr_t)-4095)
#define PTR_ERR(x) ((int)(intptr_t)(x))
#define ERR_PTR(x) ((void *)(intptr_t)(x))
#define DRM_MODE_MATCH_TIMINGS 1
#define DRM_MODE_MATCH_CLOCK 2
#define DRM_MODE_MATCH_FLAGS 4
#define DRM_MODE_TYPE_DRIVER 1
#define DRM_MODE_TYPE_PREFERRED 2
#define MIPI_DSI_MODE_LPM BIT(1)
#define dev_err(...) ((void)0)
#define dev_warn(...) ((void)0)
#define dev_info(...) ((void)0)
#define DRM_DEV_INFO(...) ((void)0)
#define pr_err(...) ((void)0)
#define DBG(...) ((void)0)
#define msleep(x) ((void)(x))
#define usleep_range(a,b) ((void)0)
#define gpiod_set_value_cansleep(a,b) ((void)0)
struct mutex { bool held; };
static void mutex_lock(struct mutex *m) { assert(!m->held); m->held = true; }
static void mutex_unlock(struct mutex *m) { assert(m->held); m->held = false; }
#define lockdep_assert_held(m) assert((m)->held)
struct device { int unused; };
struct work_struct { void (*func)(struct work_struct *); bool pending; };
#define INIT_WORK(w,f) do { (w)->func = (f); (w)->pending = false; } while (0)
static bool schedule_work(struct work_struct *w) { bool old = w->pending; w->pending = true; return !old; }
static void cancel_work_sync(struct work_struct *w) { w->pending = false; }
struct gpio_desc { int unused; };
struct regulator { int refs, index; };
struct regulator_bulk_data { const char *supply; struct regulator *consumer; };
struct drm_dsc_config { int unused; };
struct drm_dsc_picture_parameter_set { int unused; };
struct drm_display_mode {
    int clock, hdisplay, hsync_start, hsync_end, htotal;
    int vdisplay, vsync_start, vsync_end, vtotal, width_mm, height_mm, type, flags;
};
struct drm_crtc;
struct drm_crtc_state {
    struct drm_crtc *crtc;
    bool active, enable, self_refresh_active, vrr_enabled;
    struct drm_display_mode mode;
    void *mode_blob, *degamma_lut, *ctm, *gamma_lut, *commit, *event;
    bool mode_changed, active_changed, planes_changed, connectors_changed;
    bool color_mgmt_changed, zpos_changed, async_flip;
};
struct drm_crtc { struct drm_crtc_state *state; };
struct drm_device { struct { struct mutex connection_mutex; } mode_config; };
struct drm_connector_state { struct drm_crtc *crtc; };
struct drm_connector {
    struct drm_device *dev;
    struct drm_connector_state *state;
    int refs;
    struct { unsigned width_mm, height_mm, bpc; } display_info;
};
struct drm_modeset_acquire_ctx { int unused; };
struct drm_atomic_commit {
    struct drm_modeset_acquire_ctx *acquire_ctx;
    struct drm_crtc_state old, new;
    struct drm_crtc *crtc;
    bool allow_modeset, old_bound, new_bound;
};
struct drm_panel;
struct drm_panel_funcs {
    int (*prepare)(struct drm_panel *), (*enable)(struct drm_panel *);
    int (*disable)(struct drm_panel *), (*unprepare)(struct drm_panel *);
    int (*idle_enter)(struct drm_panel *), (*idle_exit)(struct drm_panel *);
};
struct backlight_device {
    struct mutex update_lock;
    struct { int brightness; bool blank; } props;
    void *data;
};
struct drm_panel {
    bool prepared, enabled;
    const struct drm_panel_funcs *funcs;
    struct mutex follower_lock;
    struct backlight_device *backlight;
    struct device *dev;
};
struct drm_panel_follower;
struct drm_panel_follower_funcs {
    int (*panel_prepared)(struct drm_panel_follower *);
    int (*panel_unpreparing)(struct drm_panel_follower *);
    int (*panel_enabled)(struct drm_panel_follower *);
    int (*panel_disabling)(struct drm_panel_follower *);
};
struct drm_panel_follower { const struct drm_panel_follower_funcs *funcs; };
/* No followers: retain actual core wrapper logic and lock/backlight operations. */
#define list_for_each_entry(pos,head,member) for ((pos) = NULL; (pos); (pos) = NULL)
struct drm_bridge { void *encoder; };
struct drm_encoder { int unused; };
struct panel_bridge { struct drm_bridge bridge; struct drm_panel *panel; };
struct mipi_dsi_device { struct device dev; unsigned long mode_flags; };
struct mipi_dsi_msg { unsigned channel, type, flags; size_t tx_len; const void *tx_buf; };
struct mipi_dsi_cmd { struct mipi_dsi_msg msg; unsigned delay_ms; };
struct mipi_dsi_multi_context { struct mipi_dsi_device *dsi; int accum_err; };
/* @PANEL_STRUCT@ */
/* @PANEL_MODES@ */
#include "panel-xiaomi-l2s-runtime.h"
static unsigned idle_hz = 1;
static struct l2s_panel panel;
static struct mipi_dsi_device device;
static struct regulator regs[3];
static struct backlight_device backlight;
static struct panel_bridge bridge;
static struct drm_device drm;
static struct drm_crtc crtc;
static struct drm_connector_state connector_state;
static struct drm_connector connector;
static struct drm_atomic_commit current;
static int sequence_error, init_error, display_on_error, pps_error;
static int brightness_error, off_error, sleep_error;
static int enable_fail = -1, disable_fail = -1, underflows, wire_brightness, physical_hz;
static int backlight_enables, wake_commits, lock_error, backoffs, alloc_fail;
static unsigned packet_writes;
static bool unplugged;
static int dev_entries;
static void drm_connector_get(struct drm_connector *c) { assert(c->refs > 0); c->refs++; }
static void drm_connector_put(struct drm_connector *c) { assert(c->refs > 1); c->refs--; }
static bool drm_dev_enter(struct drm_device *d, int *idx) {
    if (unplugged) return false;
    dev_entries++; *idx = 1; return true;
}
static void drm_dev_exit(int idx) { assert(idx == 1 && dev_entries == 1); dev_entries--; }
static struct l2s_panel *to_l2s_panel(struct drm_panel *p) { return container_of(p, struct l2s_panel, panel); }
static struct panel_bridge *drm_bridge_to_panel_bridge(struct drm_bridge *b) { return container_of(b, struct panel_bridge, bridge); }
static unsigned drm_mode_vrefresh(const struct drm_display_mode *m) {
    long long total = (long long)m->htotal * m->vtotal;
    return total ? ((long long)m->clock * 1000 + total / 2) / total : 0;
}
static bool drm_mode_match(const struct drm_display_mode *a, const struct drm_display_mode *b, int flags) {
    return a->clock == b->clock && a->hdisplay == b->hdisplay && a->vdisplay == b->vdisplay;
}
static struct drm_display_mode *drm_mode_duplicate(struct drm_device *d, const struct drm_display_mode *mode) {
    struct drm_display_mode *copy = malloc(sizeof(*copy));
    assert(copy); *copy = *mode; return copy;
}
static void drm_mode_set_name(struct drm_display_mode *mode) {}
static void drm_mode_probed_add(struct drm_connector *c, struct drm_display_mode *mode) { free(mode); }
static int regulator_enable(struct regulator *r) {
    if (r->index == enable_fail) return -EIO;
    assert(r->refs == 0); r->refs++; return 0;
}
static int regulator_disable(struct regulator *r) {
    if (r->refs == 0) { underflows++; return -EIO; }
    if (r->index == disable_fail) return -EIO;
    r->refs--; return 0;
}
static void fake_write(struct mipi_dsi_multi_context *c, const u8 *bytes, size_t len) {
    if (c->accum_err) return;
    packet_writes++;
    if (bytes[0] == 0x9e && init_error) { c->accum_err = init_error; return; }
    if (bytes[0] == 0x51 && len == 3) wire_brightness = (bytes[1] << 8) | bytes[2];
    if (bytes[0] == 0x60 && len == 2) physical_hz = bytes[1] == 8 ? 90 : 120 / (bytes[1] + 1);
}
#define mipi_dsi_dcs_write_seq_multi(c,...) fake_write(c,(const u8[]){__VA_ARGS__},sizeof((const u8[]){__VA_ARGS__}))
#define mipi_dsi_dcs_write_buffer_multi(c,b,n) fake_write(c,b,n)
#define mipi_dsi_msleep(c,x) ((void)0)
#define mipi_dsi_dcs_set_display_on_multi(c) do { if (!(c)->accum_err) (c)->accum_err = display_on_error; } while (0)
#define drm_dsc_pps_payload_pack(p,d) ((void)0)
#define mipi_dsi_picture_parameter_set_multi(c,p) do { (void)(p); if (!(c)->accum_err) (c)->accum_err = pps_error; } while (0)
static int mipi_dsi_dcs_enter_sleep_mode(struct mipi_dsi_device *d) { return sleep_error; }
static int mipi_dsi_dcs_set_display_off(struct mipi_dsi_device *d) { return off_error; }
static int mipi_dsi_dcs_set_display_brightness_large(struct mipi_dsi_device *d, u16 brightness) {
    assert(!(d->mode_flags & MIPI_DSI_MODE_LPM));
    if (brightness_error) return brightness_error;
    wire_brightness = brightness; return 0;
}
static int mipi_dsi_transfer_sequence(struct mipi_dsi_device *d, const struct mipi_dsi_cmd *cmds, size_t count) {
    struct mipi_dsi_multi_context c = { .dsi = d };
    if (sequence_error) return sequence_error;
    for (size_t i = 0; i < count; i++) fake_write(&c, cmds[i].msg.tx_buf, cmds[i].msg.tx_len);
    /* Low-rate/120 Hz tables select DDIC rate via indexed BD registers;
     * tag the selected table rather than pretending to simulate the DDIC.
     */
    if (cmds == l2s_switch_120) physical_hz = 120;
    if (cmds == l2s_switch_1) physical_hz = 1;
    if (cmds == l2s_switch_10) physical_hz = 10;
    return c.accum_err;
}
static bool backlight_is_blank(const struct backlight_device *b) { return b->props.blank; }
static int backlight_get_brightness(const struct backlight_device *b) { return b->props.blank ? 0 : b->props.brightness; }
static void *bl_get_data(struct backlight_device *b) { return b->data; }
static bool drm_atomic_crtc_effectively_active(struct drm_crtc_state *s) { return s->active || s->self_refresh_active; }
static void drm_property_blob_get(void *p) { assert(p); }
/* @DUPLICATE@ */
static struct drm_crtc *drm_atomic_get_new_crtc_for_encoder(struct drm_atomic_commit *c, void *e) { return c->new_bound ? c->crtc : NULL; }
static struct drm_crtc *drm_atomic_get_old_crtc_for_encoder(struct drm_atomic_commit *c, void *e) { return c->old_bound ? c->crtc : NULL; }
static struct drm_crtc_state *drm_atomic_get_old_crtc_state(struct drm_atomic_commit *c, struct drm_crtc *r) { return &c->old; }
static struct drm_crtc_state *drm_atomic_get_new_crtc_state(struct drm_atomic_commit *c, struct drm_crtc *r) { return &c->new; }
static struct drm_crtc_state *drm_atomic_get_crtc_state(struct drm_atomic_commit *c, struct drm_crtc *r) {
    c->old = *r->state;
    __drm_atomic_helper_crtc_duplicate_state(r, &c->new);
    c->crtc = r; c->old_bound = c->new_bound = connector_state.crtc != NULL;
    return &c->new;
}
static struct drm_atomic_commit *drm_atomic_commit_alloc(struct drm_device *d) { return alloc_fail ? NULL : calloc(1, sizeof(struct drm_atomic_commit)); }
static void drm_atomic_commit_put(struct drm_atomic_commit *s) { free(s); }
static void drm_atomic_commit_clear(struct drm_atomic_commit *s) { memset(&s->old, 0, sizeof(s->old)); }
static void drm_modeset_acquire_init(struct drm_modeset_acquire_ctx *a, int flags) {}
static void drm_modeset_acquire_fini(struct drm_modeset_acquire_ctx *a) {}
static void drm_modeset_drop_locks(struct drm_modeset_acquire_ctx *a) { drm.mode_config.connection_mutex.held = false; }
static int drm_modeset_lock(struct mutex *m, struct drm_modeset_acquire_ctx *a) {
    assert(!panel.lock.held && !backlight.update_lock.held);
    if (lock_error) { int ret = lock_error; lock_error = 0; return ret; }
    mutex_lock(m); return 0;
}
static int drm_modeset_backoff(struct drm_modeset_acquire_ctx *a) { backoffs++; drm_modeset_drop_locks(a); return 0; }
static int drm_atomic_commit(struct drm_atomic_commit *s);
/* @PANEL_FUNCTIONS@ */
static int backlight_update_status(struct backlight_device *b) {
    mutex_lock(&b->update_lock);
    int ret = l2s_panel_bl_update_status(b);
    mutex_unlock(&b->update_lock); return ret;
}
static int backlight_enable(struct backlight_device *b) { b->props.blank = false; backlight_enables++; return backlight_update_status(b); }
static int backlight_disable(struct backlight_device *b) { b->props.blank = true; return backlight_update_status(b); }
/* @CORE_FUNCTIONS@ */
struct mipi_dsi_host { bool on, enabled; int irq_depth; };
struct msm_dsi { void *phy; bool phy_enabled; struct mipi_dsi_host *host; struct { struct device dev; } *pdev; };
static struct mipi_dsi_host host;
static struct msm_dsi dsi;
static int phy_refs, pm_refs;
#define DSI_1 1
#define DSI_CLOCK_MASTER 0
#define DSI_CLOCK_SLAVE 1
#define IS_BONDED_DSI() false
#define IS_MASTER_DSI_LINK(id) true
static struct msm_dsi *dsi_mgr_get_dsi(int id) { return id == 0 ? &dsi : NULL; }
static int dsi_mgr_bridge_get_id(struct drm_bridge *b) { return 0; }
static void msm_dsi_phy_disable(void *p) { assert(phy_refs == 1 && pm_refs == 1); phy_refs--; pm_refs--; }
static int msm_dsi_host_disable(struct mipi_dsi_host *h) { h->enabled = false; return 0; }
static int msm_dsi_host_enable(struct mipi_dsi_host *h) { h->enabled = true; return 0; }
static void msm_dsi_host_disable_irq(struct mipi_dsi_host *h) { h->irq_depth++; }
static void msm_dsi_phy_pll_save_state(void *p) {}
static int msm_dsi_host_power_off(struct mipi_dsi_host *h) { h->on = false; return 0; }
static int dsi_mgr_bridge_power_on(struct drm_bridge *b) {
    assert(phy_refs == 0 && pm_refs == 0); phy_refs++; pm_refs++;
    dsi.phy_enabled = true; host.on = true; host.irq_depth--; return 0;
}
static void dsi_mgr_bridge_power_off(struct drm_bridge *b);
/* @DSI_FUNCTIONS@ */
static void dsi_mgr_bridge_power_off(struct drm_bridge *b) {
    msm_dsi_host_disable_irq(&host); msm_dsi_host_power_off(&host); dsi_mgr_phy_disable(0);
}
static const struct drm_panel_funcs funcs = {
    .prepare = l2s_panel_prepare, .enable = l2s_panel_enable,
    .disable = l2s_panel_disable, .unprepare = l2s_panel_unprepare,
    .idle_enter = l2s_idle_enter, .idle_exit = l2s_idle_exit,
};
static void transition(struct drm_atomic_commit *c) {
    crtc.state = &c->new;
    if (c->old_bound && crtc_needs_disable(&c->old, c->new_bound ? &c->new : NULL)) {
        panel_bridge_atomic_disable(&bridge.bridge, c);
        panel_bridge_atomic_post_disable(&bridge.bridge, c);
        dsi_mgr_bridge_post_disable(&bridge.bridge, c);
    }
    if (c->new_bound && c->new.active) {
        dsi_mgr_bridge_pre_enable(&bridge.bridge, c);
        panel_bridge_atomic_pre_enable(&bridge.bridge, c);
        panel_bridge_atomic_enable(&bridge.bridge, c);
    }
}
static int drm_atomic_commit(struct drm_atomic_commit *s) {
    wake_commits++; transition(s);
    current = *s; crtc.state = &current.new; return 0;
}
static int mode_index(unsigned hz) {
    for (unsigned i = 0; i < ARRAY_SIZE(l2s_panel_modes); i++)
        if (drm_mode_vrefresh(&l2s_panel_modes[i]) == hz) return i;
    assert(!"invalid rate"); return -1;
}
static void reset(bool sr, unsigned target) {
    memset(&panel, 0, sizeof(panel)); memset(&backlight, 0, sizeof(backlight));
    memset(&current, 0, sizeof(current)); memset(&drm, 0, sizeof(drm));
    sequence_error = init_error = display_on_error = pps_error = 0;
    brightness_error = off_error = sleep_error = underflows = 0;
    lock_error = backoffs = alloc_fail = wake_commits = backlight_enables = 0;
    enable_fail = disable_fail = -1; packet_writes = 0;
    wire_brightness = 640; physical_hz = sr ? idle_hz : 120;
    device.mode_flags = MIPI_DSI_MODE_LPM;
    panel.panel.funcs = &funcs; panel.panel.backlight = &backlight;
    INIT_WORK(&panel.backlight_work, l2s_backlight_work); unplugged = false; dev_entries = 0;
    panel.dsi = &device; panel.connector = &connector;
    panel.prepared = panel.enabled = panel.panel.prepared = panel.panel.enabled = true;
    panel.idle_active = panel.idle_requested = sr; panel.supplies_enabled = 7;
    panel.refresh = 120; panel.brightness = backlight.props.brightness = 640;
    backlight.data = &panel;
    for (unsigned i = 0; i < 3; i++) { regs[i] = (struct regulator){.refs=1, .index=i}; panel.supplies[i].consumer = &regs[i]; }
    connector_state.crtc = &crtc; connector.state = &connector_state; connector.dev = &drm; connector.refs = 2;
    bridge.panel = &panel.panel;
    current.crtc = &crtc; current.old_bound = current.new_bound = true;
    current.old = (struct drm_crtc_state){.crtc=&crtc, .enable=true, .active=!sr, .self_refresh_active=sr, .mode=l2s_panel_modes[mode_index(120)]};
    current.new = (struct drm_crtc_state){.crtc=&crtc, .enable=true, .active=true, .mode=l2s_panel_modes[mode_index(target)]};
    crtc.state = &current.new;
    host = (struct mipi_dsi_host){.on=true, .enabled=true, .irq_depth=0};
    dsi.host = &host; dsi.phy_enabled = true; phy_refs = pm_refs = 1;
}
static void wake(void) { transition(&current); }
static void run_work(void) {
    assert(!panel.lock.held && !backlight.update_lock.held);
    if (panel.backlight_work.pending) {
        panel.backlight_work.pending = false;
        panel.backlight_work.func(&panel.backlight_work);
    }
    assert(dev_entries == 0 && connector.refs == 2);
}
static void balanced(bool on) {
    assert(underflows == 0);
    for (unsigned i = 0; i < 3; i++) assert(regs[i].refs == (int)on);
    assert(panel.supplies_enabled == (on ? 7U : 0U));
}
static void off_on(bool detach) {
    current.old = current.new;
    current.old_bound = true; current.new_bound = !detach;
    current.new.active = current.new.self_refresh_active = false;
    current.new.enable = !detach;
    transition(&current); balanced(false);
    assert(!panel.panel.prepared && !panel.panel.enabled);
    assert(phy_refs == 0 && pm_refs == 0 && host.irq_depth == 1);
    current.old = current.new; current.old_bound = !detach; current.new_bound = true;
    current.new.enable = current.new.active = true;
    transition(&current); balanced(true);
    assert(phy_refs == 1 && pm_refs == 1 && host.irq_depth == 0);
    assert(panel.panel.enabled && panel.enabled);
    current.old_bound = true;
}
int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned cases = 0;
    for (unsigned idle = 0; idle < 2; idle++) {
        idle_hz = idle ? 10 : 1;
        for (unsigned i = 0; i < ARRAY_SIZE(l2s_panel_modes); i++) {
            unsigned hz = drm_mode_vrefresh(&l2s_panel_modes[i]);
            reset(true, hz); wake(); balanced(true);
            if (panel.refresh != hz || physical_hz != (int)hz || wire_brightness != 640)
                fprintf(stderr, "idle=%u target=%u cached=%u physical=%d brightness=%d recovery=%d\n", idle_hz, hz, panel.refresh, physical_hz, wire_brightness, panel.recovery_error);
            assert(panel.refresh == hz && physical_hz == (int)hz && wire_brightness == 640);
            assert(!panel.idle_active && !panel.idle_requested && panel.recovery_error == 0);
            assert(phy_refs == 1 && pm_refs == 1 && host.irq_depth == 0); cases++;
        }
    }
    puts("PASS SR exit to all six modes at 1/10 Hz, brightness and link ownership");
    const unsigned brightness_levels[] = { 0, 307, 640, 2047 };
    for (unsigned level = 0; level < ARRAY_SIZE(brightness_levels); level++) {
        unsigned brightness = brightness_levels[level];
        reset(true,120); panel.brightness = backlight.props.brightness = brightness;
        sequence_error = -ETIMEDOUT; wake(); balanced(true);
        assert(panel.enabled && wire_brightness == (int)brightness);
        assert(panel.runtime_failed && panel.runtime_error == -ETIMEDOUT && !panel.recovery_error);
        assert(backlight_enables == 0); cases++;
    }
    reset(true,120); sequence_error = -ETIMEDOUT; init_error = -EIO; wake();
    assert(!panel.prepared && !panel.enabled && panel.recovery_error == -EIO); balanced(false);
    init_error = sequence_error = 0; off_on(false); cases++;
    for (unsigned fault = 0; fault < 3; fault++) {
        reset(true,120); sequence_error = -ETIMEDOUT;
        if (fault == 0) display_on_error = -EIO;
        if (fault == 1) pps_error = -EIO;
        if (fault == 2) brightness_error = -EIO;
        wake(); balanced(false); assert(!panel.prepared && !panel.enabled);
        display_on_error = pps_error = brightness_error = sequence_error = 0;
        off_on(true); cases++;
    }
    puts("PASS exit/reinitialization/display-on/PPS/brightness failures and subsequent off/on");
    for (unsigned i = 0; i < 3; i++) {
        reset(true,60); enable_fail = i; wake(); balanced(false);
        enable_fail = -1; off_on(false); cases++;
        reset(true,60); disable_fail = i; wake();
        assert(panel.supplies_enabled == BIT(i) && regs[i].refs == 1 && underflows == 0);
        disable_fail = -1; off_on(false); cases++;
    }
    reset(false,120); sleep_error = off_error = -ETIMEDOUT; off_on(false); cases++;
    puts("PASS partial regulator acquisition/release, retries and DCS teardown errors");
    for (unsigned detach = 0; detach < 2; detach++) {
        reset(false,120);
        for (unsigned i = 0; i < 100; i++) {
            current.old = current.new; current.new.active = false; current.new.self_refresh_active = true;
            transition(&current); balanced(true);
            if (!panel.idle_active || phy_refs != 1 || pm_refs != 1 || host.irq_depth != 0)
                fprintf(stderr, "cycle=%u detach=%u idle=%d prepared=%d enabled=%d refresh=%u failed=%d errno=%d phy=%d pm=%d irq=%d\n", i, detach, panel.idle_active, panel.prepared, panel.enabled, panel.refresh, panel.runtime_failed, panel.runtime_error, phy_refs, pm_refs, host.irq_depth);
            assert(panel.idle_active && phy_refs == 1 && pm_refs == 1 && host.irq_depth == 0);
            off_on(detach); cases++;
        }
    }
    puts("PASS 100 SR/off/on cycles each with DPMS-bound and detached connector");
    reset(false,120); sequence_error = -ETIMEDOUT;
    current.old = current.new; current.new.active = false; current.new.self_refresh_active = true;
    transition(&current);
    assert(panel.idle_requested && !panel.idle_active && panel.runtime_failed);
    assert(!l2s_idle_supported(&panel.panel, &current.new));
    backlight.props.brightness = 777;
    assert(backlight_update_status(&backlight) == 0);
    assert(wake_commits == 0 && panel.backlight_work.pending); run_work();
    assert(wake_commits == 1 && wire_brightness == 777 && panel.enabled && !panel.idle_requested); cases++;
    puts("PASS failed idle entry wakes through DRM and restores new requested brightness");
    reset(true,120); current.new = current.old; crtc.state = &current.new;
    assert(backlight_update_status(&backlight) == 0);
    assert(wake_commits == 0 && panel.backlight_work.pending); run_work();
    assert(wake_commits == 1 && !current.new.self_refresh_active && current.new.active); cases++;
    reset(true,120); current.new = current.old; crtc.state = &current.new; lock_error = -EDEADLK;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(backoffs == 1 && wake_commits == 1); cases++;
    reset(true,120); backlight.props.blank = true;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(wake_commits == 0); cases++;
    reset(true,120); connector_state.crtc = NULL;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(wake_commits == 0); cases++;
    reset(true,120); current.new = current.old; current.new.self_refresh_active = false; current.new.enable = false;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(wake_commits == 0); cases++;
    reset(true,120); alloc_fail = 1;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(panel.backlight_error == -ENOMEM && wake_commits == 0); cases++;
    reset(true,120); current.new = current.old; crtc.state = &current.new;
    sequence_error = -ETIMEDOUT; init_error = -EIO;
    assert(backlight_update_status(&backlight) == 0); run_work();
    assert(panel.backlight_error == -EIO && wake_commits == 1); balanced(false); cases++;
    reset(false,120); brightness_error = -EIO;
    assert(backlight_update_status(&backlight) == -EIO && device.mode_flags == MIPI_DSI_MODE_LPM); cases++;
    puts("PASS real duplicate_state, deferred brightness wake, blank/off/unbound, deadlock retry and lock order");
    reset(true,120); current.new = current.old; crtc.state = &current.new;
    backlight.props.brightness = 777; assert(backlight_update_status(&backlight) == 0);
    backlight.props.brightness = 888; assert(backlight_update_status(&backlight) == 0);
    run_work(); assert(wake_commits == 1 && wire_brightness == 888); cases++;
    reset(true,120); assert(backlight_update_status(&backlight) == 0);
    current.old = current.new; current.old.self_refresh_active = true; current.old.active = false;
    current.new.active = false; current.new.self_refresh_active = false;
    transition(&current); balanced(false); run_work();
    assert(wake_commits == 0 && !panel.enabled); cases++;
    reset(true,120); assert(backlight_update_status(&backlight) == 0); unplugged = true;
    run_work(); assert(panel.backlight_error == -ENODEV && wake_commits == 0); cases++;
    reset(true,120); assert(backlight_update_status(&backlight) == 0);
    assert(panel.backlight_work.pending); l2s_stop_backlight_work(&panel);
    assert(!panel.backlight_work.pending && !panel.connector && connector.refs == 1);
    assert(backlight_update_status(&backlight) == -ENODEV);
    l2s_stop_backlight_work(&panel); assert(connector.refs == 1 && wake_commits == 0); cases++;
    reset(false,120); panel.connector = NULL; connector.refs = 1;
    assert(l2s_panel_get_modes(&panel.panel, &connector) == 6 && connector.refs == 2);
    assert(l2s_panel_get_modes(&panel.panel, &connector) == 6 && connector.refs == 2);
    struct drm_connector replacement = { .dev=&drm, .state=&connector_state, .refs=1 };
    assert(l2s_panel_get_modes(&panel.panel, &replacement) == 6);
    assert(connector.refs == 1 && replacement.refs == 2);
    l2s_stop_backlight_work(&panel); assert(replacement.refs == 1);
    assert(l2s_panel_get_modes(&panel.panel, &connector) == -ENODEV && connector.refs == 1); cases++;
    puts("PASS coalesced brightness requests, off/unplug during pending wake and idempotent removal");
    printf("PASS %u source-extracted scenarios (hardware and scheduling faked)\n", cases);
    return 0;
}
