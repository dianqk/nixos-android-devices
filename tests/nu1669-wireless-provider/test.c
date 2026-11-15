// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <sys/types.h>
#include "production-defines.h"

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef struct { u32 value; } atomic_t;
static atomic_t nu1669_bpp_uncertain;
static void atomic_set(atomic_t *a, u32 v) { a->value = v; }
static u32 atomic_read(atomic_t *a) { return a->value; }
static void atomic_inc(atomic_t *a) { a->value++; }
typedef int irqreturn_t;
struct mutex { bool locked; };
struct work_struct { int unused; };
struct delayed_work { struct work_struct work; };
struct regmap { int unused; };
struct gpio_desc { int unused; };
struct device { void *data; };
struct device_attribute { int unused; };
struct notifier_block { int unused; };
struct power_supply { void *data; void *desc; };
static int nu1669_psy_desc;
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x, v) ((x) = (v))
#define xchg(p, v) __extension__ ({ __typeof__(*(p)) old = *(p); *(p) = (v); old; })
#define EXPORT_SYMBOL_GPL(symbol)
enum power_supply_property {
	POWER_SUPPLY_PROP_PRESENT, POWER_SUPPLY_PROP_ONLINE,
	POWER_SUPPLY_PROP_VOLTAGE_NOW, POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_MANUFACTURER, POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_CAPACITY,
};
union power_supply_propval { int intval; const char *strval; };
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
#define to_delayed_work(p) container_of(p, struct delayed_work, work)
#define IRQ_HANDLED 1
#define IRQ_WAKE_THREAD 2
#define PSY_EVENT_PROP_CHANGED 1
#define NOTIFY_DONE 0
#define NOTIFY_OK 1
#define QCOM_BATTMGR_DODGE 2
#define DODGE_POWER_UNKNOWN 0
#define DODGE_POWER_OFF 1
#define DODGE_POWER_ON 2
#define BATTMGR_WLS_PROPERTY_GET 1
#define BATTMGR_USB_PROPERTY_SET 2
#define WLS_ONLINE 1
#define DODGE_USB_OTG_BOOST_CURRENT 64
#define DODGE_USB_OTG_VBUS_ENABLE 24
#define HZ 100
#define S32_MIN INT_MIN
static unsigned long jiffies = 100;
static void *system_percpu_wq;
static int gpio_value, i2c_error, notify_count, queued, cancelled, disabled, enabled;
static int unregistered, glink_wls_queries, glink_wls_online, on_writes, off_writes;
static bool race_sample, race_primary_only, attach_on_request, attach_on_enable;
static u8 shadow[NU1669_INFO_SIZE];
static struct nu1669 *receiver;
static struct power_supply rx_psy;
struct qcom_battmgr {
	struct power_supply *wireless_receiver, *wls_psy, *bat_psy;
	struct notifier_block wireless_nb;
	bool wireless_notifier_registered, wireless_known, wireless_present;
	int variant;
	int dodge_otg_lock;
	struct mutex lock;
	struct delayed_work dodge_otg_work, charge_work;
	u32 charge_epoch;
	bool charge_closing, charge_suspending;
	bool service_up, dodge_otg_stopping, dodge_otg_requested, dodge_otg_ready;
	bool dodge_otg_broken, dodge_otg_prohibited, dodge_power_off_pending;
	u32 dodge_otg_epoch, dodge_pd_epoch, dodge_service_generation, dodge_pd_generation;
	u32 dodge_pd_caps_revision, dodge_pd_revision, dodge_pd_sequence, dodge_cid_sequence;
	int dodge_otg_value, dodge_power_state;
	u32 dodge_power_generation, dodge_power_epoch, dodge_power_current_ma;
	unsigned long dodge_power_checked;
};
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
static void mutex_lock(struct mutex *lock) { assert(!lock->locked); lock->locked = true; }
static void mutex_unlock(struct mutex *lock) { assert(lock->locked); lock->locked = false; }
static void *power_supply_get_drvdata(struct power_supply *psy) { return psy->data; }
static void *dev_get_drvdata(struct device *dev) { return dev->data; }
static int gpiod_get_value_cansleep(struct gpio_desc *gpio) { return gpio_value; }
static int msecs_to_jiffies(int ms) { return ms; }
static void power_supply_changed(struct power_supply *psy) { notify_count++; }
static void mod_delayed_work(void *wq, struct delayed_work *work, int delay) { queued++; }
static void schedule_delayed_work(struct delayed_work *work, int delay) { queued++; }
static void cancel_delayed_work_sync(struct delayed_work *work) { cancelled++; }
static void disable_irq(int irq) { disabled++; }
static void enable_irq(int irq) { enabled++; }
static void power_supply_unreg_notifier(struct notifier_block *nb) { unregistered++; }
static u32 get_unaligned_le16(const void *data)
{
	const u8 *p = data;
	return p[0] | ((u32)p[1] << 8);
}
static u32 get_unaligned_le32(const void *data)
{
	const u8 *p = data;
	return get_unaligned_le16(p) | (get_unaligned_le16(p + 2) << 16);
}
#define sysfs_emit(buf, ...) snprintf(buf, 4096, __VA_ARGS__)
static irqreturn_t nu1669_connected_irq(int irq, void *data);
static irqreturn_t nu1669_connected_irq_primary(int irq, void *data);
static void qcom_battmgr_charge_event(struct qcom_battmgr *bm) { bm->charge_epoch++; }
static int regmap_bulk_read(struct regmap *map, int reg, void *data, size_t size)
{
	assert(reg == NU1669_INFO_BASE && size == NU1669_INFO_SIZE);
	if (race_sample || race_primary_only) {
		nu1669_connected_irq_primary(0, receiver);
		/* The thread waits behind the receiver mutex; primary invalidation is immediate. */
	}
	memcpy(data, shadow, size);
	return i2c_error;
}
static int power_supply_get_property(struct power_supply *psy,
		enum power_supply_property prop, union power_supply_propval *val);
static int qcom_battmgr_dodge_otg_request(struct qcom_battmgr *bm,
		u32 opcode, u32 property, u32 value, u32 generation);
static int qcom_battmgr_dodge_power_off(struct qcom_battmgr *bm, u32 generation)
{
	off_writes++;
	bm->dodge_power_off_pending = false;
	bm->dodge_power_state = DODGE_POWER_OFF;
	bm->dodge_power_generation = generation;
	return 0;
}
static bool qcom_battmgr_dodge_power_protect(struct qcom_battmgr *bm, int soc, int ua)
{
	return false;
}
static int qcom_battmgr_dodge_get_property(struct power_supply *psy,
		enum power_supply_property prop, union power_supply_propval *val)
{
	val->intval = prop == POWER_SUPPLY_PROP_CAPACITY ? 50 : -100000;
	return 0;
}
#define dev_info_ratelimited(...) ((void)0)
#define dev_warn_ratelimited(...) ((void)0)
#include "production.c"

static int power_supply_get_property(struct power_supply *psy,
		enum power_supply_property prop, union power_supply_propval *val)
{
	assert(psy == &rx_psy);
	return nu1669_get_property(psy, prop, val);
}

static int qcom_battmgr_dodge_otg_request(struct qcom_battmgr *bm,
		u32 opcode, u32 property, u32 value, u32 generation)
{
	if (opcode == BATTMGR_WLS_PROPERTY_GET) {
		glink_wls_queries++;
		bm->dodge_otg_value = glink_wls_online;
	}
	if (opcode == BATTMGR_USB_PROPERTY_SET && property == DODGE_USB_OTG_VBUS_ENABLE && value) {
		on_writes++;
		if (attach_on_enable) {
			gpio_value = 1;
			qcom_battmgr_wireless_notifier(&bm->wireless_nb,
				PSY_EVENT_PROP_CHANGED, &rx_psy);
		}
	}
	if (attach_on_request) {
		gpio_value = 1;
		qcom_battmgr_wireless_notifier(&bm->wireless_nb,
			PSY_EVENT_PROP_CHANGED, &rx_psy);
	}
	return 0;
}

static struct nu1669 rx;
static struct qcom_battmgr bm;
static void reset(void)
{
	memset(&rx, 0, sizeof(rx));
	memset(&bm, 0, sizeof(bm));
	memset(shadow, 0, sizeof(shadow));
	receiver = &rx;
	rx.psy = &rx_psy;
	rx_psy.data = &rx;
	rx_psy.desc = &nu1669_psy_desc;
	gpio_value = 0;
	i2c_error = notify_count = queued = cancelled = disabled = enabled = 0;
	unregistered = glink_wls_queries = glink_wls_online = on_writes = off_writes = 0;
	race_sample = race_primary_only = attach_on_request = attach_on_enable = false;
	bm.wireless_receiver = &rx_psy;
	bm.wls_psy = &rx_psy;
	bm.variant = QCOM_BATTMGR_DODGE;
	bm.service_up = bm.dodge_otg_ready = bm.wireless_known = true;
	bm.dodge_service_generation = bm.dodge_pd_generation = bm.dodge_power_generation = 1;
	bm.dodge_power_state = DODGE_POWER_OFF;
}

static void receiver_tests(void)
{
	union power_supply_propval val;
	char diagnostics[4096];
	struct device dev = { .data = &rx };
	reset();
	gpio_value = -EIO;
	assert(nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_PRESENT, &val) == -EIO);
	assert(nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_ONLINE, &val) == -EIO);
	gpio_value = 1;
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_PRESENT, &val) && val.intval == 1);
	shadow[0x34] = 0x88; shadow[0x35] = 0x13; /* 5000mV */
	shadow[0x36] = 0xf4; shadow[0x37] = 0x01; /* 500mA */
	shadow[0x44] = 1; shadow[0x46] = 3; /* Raw direct-path firmware bytes. */
	nu1669_poll(&rx.poll.work);
	assert(rx.valid);
	assert(firmware_state_show(&dev, NULL, diagnostics) > 0);
	assert(strstr(diagnostics, "b2b_on=0x01 b2b_state=0x03"));
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_ONLINE, &val) && val.intval == 1);
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_VOLTAGE_NOW, &val) && val.intval == 5000000);
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_CURRENT_NOW, &val) && val.intval == 500000);
	/* Fresh attachment reads defeat stale sampled state before IRQ delivery. */
	gpio_value = 0;
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_PRESENT, &val) && !val.intval);
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_ONLINE, &val) && !val.intval);
	assert(nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_VOLTAGE_NOW, &val) == -ENODATA);
	gpio_value = 1;
	i2c_error = -EREMOTEIO;
	nu1669_poll(&rx.poll.work);
	assert(!rx.valid && rx.present == 1 && !rx.info[0x34]);
	assert(firmware_state_show(&dev, NULL, diagnostics) == -ENODATA);
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_ONLINE, &val) && !val.intval);
	i2c_error = 0;
	race_sample = true;
	nu1669_poll(&rx.poll.work);
	assert(!rx.valid && atomic_read(&rx.generation) == 1); /* Reject a read spanning an edge. */
	race_sample = false;
	nu1669_poll(&rx.poll.work);
	assert(rx.valid);
	int notifications = notify_count;
	shadow[0x36]++;
	nu1669_poll(&rx.poll.work);
	assert(notify_count == notifications); /* Quiet ordinary telemetry changes. */
	nu1669_suspend(&dev);
	assert(!rx.valid && rx.suspended && disabled == 1 && cancelled == 1);
	int before = queued;
	nu1669_connected_irq(0, &rx);
	assert(queued == before);
	nu1669_resume(&dev);
	assert(!rx.suspended && enabled == 1 && queued == before + 1);
	nu1669_stop(&rx);
	nu1669_stop(&rx);
	before = queued;
	nu1669_connected_irq(0, &rx);
	nu1669_poll(&rx.poll.work);
	assert(rx.stopped && !rx.valid && disabled == 2 && cancelled == 2 && queued == before);
	puts("receiver: fresh GPIO/errors, telemetry failure, raced edge, quiet samples, suspend/stop passed");
}

static void snapshot_tests(void)
{
	struct nu1669_snapshot sample = {};
	union power_supply_propval val;
	struct power_supply wrong = {};

	reset();
	assert(nu1669_get_snapshot(NULL, &sample) == -EOPNOTSUPP);
	assert(nu1669_get_snapshot(&wrong, &sample) == -EOPNOTSUPP);
	assert(nu1669_get_snapshot(&rx_psy, &sample) == -ENODEV);
	gpio_value = -EIO;
	assert(nu1669_get_snapshot(&rx_psy, &sample) == -EIO);
	gpio_value = 1;
	i2c_error = -EREMOTEIO;
	assert(nu1669_get_snapshot(&rx_psy, &sample) == -EREMOTEIO);
	i2c_error = 0;
	shadow[0] = 0x69; shadow[1] = 0x16; shadow[0x11] = 4;
	shadow[0x34] = 0x7c; shadow[0x35] = 0x15; /* 5500mV */
	shadow[0x46] = 4;
	assert(!nu1669_get_snapshot(&rx_psy, &sample));
	assert(sample.chip_id == 0x1669 && sample.protocol == 4 && sample.vout_mv == 5500);
	assert(sample.b2b_on == 0 && sample.b2b_state == 4);
	nu1669_poll(&rx.poll.work);
	assert(rx.valid);
	race_primary_only = true;
	assert(nu1669_get_snapshot(&rx_psy, &sample) == -EAGAIN);
	/* The thread has not run: the hard IRQ alone invalidates cached telemetry. */
	assert(rx.valid);
	assert(!nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_ONLINE, &val) && !val.intval);
	assert(nu1669_get_property(&rx_psy, POWER_SUPPLY_PROP_VOLTAGE_NOW, &val) == -ENODATA);
	race_primary_only = false;
	rx.suspended = true;
	assert(nu1669_get_snapshot(&rx_psy, &sample) == -EBUSY);
	puts("snapshot: typed provider, fresh fields, GPIO/I2C errors, hard IRQ before delayed thread passed");
}

static void authorization_tests(void)
{
	reset();
	assert(qcom_battmgr_dodge_pd_valid(&bm));
	gpio_value = -EIO;
	assert(!qcom_battmgr_dodge_pd_valid(&bm));
	assert(!bm.wireless_known && bm.dodge_power_off_pending);
	bm.dodge_otg_requested = true;
	assert(!qcom_battmgr_dodge_otg_allowed(&bm, 1, bm.dodge_otg_epoch));
	/* Physical presence veto survives absent/unreadable receiver telemetry. */
	gpio_value = 1;
	assert(!qcom_battmgr_dodge_otg_allowed(&bm, 1, bm.dodge_otg_epoch));
	assert(!rx.valid && bm.wireless_known && bm.wireless_present);

	reset();
	attach_on_request = true;
	assert(qcom_battmgr_dodge_pd_property(&bm, 123, 45, 1) == -ENOTCONN);
	assert(bm.dodge_otg_epoch == 1 && bm.dodge_power_off_pending);
	/* A coalesced attach/detach ending absent still revokes the old epoch. */
	reset();
	qcom_battmgr_wireless_notifier(&bm.wireless_nb, PSY_EVENT_PROP_CHANGED, &rx_psy);
	assert(bm.dodge_otg_epoch == 1 && bm.dodge_power_off_pending);
	assert(!qcom_battmgr_dodge_pd_current(&bm));
	int old = queued;
	qcom_battmgr_wireless_notifier(&bm.wireless_nb, 99, &rx_psy);
	assert(queued == old);
	bm.wireless_notifier_registered = true;
	qcom_battmgr_wireless_unregister(&bm);
	qcom_battmgr_wireless_unregister(&bm);
	assert(unregistered == 1 && !bm.wireless_notifier_registered);
	puts("authorization: GPIO error/presence veto, attach in request, coalesced edge, unregister passed");
}

static void worker_tests(void)
{
	reset();
	bm.dodge_otg_requested = true;
	bm.dodge_power_state = DODGE_POWER_ON;
	gpio_value = -EIO;
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(!on_writes && off_writes == 1);
	reset();
	bm.dodge_otg_requested = true;
	gpio_value = 1;
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(!on_writes && off_writes == 1);
	reset();
	bm.dodge_otg_requested = true;
	attach_on_enable = true;
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(on_writes == 1 && off_writes == 1 && bm.dodge_power_state == DODGE_POWER_OFF);
	assert(!glink_wls_queries); /* Linked provider replaces the wrong firmware value. */
	reset();
	bm.dodge_otg_requested = true;
	bm.dodge_power_state = DODGE_POWER_ON;
	qcom_battmgr_wireless_notifier(&bm.wireless_nb, PSY_EVENT_PROP_CHANGED, &rx_psy);
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(off_writes == 1 && on_writes == 1); /* Drain the coalesced edge before reenable. */
	reset();
	bm.dodge_otg_requested = bm.dodge_otg_prohibited = true;
	qcom_battmgr_wireless_notifier(&bm.wireless_nb, PSY_EVENT_PROP_CHANGED, &rx_psy);
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(bm.dodge_otg_prohibited && !on_writes && off_writes == 1);
	reset();
	bm.wireless_receiver = NULL;
	bm.dodge_otg_requested = true;
	glink_wls_online = 1;
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(glink_wls_queries == 1 && !on_writes && off_writes == 1);
	reset();
	bm.wireless_receiver = NULL;
	bm.dodge_otg_requested = true;
	qcom_battmgr_dodge_otg_worker(&bm.dodge_otg_work.work);
	assert(glink_wls_queries == 1 && on_writes == 1 && !off_writes);
	puts("OTG worker: error/attachment OFF, raced enable OFF, provider bypass, legacy paths passed");
}

int main(void)
{
	receiver_tests();
	snapshot_tests();
	authorization_tests();
	worker_tests();
	return 0;
}
