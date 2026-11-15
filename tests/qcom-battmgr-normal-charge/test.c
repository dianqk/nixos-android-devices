// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "production-defines.h"

typedef uint8_t u8;
typedef uint16_t __le16;
typedef uint32_t u32;
typedef uint32_t __le32;
typedef uint64_t u64;
struct pmic_glink_hdr { __le32 owner, type, opcode; };
struct mutex { bool locked; };
struct completion { bool done; };
struct delayed_work { int unused; };
struct dentry { int unused; };
struct qcom_battmgr {
	struct mutex lock;
	int dodge_otg_lock;
	struct completion dodge_otg_ack;
	struct delayed_work dodge_otg_work;
	struct dentry *dodge_debugfs;
	void *client;
	bool service_up, dodge_otg_stopping, dodge_otg_broken;
	bool dodge_power_ambiguous, dodge_otg_pending;
	u32 dodge_service_generation, dodge_otg_opcode, dodge_otg_property, dodge_otg_value;
	int dodge_otg_error;
};
#define PMIC_GLINK_OWNER_BATTMGR 32778
#define PMIC_GLINK_REQ_RESP 1
#define HZ 100
#define cpu_to_le32(v) ((u32)(v))
#define le32_to_cpu(v) ((u32)(v))
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
static void *system_percpu_wq;
static int submitted, queued, removed;
static bool wireless, limits;
static int limit_stage, fault_at;
static u32 limit_current, limit_voltage;
static int (*getter)(void *, u64 *);
static u32 response;
static enum { GOOD, BAD_LENGTH, BAD_TYPE, BAD_OPCODE, BAD_PROPERTY, REMOTE_ERROR,
	      TIMEOUT, SERVICE_GONE, GENERATION_CHANGED, STOPPED, SEND_ERROR } fault;
static void mutex_lock(struct mutex *lock) { assert(!lock->locked); lock->locked = true; }
static void mutex_unlock(struct mutex *lock) { assert(lock->locked); lock->locked = false; }
static void reinit_completion(struct completion *c) { c->done = false; }
static void complete(struct completion *c) { c->done = true; }
static unsigned long wait_for_completion_timeout(struct completion *c, int timeout)
{
	return c->done;
}
static int qcom_battmgr_wireless_present(struct qcom_battmgr *bm, bool event)
{
	assert(!"raw battery GET must not query a receiver");
	return -EIO;
}
static void mod_delayed_work(void *wq, struct delayed_work *work, int delay) { queued++; }
static void debugfs_remove_recursive(struct dentry *dentry) { if (dentry) removed++; }
static void qcom_battmgr_input_probe_close(struct qcom_battmgr *bm) {}
static int pmic_glink_send(void *client, const void *data, size_t len);
#include "production.c"

static int pmic_glink_send(void *client, const void *data, size_t len)
{
	struct qcom_battmgr *bm = client;
	const struct qcom_battmgr_property_request *req = data;
	struct qcom_battmgr_message reply = {};
	size_t reply_len = sizeof(reply.hdr) + sizeof(reply.intval);
	int active_fault = (!limits || ++limit_stage == fault_at) ? fault : GOOD;
	assert(bm->lock.locked);
	assert(len == sizeof(*req));
	assert(le32_to_cpu(req->hdr.owner) == 32778);
	assert(le32_to_cpu(req->hdr.type) == 1);
	assert(le32_to_cpu(req->hdr.opcode) == (!limits && wireless ? 0x34 : 0x30)); /* Any SET fails the test. */
	assert(le32_to_cpu(req->battery) == 0);
	assert(le32_to_cpu(req->property) == (limits ? (limit_stage == 1 ? 10 : 8) : wireless ? 8 : 24));
	assert(le32_to_cpu(req->value) == 0);
	submitted++;
	if (active_fault == SEND_ERROR)
		return -EIO;
	if (active_fault == TIMEOUT)
		return 0;
	reply.hdr = req->hdr;
	reply.intval.property = req->property;
	reply.intval.value = cpu_to_le32(limits ? (limit_stage == 1 ? limit_current : limit_voltage) : response);
	if (active_fault == BAD_LENGTH)
		reply_len--;
	if (active_fault == BAD_TYPE)
		reply.hdr.type = cpu_to_le32(2);
	if (active_fault == BAD_OPCODE)
		reply.hdr.opcode = cpu_to_le32(0x31);
	if (active_fault == BAD_PROPERTY)
		reply.intval.property = cpu_to_le32(25);
	if (active_fault == REMOTE_ERROR)
		reply.intval.result = cpu_to_le32(1);
	qcom_battmgr_dodge_otg_reply(bm, &reply, reply_len);
	if (active_fault == SERVICE_GONE)
		bm->service_up = false;
	if (active_fault == GENERATION_CHANGED)
		bm->dodge_service_generation++;
	if (active_fault == STOPPED)
		bm->dodge_otg_stopping = true;
	return 0;
}

static struct qcom_battmgr bm;
static void reset(void)
{
	memset(&bm, 0, sizeof(bm));
	bm.service_up = true;
	bm.dodge_service_generation = 7;
	bm.client = &bm;
	submitted = queued = removed = 0;
	fault = GOOD;
	response = 0;
	limit_stage = fault_at = 0;
}

static void run(void)
{
	u64 value;
	for (u32 expected = 0; expected <= 1; expected++) {
		reset();
		value = 99;
		response = expected;
		assert(!getter(&bm, &value));
		assert(value == expected && submitted == 1 && !queued);
	}
	if (!wireless) for (u32 invalid = 2; ; invalid = UINT32_MAX) {
		reset();
		value = 99;
		response = invalid;
		assert(getter(&bm, &value) == -EPROTO);
		assert(value == 99 && submitted == 1);
		if (invalid == UINT32_MAX)
			break;
	}
	for (int malformed = BAD_LENGTH; malformed <= BAD_PROPERTY; malformed++) {
		reset();
		value = 99;
		fault = malformed;
		assert(getter(&bm, &value) == -ETIMEDOUT);
		assert(value == 99 && submitted == 1 && bm.dodge_otg_broken && queued == 1);
		assert(getter(&bm, &value) == -ENOTCONN);
		assert(submitted == 1); /* No retry after an ambiguous response. */
	}
	reset();
	fault = REMOTE_ERROR;
	assert(getter(&bm, &value) == -EREMOTEIO);
	reset();
	fault = TIMEOUT;
	assert(getter(&bm, &value) == -ETIMEDOUT);
	assert(bm.dodge_otg_broken && queued == 1 && submitted == 1);
	for (int change = SERVICE_GONE; change <= STOPPED; change++) {
		reset();
		value = 99;
		fault = change;
		assert(getter(&bm, &value) == -ENOTCONN);
		assert(value == 99 && submitted == 1);
	}
	reset();
	bm.service_up = false;
	assert(getter(&bm, &value) == -ENOTCONN);
	assert(!submitted);
	reset();
	bm.dodge_otg_stopping = true;
	assert(getter(&bm, &value) == -ENOTCONN);
	assert(!submitted);
	reset();
	fault = SEND_ERROR;
	assert(getter(&bm, &value) == -EIO);
	reset();
	struct dentry entry;
	bm.dodge_debugfs = &entry;
	qcom_battmgr_dodge_debugfs_remove(&bm);
	qcom_battmgr_dodge_debugfs_remove(&bm);
	assert(!bm.dodge_debugfs && removed == 1);
	if (!wireless) puts("raw GET: bool0/1, invalid values, malformed replies, remote failure, timeout, service/generation/stop, no retry and cleanup passed; all submitted requests GET0x30/BATT24/value0/battery0, zero SET");
	if (wireless) {
		reset(); response = UINT32_MAX;
		assert(!getter(&bm, &value) && value == UINT32_MAX);
	}
}
static void charge_limits(void)
{
	u32 current, voltage;
	limits = true;
	reset(); limit_current = limit_voltage = UINT32_MAX;
	assert(!qcom_battmgr_dodge_normal_charge_limits_get(&bm, &current, &voltage));
	assert(current == UINT32_MAX && voltage == UINT32_MAX && submitted == 2);
	reset(); limit_current = limit_voltage = 0;
	assert(!qcom_battmgr_dodge_normal_charge_limits_get(&bm, &current, &voltage));
	assert(!current && !voltage && submitted == 2);
	for (int stage = 1; stage <= 2; stage++) {
		for (int f = BAD_LENGTH; f <= SEND_ERROR; f++) {
			reset(); fault_at = stage; fault = f;
			current = 123; voltage = 456;
			assert(qcom_battmgr_dodge_normal_charge_limits_get(&bm, &current, &voltage));
			assert(current == 123 && voltage == 456 && !bm.lock.locked);
			assert(submitted == stage);
		}
	}
	puts("normal charge limits: fresh GET10/GET8, full-u32 pair, no partial/stale output on malformed/error/service/lifecycle failures; zero SET");
}

int main(void)
{
 getter = qcom_battmgr_dodge_normal_charge_enable_get;
 run();
 wireless = true;
 getter = qcom_battmgr_dodge_wireless_input_current_limit_get;
 run();
 puts("wireless ICL: raw full-u32 GET0x34/WLS8/value0/battery0, malformed replies, errors and generation checks passed; zero SET");
 charge_limits();
 return 0;
}
