// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include "production-defines.h"

typedef uint64_t u64;
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint16_t __le16;
typedef uint32_t u32;
typedef uint32_t __le32;
typedef int32_t s32;
struct pmic_glink_hdr { __le32 owner, type, opcode; };
#include "production-types.h"
typedef struct { int value; } atomic_t;
#define ATOMIC_INIT(v) { (v) }
static int atomic_read(atomic_t *v) { return v->value; }
static void atomic_set(atomic_t *v, int value) { v->value = value; }
static int atomic_cmpxchg(atomic_t *v, int old, int value) { int before = v->value; if (before == old) v->value = value; return before; }
static bool builtin = true;
#define IS_BUILTIN(...) builtin
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define time_after_eq(a, b) ((long)((a) - (b)) >= 0)
#define min_t(type, a, b) ((type)(a) < (type)(b) ? (type)(a) : (type)(b))
#define __user
struct file { void *private_data; };
static int copy_from_user(void *to, const void *from, size_t size) { memcpy(to, from, size); return 0; }
struct mutex { bool locked; };
struct completion { bool done; };
struct work_struct { int unused; };
struct delayed_work { struct work_struct work; };
struct power_supply { void *data; };
struct device { void *data; };
struct device_attribute { int unused; };
static int sysfs_emit(char *buf, const char *format, ...) { va_list args; va_start(args, format); int n = vsnprintf(buf, 4096, format, args); va_end(args); return n; }
enum power_supply_property { POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR, POWER_SUPPLY_PROP_CAPACITY };
union power_supply_propval { int intval; };
#define POWER_SUPPLY_CHARGE_BEHAVIOUR_AUTO 0
#define POWER_SUPPLY_CHARGE_BEHAVIOUR_INHIBIT_CHARGE 1
#define POWER_SUPPLY_HEALTH_GOOD 1
#define QCOM_BATTMGR_DODGE 2
#define QCOM_BATTMGR_SC8280XP 3
#define QCOM_BATTMGR_X1E80100 4
#define xchg(p, v) __extension__ ({ __typeof__(*(p)) old = *(p); *(p) = (v); old; })
#define DODGE_POWER_OFF 1
#define fallthrough __attribute__((fallthrough))
#define PMIC_GLINK_OWNER_BATTMGR 32778
#define PMIC_GLINK_REQ_RESP 1
#define PMIC_GLINK_NOTIFY 2
#define HZ 100
/* Match the kernel task macro so local variable collisions fail compilation. */
#define current get_current()
#define BIT(n) (1u << (n))
#define cpu_to_le32(v) ((u32)(v))
#define le32_to_cpu(v) ((u32)(v))
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x, v) ((x) = (v))
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
#define to_delayed_work(p) container_of(p, struct delayed_work, work)
struct qcom_battmgr {
	struct mutex lock;
	int dodge_otg_lock, variant;
	bool dodge_request_pending;
	u32 dodge_request_opcode, dodge_request_property;
	struct completion ack;
	int error;
	u32 dodge_input_suspend;
	int dodge_input_suspend_error;
	u32 dodge_voltage_word2, dodge_voltage_word13, dodge_voltage_words;
	int dodge_voltage_error;
	struct completion dodge_otg_ack;
	struct delayed_work dodge_otg_work, charge_work, dodge_cid_work, dodge_typec_work;
	struct nu1669_snapshot charge_receiver;
	struct nu1669_snapshot input_receiver;
	struct delayed_work input_work;
	u32 input_generation, input_usb_epoch, input_session_usb_epoch;
	unsigned long input_deadline;
	const char *input_phase, *input_stage, *input_reason, *input_failure_stage;
	int input_start_ack, input_cleanup_ack, input_error;
	bool input_owned, input_frozen, input_closed;
	struct power_supply *wireless_receiver, *bat_psy;
	void *client, *dev;
	bool service_up, dodge_otg_stopping, dodge_otg_broken, dodge_otg_requested, dodge_otg_ready;
	bool dodge_power_ambiguous, dodge_otg_pending, dodge_gauge_pending, dodge_power_off_pending;
	bool dodge_otg_prohibited, dodge_cid_pending, dodge_cid_retried;
	bool dodge_typec_pending, dodge_typec_retried;
	bool automatic_bpp, manual_hold, care_hold, safety_hold, automatic_veto, automatic_qualified, automatic_prepared;
	unsigned int automatic_good;
	unsigned long charge_hold_since, automatic_good_at, safety_hold_since;
	bool charge_owned, charge_pending, charge_frozen, charge_closing, charge_suspending;
	u32 dodge_service_generation, dodge_otg_opcode, dodge_otg_property, dodge_otg_value;
	u32 dodge_otg_epoch, charge_epoch, charge_generation, charge_session_epoch;
	u32 dodge_pd_revision, dodge_cid_sequence, dodge_typec_sequence;
	u32 dodge_gauge[9];
	unsigned long dodge_cid_deadline;
	int dodge_otg_error, dodge_power_state;
};
static void *system_percpu_wq;
static unsigned long jiffies;
static int requests, sets0, sets1, gauge_reads, snapshot_error, usb_online, cid, otg_switch;
static int queued, cancelled, warnings, teardown_errors, gate, battery_health, temperature;
static struct nu1669_snapshot fresh;
static enum { GOOD, LOST_SET0_ACK, LOST_READBACK, INVALID_READBACK, SERVICE_LOSS,
	      USB_ATTACH, PROVIDER_REMOVE, FAST_TRANSITION, LOST_SET1_ACK,
	      SET0_REMOTE_ERROR, GAUGE_TIMEOUT } fault;
static int boundary, inject_at;
static int input_starts, input_stops, wireless_gets;
static bool manual_api;
static u32 wireless_raw;
static enum { P_GOOD, P_LOST_START, P_LOST_STOP, P_REMOTE_START, P_REMOTE_STOP,
              P_BAD_PROPERTY, P_BAD_TYPE, P_BAD_LENGTH } probe_fault;
static enum { B_NONE, B_USB, B_SERVICE, B_PRIMARY, B_PROVIDER, B_WLS, B_DEADLINE } boundary_mode;
static struct power_supply battery;
static struct device device;
static struct qcom_battmgr bm;
static void mutex_lock(struct mutex *m) { assert(!m->locked); m->locked = true; }
static int mutex_trylock(struct mutex *m) { if (m->locked) return 0; m->locked = true; return 1; }
static void mutex_unlock(struct mutex *m) { assert(m->locked); m->locked = false; }
static void *power_supply_get_drvdata(struct power_supply *psy) { return psy->data; }
static void *dev_get_drvdata(struct device *dev) { return dev->data; }
static void power_supply_changed(struct power_supply *psy) {}
static void reinit_completion(struct completion *c) { c->done = false; }
static void complete(struct completion *c) { c->done = true; }
static unsigned long wait_for_completion_timeout(struct completion *c, int timeout) { return c->done; }
static void mod_delayed_work(void *wq, struct delayed_work *work, int delay) { queued++; }
static void schedule_delayed_work(struct delayed_work *work, int delay) { queued++; }
static void cancel_delayed_work_sync(struct delayed_work *work) { cancelled++; }
static int msecs_to_jiffies(int ms) { return ms; }
#define dev_warn_ratelimited(...) ((void)warnings++)
#define dev_err(...) ((void)teardown_errors++)
static int qcom_battmgr_wireless_present(struct qcom_battmgr *manager, bool event)
{
	assert(!"charge behaviour must never authorize OTG power");
	return -EIO;
}
static void inject_boundary(struct qcom_battmgr *manager);
static int nu1669_get_snapshot(struct power_supply *psy, struct nu1669_snapshot *snapshot)
{
	if (snapshot_error)
		return snapshot_error;
	u64 generation = fresh.generation;
	inject_boundary(&bm);
	if (snapshot_error) return snapshot_error;
	if (generation != fresh.generation) return -EAGAIN;
	*snapshot = fresh;
	return 0;
}
static int setup_calls, setup_error;
static int nu1669_prepare_bpp(struct power_supply *psy, u32 generation) { setup_calls++; if (generation != fresh.generation) return -ESTALE; if (!setup_error) fresh.bpp_valid = true; return setup_error; }
static void inject_boundary(struct qcom_battmgr *manager);
static int qcom_battmgr_request(struct qcom_battmgr *manager, void *data, size_t len)
{
	const struct qcom_battmgr_dodge_request *req = data;
	assert(manager->lock.locked && manager->dodge_gauge_pending);
	assert(len == sizeof(*req) && req->hdr.opcode == DODGE_GAUGE_OPCODE);
	assert(req->data_size == DODGE_GAUGE_WORDS * sizeof(__le32));
	gauge_reads++;
	manager->dodge_gauge[0] = temperature;
	inject_boundary(manager);
	return fault == GAUGE_TIMEOUT ? -ETIMEDOUT : 0;
}
static int pmic_glink_send(void *client, const void *data, size_t len);
/* These demux branches must never receive a matched property ACK. */
static void qcom_battmgr_dodge_pd_reply(struct qcom_battmgr *bm, const void *data, size_t len) { assert(!"unexpected PD branch"); }
static int qcom_battmgr_dodge_decode(const void *data, size_t len, u32 *value) { assert(!"unexpected gauge branch"); return -EIO; }
static int qcom_battmgr_dodge_decode_input_suspend(const void *data, size_t len, u32 *value) { assert(!"unexpected gauge branch"); return -EIO; }
static int qcom_battmgr_dodge_decode_voltage_samples(const void *data, size_t len, u32 *w2, u32 *w13, u32 *words) { assert(!"unexpected gauge branch"); return -EIO; }
static void qcom_battmgr_notification(struct qcom_battmgr *bm, const void *data, size_t len) { assert(!"unexpected generic notification"); }
static void qcom_battmgr_sc8280xp_callback(struct qcom_battmgr *bm, const void *data, size_t len) { assert(!"unexpected generic callback"); }
static void qcom_battmgr_sm8350_callback(struct qcom_battmgr *bm, const void *data, size_t len) { assert(!"matched ACK escaped interceptor"); }
#include "production.c"

static int pmic_glink_send(void *client, const void *data, size_t len)
{
	struct qcom_battmgr *manager = client;
	const struct qcom_battmgr_property_request *req = data;
	struct qcom_battmgr_message reply = {};
	assert(manager->lock.locked && len == sizeof(*req));
	assert(req->hdr.owner == 32778 && req->hdr.type == 1 && req->battery == 0);
	requests++;
	reply.hdr = req->hdr;
	reply.intval.property = req->property;
	if (req->hdr.opcode == BATTMGR_BAT_PROPERTY_SET) {
		assert(req->property == BATT_CHG_CTRL_EN && req->value <= 1);
		assert(manager->charge_owned); /* Ownership must predate the side effect. */
		assert(!manager->input_owned || manual_api || manager->automatic_bpp);
		assert(manager->charge_generation == manager->dodge_service_generation);
		gate = req->value;
		if (!req->value) {
			sets0++;
			if (fault == LOST_SET0_ACK)
				return 0;
			if (fault == SET0_REMOTE_ERROR)
				reply.intval.result = 1;
			if (fault == SERVICE_LOSS) {
				manager->service_up = false;
				manager->dodge_service_generation++;
			}
			if (fault == USB_ATTACH) {
				struct qcom_battmgr_message notification = {};
				usb_online = cid = 1;
				notification.hdr.type = PMIC_GLINK_NOTIFY;
				notification.notification = NOTIF_USB_PROPERTY;
				qcom_battmgr_dodge_otg_notification(manager, &notification,
					sizeof(notification.hdr) + sizeof(notification.notification));
			}
			if (fault == PROVIDER_REMOVE) {
				snapshot_error = -ENODEV;
				qcom_battmgr_charge_event(manager);
			}
			if (fault == FAST_TRANSITION) {
				fresh.protocol = 0x31;
				fresh.b2b_state = 1;
			}
		} else {
			sets1++;
			if (manager->automatic_bpp && qcom_battmgr_bpp_hold(manager))
				assert(!manager->input_owned); /* Unsafe/session cleanup removes input first. */
			assert(battery_health == POWER_SUPPLY_HEALTH_GOOD);
			assert(temperature >= 0 && temperature <= 430);
			if (fault == LOST_SET1_ACK)
				return 0;
		}
	} else if (req->hdr.opcode == BATTMGR_WLS_PROPERTY_SET) {
		assert(req->property == DODGE_WLS_INPUT_CURR_LIMIT);
		assert(req->value == 750000 || !req->value);
		assert(manager->input_owned && atomic_read(&dodge_input_boot_state) == INPUT_BOOT_MAYBE_OWNED);
		/* Only the existing manual API can have changed the battery permission. */
		reply.intval.value = wireless_raw;
		if (req->value) {
			input_starts++;
			assert(manager->automatic_bpp || manager->input_deadline == jiffies + 45 * HZ);
			if (probe_fault == P_LOST_START) return 0;
			if (probe_fault == P_REMOTE_START) reply.intval.result = 1;
		} else {
			input_stops++;
			if (probe_fault == P_LOST_STOP) return 0;
			if (probe_fault == P_REMOTE_STOP) reply.intval.result = 1;
		}
		if (probe_fault == P_BAD_PROPERTY) reply.intval.property++;
		if (probe_fault == P_BAD_TYPE) reply.hdr.type = 2;
	} else if (req->hdr.opcode == BATTMGR_WLS_PROPERTY_GET) {
		assert(req->property == DODGE_WLS_INPUT_CURR_LIMIT && !req->value);
		reply.intval.value = wireless_raw; /* Independent sensor/effective response, never request echo. */
		wireless_gets++;
	} else if (req->hdr.opcode == BATTMGR_BAT_PROPERTY_GET) {
		if (req->property == BATT_CHG_CTRL_EN) {
			reply.intval.value = gate;
			if (sets0 && !sets1 && fault == LOST_READBACK)
				return 0;
			if (sets0 && !sets1 && fault == INVALID_READBACK)
				reply.intval.value = 2;
		} else {
			assert(req->property == BATT_HEALTH);
			reply.intval.value = battery_health;
		}
	} else {
		assert(req->hdr.opcode == BATTMGR_USB_PROPERTY_GET);
		assert(!req->value);
		if (req->property == USB_ONLINE)
			reply.intval.value = usb_online;
		else if (req->property == DODGE_USB_CID_STATUS)
			reply.intval.value = cid;
		else {
			assert(req->property == DODGE_USB_OTG_SWITCH);
			reply.intval.value = otg_switch;
		}
	}
	qcom_battmgr_callback(&reply, sizeof(reply.hdr) + sizeof(reply.intval) -
		(req->hdr.opcode == BATTMGR_WLS_PROPERTY_SET && probe_fault == P_BAD_LENGTH), manager);
	inject_boundary(manager);
	return 0;
}

static void inject_boundary(struct qcom_battmgr *manager)
{
	boundary++;
	if (!inject_at || boundary != inject_at)
		return;
	if (boundary_mode == B_USB) {
		struct qcom_battmgr_message notification = {};
		usb_online = cid = 1;
		notification.hdr.type = PMIC_GLINK_NOTIFY;
		notification.notification = NOTIF_USB_PROPERTY;
		qcom_battmgr_dodge_otg_notification(manager, &notification,
			sizeof(notification.hdr) + sizeof(notification.notification));
	} else if (boundary_mode == B_SERVICE) {
		manager->service_up = false;
		manager->dodge_service_generation++;
	} else if (boundary_mode == B_PRIMARY) {
		/* Hard IRQ happened, threaded notification is deliberately delayed. */
		fresh.generation++;
	} else if (boundary_mode == B_WLS) {
		struct qcom_battmgr_message notification = {};
		notification.hdr.type = PMIC_GLINK_NOTIFY;
		notification.notification = NOTIF_WLS_PROPERTY;
		qcom_battmgr_dodge_otg_notification(manager, &notification,
			sizeof(notification.hdr) + sizeof(notification.notification));
	} else if (boundary_mode == B_DEADLINE) {
		if (manager->input_owned) jiffies = manager->input_deadline;
	} else if (boundary_mode == B_PROVIDER) {
		snapshot_error = -ENODEV;
		qcom_battmgr_charge_event(manager);
	}
}

static void reset(void)
{
	jiffies = 100;
	memset(&bm, 0, sizeof(bm));
	bm.service_up = bm.dodge_otg_ready = true;
	bm.variant = QCOM_BATTMGR_DODGE;
	bm.dodge_service_generation = 7;
	bm.dodge_power_state = DODGE_POWER_OFF;
	bm.client = &bm;
	bm.bat_psy = &battery;
	battery.data = &bm;
	device.data = &bm;
	requests = sets0 = sets1 = gauge_reads = queued = cancelled = warnings = teardown_errors = 0;
	snapshot_error = usb_online = cid = otg_switch = 0;
	gate = 1;
	battery_health = POWER_SUPPLY_HEALTH_GOOD;
	temperature = 250;
	fresh = (struct nu1669_snapshot) { .generation = 11, .chip_id = 0x1669,
		.vout_mv = 5500, .protocol = 4, .b2b_state = 4 };
	fault = GOOD;
	builtin = true;
	input_starts = input_stops = wireless_gets = wireless_raw = 0;
	manual_api = false;
	probe_fault = P_GOOD;
	atomic_set(&dodge_input_boot_state, INPUT_BOOT_UNUSED);
	bm.input_start_ack = bm.input_cleanup_ack = -ENODATA;
	boundary = inject_at = 0;
	boundary_mode = B_NONE;
}

static int set_mode(int mode)
{
	union power_supply_propval value = { .intval = mode };
	manual_api = true;
	int ret = qcom_battmgr_charge_set_property(&battery, POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR, &value);
	manual_api = false;
	return ret;
}

static int get_mode(void)
{
	union power_supply_propval value;
	int ret = qcom_battmgr_charge_get_behaviour(&bm, &value);
	return ret ? ret : value.intval;
}

static void normal_and_foreign(void)
{
	reset();
	assert(qcom_battmgr_charge_is_writeable(&battery, POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR));
	assert(!qcom_battmgr_charge_is_writeable(&battery, POWER_SUPPLY_PROP_CAPACITY));
	assert(!set_mode(0) && !requests && !sets1 && get_mode() == 0);
	assert(!set_mode(1) && sets0 == 1 && !sets1 && !gate && get_mode() == 1);
	assert(bm.charge_owned && !bm.charge_pending);
	assert(!set_mode(1) && sets0 == 1); /* Revalidate; never repeat SET0. */
	assert(!set_mode(0) && gate == 1 && sets1 == 1 && !bm.charge_owned && get_mode() == 0);
	assert(!set_mode(0) && sets1 == 1);
	reset();
	gate = 0;
	assert(get_mode() == 0 && !set_mode(0) && !requests);
	assert(set_mode(1) == -EBUSY && !bm.charge_owned && !sets0 && !sets1);
	assert(!set_mode(0) && !sets1 && get_mode() == 0);
	puts("normal/foreign: owned1->0->1, repeated inhibit, idempotent AUTO, foreign0 untouched passed");
}

static void source_and_health(void)
{
	for (int scenario = 0; scenario < 17; scenario++) {
		reset();
		switch (scenario) {
		case 0: fresh.protocol = 0x31; break;
		case 1: fresh.b2b_on = 1; break;
		case 2: fresh.b2b_state = 1; break;
		case 3: fresh.vout_mv = 4499; break;
		case 4: fresh.vout_mv = 6001; break;
		case 5: snapshot_error = -EIO; break;
		case 6: usb_online = 1; break;
		case 7: cid = 1; break;
		case 8: otg_switch = 1; break;
		case 9: temperature = -1; break;
		case 10: battery_health = 2; break;
		case 11: temperature = 431; break;
		case 12: bm.dodge_otg_requested = true; break;
		case 13: bm.dodge_power_state = 0; break;
		case 14: snapshot_error = -EOPNOTSUPP; break;
		case 15: bm.service_up = false; break;
		case 16: bm.charge_suspending = true; break;
		}
		assert(set_mode(1) < 0 && !bm.charge_owned && !sets0 && !sets1);
	}
	for (int limit = 0; limit <= 430; limit += 430) {
		reset();
		temperature = limit;
		assert(!set_mode(1) && !set_mode(0) && sets0 == 1 && sets1 == 1);
	}
	reset();
	gate = 2;
	assert(set_mode(1) == -EPROTO && !sets0 && !sets1);
	reset();
	fault = GAUGE_TIMEOUT;
	assert(set_mode(1) == -ETIMEDOUT && !sets0 && !sets1 && bm.dodge_otg_broken);
	reset();
	assert(!set_mode(1));
	temperature = 431;
	assert(set_mode(0) == -EAGAIN && gate == 0 && !sets1 && bm.charge_pending);
	assert(get_mode() == -EIO && !bm.charge_frozen);
	temperature = 250;
	qcom_battmgr_charge_worker(&bm.charge_work.work);
	assert(gate == 1 && sets1 == 1 && !bm.charge_owned && get_mode() == 0);
	puts("source/health: BPP/direct/VOUT/GPIO/USB/temp/health gates, malformed bool, pending healthy retry passed");
}

static void interrupted_transactions(void)
{
	for (int scenario = LOST_SET0_ACK; scenario <= FAST_TRANSITION; scenario++) {
		reset();
		fault = scenario;
		assert(set_mode(1) < 0 && sets0 == 1);
		if (scenario == USB_ATTACH || scenario == PROVIDER_REMOVE || scenario == FAST_TRANSITION) {
			assert(sets1 == 1 && gate == 1 && !bm.charge_owned && get_mode() == 0);
		} else {
			assert(!sets1 && gate == 0 && bm.charge_owned && bm.charge_pending);
			assert(bm.charge_frozen && get_mode() == -EIO);
			int before = requests;
			assert(set_mode(0) < 0 && requests == before && !sets1);
		}
	}
	reset();
	fault = SET0_REMOTE_ERROR;
	assert(set_mode(1) == -EREMOTEIO && bm.charge_owned && bm.charge_frozen && !sets1);
	reset();
	assert(!set_mode(1));
	fault = LOST_SET1_ACK;
	assert(set_mode(0) == -ETIMEDOUT && sets1 == 1 && gate == 1);
	assert(bm.charge_owned && bm.charge_pending && bm.charge_frozen && get_mode() == -EIO);
	int before = requests;
	assert(set_mode(0) < 0 && requests == before && sets1 == 1);
	puts("transactions: ownership before SET, lost SET/readback ACK, invalid bool, service loss, USB/provider/fast races passed");
}

static void boundary_sweeps(void)
{
	reset();
	assert(!set_mode(1));
	int acquire_boundaries = boundary;
	boundary = 0;
	assert(!set_mode(0));
	int restore_boundaries = boundary;
	for (int event = B_USB; event <= B_PROVIDER; event++) {
		for (int at = 1; at <= acquire_boundaries; at++) {
			reset();
			boundary_mode = event;
			inject_at = at;
			int ret = set_mode(1);
			if (!ret) {
				/* A primary edge before the first snapshot starts a fresh identity. */
				assert(event == B_PRIMARY && bm.charge_receiver.generation == fresh.generation);
				assert(bm.charge_owned && !bm.charge_pending && gate == 0);
			} else if (!sets0) {
				assert(!bm.charge_owned && gate == 1 && !sets1);
			} else if (event == B_SERVICE) {
				assert(bm.charge_owned && bm.charge_frozen && !sets1);
				assert(get_mode() == -EIO);
			} else {
				assert(!bm.charge_owned && gate == 1 && sets1 == 1);
			}
		}
		for (int at = 1; at <= restore_boundaries; at++) {
			reset();
			assert(!set_mode(1));
			boundary = 0;
			boundary_mode = event;
			inject_at = at;
			int ret = set_mode(0);
			if (event == B_SERVICE) {
				assert(ret < 0 && bm.charge_owned && bm.charge_frozen && get_mode() == -EIO);
				assert(sets1 <= 1);
			} else {
				assert(!ret && !bm.charge_owned && gate == 1 && sets1 == 1);
			}
		}
	}
	printf("boundaries: USB/service/hard-IRQ/provider at every %d acquire and %d restore endpoint passed\n",
		acquire_boundaries, restore_boundaries);
}

static void lifecycle(void)
{
	reset();
	assert(!set_mode(1));
	assert(!qcom_battmgr_charge_suspend(&device));
	assert(!bm.charge_owned && gate == 1 && sets1 == 1 && bm.charge_suspending);
	assert(!qcom_battmgr_charge_resume(&device) && !bm.charge_suspending);
	assert(get_mode() == 0 && sets0 == 1); /* No automatic reacquisition. */
	reset();
	gate = 0;
	assert(!qcom_battmgr_charge_suspend(&device) && !requests && !sets1);
	reset();
	assert(!set_mode(1));
	temperature = 450;
	assert(qcom_battmgr_charge_suspend(&device) == -EBUSY);
	assert(bm.charge_owned && bm.charge_pending && !bm.charge_suspending && !sets1);
	qcom_battmgr_charge_close(&bm);
	assert(bm.charge_closing && bm.charge_owned && !sets1 && teardown_errors == 1);
	int before = requests;
	qcom_battmgr_charge_event(&bm);
	qcom_battmgr_charge_worker(&bm.charge_work.work);
	assert(set_mode(0) == -EBUSY && requests == before);
	/* Reprobe has no ownership; an inherited raw0 must stay unowned. */
	reset();
	gate = 0;
	assert(!set_mode(0) && !sets1 && get_mode() == 0);
	reset();
	assert(!set_mode(1));
	qcom_battmgr_charge_close(&bm);
	qcom_battmgr_charge_close(&bm);
	assert(!bm.charge_owned && gate == 1 && sets1 == 1 && !teardown_errors);
	puts("lifecycle: suspend ends session, unsafe suspend blocks, unsafe teardown warns, no post-close work/reprobe enable passed");
}

static void raw_wireless_zero(void)
{
	u64 raw = UINT64_MAX;
	reset();
	assert(!qcom_battmgr_dodge_wireless_input_current_limit_get(&bm, &raw) && raw == 0);
	assert(!set_mode(1));
	assert(!qcom_battmgr_dodge_wireless_input_current_limit_get(&bm, &raw) && raw == 0);
	assert(!set_mode(0));
	assert(!qcom_battmgr_dodge_wireless_input_current_limit_get(&bm, &raw) && raw == 0);
	assert(gate == 1 && sets0 == 1 && sets1 == 1);
	puts("raw wireless zero remains readable across owned battery permission cycle; no wireless SET permitted");
}

static int input_control(bool start)
{
	return qcom_battmgr_input_probe_control(&bm, start);
}
static void input_probe_normal(void)
{
	reset();
	struct file file = { .private_data = &bm }; loff_t position = 0;
	assert(qcom_battmgr_input_probe_write(&file, "300000", 6, &position) == -EINVAL);
	assert(qcom_battmgr_input_probe_write(&file, "1 ", 2, &position) == -EINVAL);
	assert(qcom_battmgr_input_probe_write(&file, "01", 2, &position) == -EINVAL);
	assert(atomic_read(&dodge_input_boot_state) == INPUT_BOOT_UNUSED && !requests);
	mutex_lock(&bm.lock); assert(input_control(true) == -EBUSY); mutex_unlock(&bm.lock);
	assert(atomic_read(&dodge_input_boot_state) == INPUT_BOOT_UNUSED);
	builtin = false; assert(input_control(true) == -EOPNOTSUPP && !requests);
	builtin = true; assert(!input_control(false) && !requests);
	assert(qcom_battmgr_input_probe_write(&file, "1\n", 2, &position) == 2);
	assert(input_starts == 1 && !input_stops && gate == 1 && !sets0 && !sets1 && !wireless_gets);
	assert(bm.input_owned && !bm.input_frozen && bm.input_start_ack == 0);
	int before = requests;
	assert(!set_mode(0) && requests == before && bm.input_owned);
	assert(input_control(true) == -EALREADY && requests == before);
	wireless_raw = 710000; /* Stock-like measured/effective response is independent of750000 request. */
	u64 raw; assert(!qcom_battmgr_dodge_wireless_input_current_limit_get(&bm, &raw) && raw == 710000);
	assert(qcom_battmgr_input_probe_write(&file, "0", 1, &position) == 1);
	assert(input_stops == 1 && !bm.input_owned && !bm.input_cleanup_ack && gate == 1);
	before = requests; assert(!input_control(false) && requests == before);
	assert(input_control(true) == -EALREADY && requests == before);
	reset(); assert(!set_mode(1)); before = requests;
	assert(input_control(true) == -EBUSY && requests == before && !input_starts);
	for (int condition = 0; condition < 7; condition++) {
		reset();
		if (condition == 0) gate = 0;
		if (condition == 1) temperature = 500;
		if (condition == 2) usb_online = 1;
		if (condition == 3) cid = 1;
		if (condition == 4) otg_switch = 1;
		if (condition == 5) fresh.b2b_state = 1;
		if (condition == 6) bm.dodge_power_state = 2;
		assert(input_control(true) && !input_starts && !input_stops && !sets0 && !sets1);
		assert(atomic_read(&dodge_input_boot_state) == INPUT_BOOT_CONSUMED_NO_REQUEST);
		assert(input_control(true) == -EALREADY);
	}
	puts("ACK input probe: exact1/0, built-in/once-per-boot, gate1/health/BPP/USB guards, no BATT SET, no GET8 write-through, independent measured response and UNKNOWN INHIBIT exclusion passed");
}
static void input_probe_lifecycle(void)
{
	reset(); assert(!input_control(true));
	jiffies = bm.input_deadline;
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(input_stops == 1 && !bm.input_owned && gate == 1 && !sets0 && !sets1);
	assert(!strcmp(bm.input_reason, "deadline"));
	reset(); assert(!input_control(true)); temperature = 500; snapshot_error = -ENODEV;
	assert(!input_control(false) && input_stops == 1 && !bm.input_owned);
	reset(); assert(!input_control(true)); temperature = 500;
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(input_stops == 1 && !bm.input_owned && !sets0 && !sets1);
	assert(bm.input_error == -EAGAIN && bm.input_failure_stage);
	reset(); assert(!input_control(true));
	assert(!qcom_battmgr_charge_suspend(&device) && input_stops == 1 && !bm.input_owned);
	assert(!qcom_battmgr_charge_resume(&device));
	assert(input_control(true) == -EALREADY && !sets0 && !sets1);
	reset(); assert(!input_control(true)); qcom_battmgr_charge_close(&bm);
	assert(input_stops == 1 && !bm.input_owned && !sets0 && !sets1);
	qcom_battmgr_charge_close(&bm); assert(input_stops == 1);
	puts("ACK input lifecycle:45s watchdog, unhealthy/unreadable SET0 cleanup, source revalidation, suspend/resume/no reacquire, teardown/idempotence and zero BATT SET passed");
}
static void input_probe_ambiguity(void)
{
	for (int f = P_LOST_START; f <= P_BAD_LENGTH; f++) {
		reset(); probe_fault = f;
		if (f == P_LOST_STOP || f == P_REMOTE_STOP) {
			probe_fault = P_GOOD; assert(!input_control(true)); probe_fault = f;
			assert(input_control(false));
		} else assert(input_control(true));
		assert(bm.input_owned && bm.input_frozen && atomic_read(&dodge_input_boot_state) == INPUT_BOOT_MAYBE_OWNED);
		assert(gate == 1 && !sets0 && !sets1);
		int before = requests; assert(input_control(false) == -ENOTCONN && requests == before);
		jiffies = bm.input_deadline; qcom_battmgr_input_probe_worker(&bm.input_work.work);
		assert(requests == before);
		bm.service_up = true; bm.dodge_service_generation++; bm.dodge_otg_broken = false;
		assert(input_control(false) == -ENOTCONN && requests == before);
		assert(qcom_battmgr_charge_suspend(&device) == -EBUSY);
		qcom_battmgr_charge_close(&bm); assert(requests == before && teardown_errors);
		/* A new instance loses context, never the boot-global possible owner/consumption. */
		int boot = atomic_read(&dodge_input_boot_state); reset(); atomic_set(&dodge_input_boot_state, boot);
		assert(!bm.input_owned && atomic_read(&dodge_input_boot_state) == INPUT_BOOT_MAYBE_OWNED);
		assert(input_control(true) == -EALREADY && input_control(false) == -ENOTCONN && !requests);
		assert(set_mode(1) == -EBUSY && !requests);
	}
	puts("ACK input ambiguity: matched errors/malformed or lost ACK, retired channel, no zero retry/service transfer, UNKNOWN teardown and possible owner surviving reprobe passed");
}
static void input_probe_boundaries(void)
{
	reset(); assert(!input_control(true)); int acquire = boundary;
	boundary = 0; assert(!input_control(false)); int cleanup = boundary;
	for (int event = B_USB; event <= B_DEADLINE; event++) {
		for (int at = 1; at <= acquire; at++) {
			reset(); boundary_mode = event; inject_at = at;
			int ret = input_control(true);
			assert(!sets0 && !sets1 && gate == 1 && input_starts <= 1 && input_stops <= 1);
			if (!ret && bm.input_owned) {
				assert(!input_control(false));
			} else if (bm.input_owned) {
				assert(bm.input_frozen && atomic_read(&dodge_input_boot_state) == INPUT_BOOT_MAYBE_OWNED);
			}
			if (event == B_WLS) assert(!ret && input_starts == 1 && input_stops == 1);
			assert(!wireless_gets);
		}
		for (int at = 1; at <= cleanup; at++) {
			reset(); assert(!input_control(true)); boundary = 0;
			boundary_mode = event; inject_at = at;
			int ret = input_control(false);
			if (event == B_SERVICE) assert(ret && bm.input_frozen && bm.input_owned);
			else assert(!ret && !bm.input_owned);
			assert(input_stops == 1 && gate == 1 && !sets0 && !sets1 && !wireless_gets);
		}
	}
	printf("ACK input boundaries: USB/service/hard-IRQ/provider/generic WLS/deadline at every %d start and %d cleanup endpoint passed\n", acquire, cleanup);
}

static void input_probe_manual_pause(void)
{
	reset(); assert(!input_control(true));
	assert(!set_mode(1) && gate == 0 && bm.charge_owned && !bm.charge_pending && !bm.charge_frozen);
	assert(input_starts == 1 && !input_stops && sets0 == 1 && !sets1);
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(bm.input_owned && !input_stops && gate == 0 && sets0 == 1 && !sets1);
	assert(!set_mode(1) && sets0 == 1); /* Same confirmed pause, no extra SET. */
	assert(!set_mode(0) && gate == 1 && !bm.charge_owned && bm.input_owned && !input_stops);
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(bm.input_owned && sets0 == 1 && sets1 == 1 && !input_stops);
	assert(!input_control(false) && input_stops == 1 && sets0 == 1 && sets1 == 1);
	reset(); assert(!input_control(true)); gate = 0; /* Foreign disabled permission is not a pause. */
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(!bm.input_owned && input_stops == 1 && !sets0 && !sets1 && !bm.charge_owned && gate == 0);
	for (int corruption = 0; corruption < 5; corruption++) {
		reset(); assert(!input_control(true)); assert(!set_mode(1));
		if (corruption == 0) bm.charge_generation++;
		if (corruption == 1) bm.charge_receiver.generation++;
		if (corruption == 2) bm.charge_pending = true;
		if (corruption == 3) bm.charge_frozen = true;
		if (corruption == 4) bm.charge_epoch++;
		qcom_battmgr_input_probe_worker(&bm.input_work.work);
		assert(!bm.input_owned && input_stops == 1 && gate == 0 && sets0 == 1 && !sets1);
	}
	reset(); assert(!input_control(true)); assert(!set_mode(1));
	jiffies = bm.input_deadline;
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(input_stops == 1 && !bm.input_owned && bm.charge_owned && gate == 0 && sets0 == 1 && !sets1);
	assert(!set_mode(0) && gate == 1 && sets1 == 1); /* Explicit AUTO remains separate. */
	reset(); assert(!input_control(true)); jiffies = bm.input_deadline;
	assert(set_mode(1) && !sets0 && gate == 1);
	qcom_battmgr_input_probe_worker(&bm.input_work.work); assert(input_stops == 1);
	reset(); assert(!input_control(true)); assert(!set_mode(1));
	boundary_mode = B_WLS; inject_at = boundary + 1; inject_boundary(&bm);
	assert(bm.charge_epoch != bm.charge_session_epoch);
	manual_api = true; qcom_battmgr_charge_worker(&bm.charge_work.work); manual_api = false;
	assert(!bm.charge_owned && gate == 1 && sets1 == 1); /* Existing epoch invalidation is intact. */
	qcom_battmgr_input_probe_worker(&bm.input_work.work);
	assert(bm.input_owned && !input_stops);
	puts("750mA coupling: confirmed pause0 accepted, AUTO1 keeps input, foreign/stale/pending/frozen pause rejected,45s SET0 independent of BATT, existing WLS epoch cleanup unchanged passed");
}
static void coupled_pause_boundaries(void)
{
	reset(); assert(!input_control(true)); boundary = 0; assert(!set_mode(1)); int total = boundary;
	for (int event = B_USB; event <= B_DEADLINE; event++) {
		for (int at = 1; at <= total; at++) {
			reset(); assert(!input_control(true)); boundary = 0;
			boundary_mode = event; inject_at = at;
			int ret = set_mode(1);
			if (!ret) assert(bm.charge_owned && !bm.charge_pending && !bm.charge_frozen && !gate);
			int before0 = sets0, before1 = sets1;
			qcom_battmgr_input_probe_worker(&bm.input_work.work);
			assert(sets0 == before0 && sets1 == before1); /* Input actor never toggles BATT. */
			assert(input_starts == 1 && input_stops <= 1 && !wireless_gets);
		}
	}
	printf("coupled manual pause: USB/service/Nu/provider/WLS/deadline at every %d endpoint, no BATT writes from input worker passed\n", total);
}

static void auto_reset(void)
{
	reset(); bm.automatic_bpp = true;
	fresh.customer_id = 4; fresh.fw_version = 0x6b;
	bm.dodge_voltage_word2 = 4200000; bm.dodge_voltage_word13 = 4200;
	setup_calls = setup_error = 0;
}
static void auto_step(void) { mutex_lock(&bm.lock); qcom_battmgr_automatic_step(&bm); mutex_unlock(&bm.lock); }
static void automatic_bpp(void)
{
	auto_reset(); auto_step(); assert(input_stops == 1 && input_starts == 1 && setup_calls == 1);
	assert(bm.input_owned && gate == 1 && !sets0 && !sets1 && !wireless_gets);
	jiffies += 100 * HZ; auto_step(); assert(bm.input_owned && input_starts == 1);
	assert(!set_mode(1) && bm.manual_hold && gate == 0 && bm.input_owned);
	bm.care_hold = true; assert(!set_mode(0) && !bm.manual_hold && gate == 0 && !sets1);
	bm.care_hold = false; auto_step(); assert(gate == 1 && sets1 == 1);
	bm.dodge_voltage_word2 = 4350000; bm.dodge_voltage_word13 = 4350;
	auto_step(); assert(bm.safety_hold && gate == 0 && bm.input_owned && input_stops == 1);
	assert(!set_mode(0) && gate == 0 && bm.safety_hold);
	bm.dodge_voltage_word2 = 4300000; bm.dodge_voltage_word13 = 4300;
	jiffies += 30 * HZ;
	for (int i = 0; i < 2; i++) { jiffies += HZ; auto_step(); assert(gate == 0); }
	jiffies += HZ; auto_step(); assert(gate == 1 && !bm.safety_hold);
	bm.dodge_voltage_word2 = 4400000; bm.dodge_voltage_word13 = 4400;
	auto_step(); assert(!bm.input_owned && input_stops == 2);
	auto_reset(); gate = 0; auto_step(); assert(!input_starts && !sets0 && !sets1 && !setup_calls);
	auto_reset(); assert(input_control(true) == -EOPNOTSUPP && !requests);
	/* Repeated confirmed attachment gets a new preparation; intent survives veto. */
	auto_reset(); bm.care_hold = true; auto_step(); assert(gate == 0 && bm.input_owned);
	snapshot_error = -ENODEV; auto_step(); assert(!bm.input_owned && gate == 1 && bm.care_hold);
	snapshot_error = 0; fresh.generation++; auto_step(); assert(bm.input_owned && gate == 0 && setup_calls == 2);
	/* Telemetry/fault emergency disable does not need a readable provider. */
	for (int failure = 0; failure < 10; failure++) {
		auto_reset(); auto_step();
		if (failure == 0) temperature = 159;
		if (failure == 1) temperature = 351;
		if (failure == 2) bm.dodge_voltage_error = -ENODATA;
		if (failure == 3) bm.dodge_voltage_word2 = 2999999;
		if (failure == 4) bm.dodge_voltage_word13 = 4149;
		if (failure == 5) bm.dodge_gauge[1] = (u32)-1200001;
		if (failure == 6) fresh.iout_ma = 901;
		if (failure == 7) fresh.flags = BIT(0);
		if (failure == 8) snapshot_error = -EIO;
		if (failure == 9) fresh.bpp_valid = false;
		auto_step(); assert(!bm.input_owned && input_stops == 2);
	}
	auto_reset(); auto_step(); assert(!set_mode(1));
	bm.dodge_gauge[1] = (u32)-50001; jiffies += 5 * HZ;
	auto_step(); assert(!bm.input_owned);
	auto_reset(); setup_error = -EIO; auto_step();
	assert(bm.input_frozen && !bm.input_owned && !input_starts); auto_step(); assert(setup_calls == 1);
	auto_reset(); probe_fault = P_LOST_START; auto_step();
	assert(bm.input_owned && bm.input_frozen && input_stops == 1);
	int before = requests; auto_step(); assert(requests == before);
	puts("automatic BPP: persistent750, independent manual/care/safety votes, ceiling retains input, hysteresis, repeated attach, unsafe input0, grace/current/fault guards and ambiguity quarantine passed");
}

static void automatic_boundaries(void)
{
	auto_reset(); auto_step(); int total = boundary;
	for (int e = B_USB; e <= B_PROVIDER; e++) {
		for (int at = 1; at <= total; at++) {
			auto_reset(); boundary_mode = e; inject_at = at; auto_step();
			if (bm.input_owned && !bm.input_frozen) auto_step();
			if (e == B_USB || e == B_SERVICE || e == B_PROVIDER)
				assert(!bm.input_owned || bm.input_frozen);
			assert(input_starts <= 1 && !wireless_gets);
		}
	}
	auto_reset(); auto_step(); assert(!set_mode(1));
	temperature = 351; auto_step(); assert(!bm.input_owned && bm.manual_hold);
	temperature = 340; auto_step(); assert(!bm.input_owned); /* Restart interior window. */
	temperature = 330; auto_step(); assert(bm.input_owned && !gate && bm.manual_hold);
	/* A suspend releases physical ownership but retains both requested votes. */
	bm.care_hold = true; assert(!qcom_battmgr_charge_suspend(&device));
	assert(!bm.input_owned && !bm.charge_owned && bm.manual_hold && bm.care_hold);
	assert(!qcom_battmgr_charge_resume(&device)); auto_step(); assert(bm.input_owned && !gate);
	printf("automatic boundaries: USB/service/primary/provider across %d start endpoints, input-before-battery cleanup, restart window and suspend vote persistence passed\n", total);
}

static void care_attribute(void)
{
	struct device care_device = { .data = &battery };
	char value[4096];
	auto_reset(); auto_step();
	const char *bad[] = { "", "2", "true", "01", "1 ", "1\n\n", "1\0ignored" };
	const size_t sizes[] = { 0, 1, 4, 2, 2, 3, 9 };
	for (unsigned int i = 0; i < ARRAY_SIZE(bad); i++)
		assert(wireless_care_hold_store(&care_device, NULL, bad[i], sizes[i]) == -EINVAL);
	assert(wireless_care_hold_store(&care_device, NULL, "1\n", 2) == 2 && gate == 0);
	assert(wireless_care_hold_show(&care_device, NULL, value) == 2 && !strcmp(value, "1\n"));
	assert(!set_mode(1));
	assert(wireless_care_hold_store(&care_device, NULL, "0", 1) == 1 && gate == 0);
	assert(!set_mode(0) && gate == 1);
	puts("care sysfs: exact0/1, newline, NUL/trailing-data rejection, requested state and independent manual vote passed");
}

int main(void)
{
	care_attribute();
	automatic_bpp();
	automatic_boundaries();
	input_probe_manual_pause();
	coupled_pause_boundaries();
	input_probe_normal();
	input_probe_lifecycle();
	input_probe_ambiguity();
	input_probe_boundaries();
	raw_wireless_zero();
	normal_and_foreign();
	source_and_health();
	interrupted_transactions();
	boundary_sweeps();
	lifecycle();
	return 0;
}
