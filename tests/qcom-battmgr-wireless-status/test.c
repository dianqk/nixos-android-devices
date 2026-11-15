// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "defines.h"
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint32_t __le32;
typedef int32_t s32;
struct pmic_glink_hdr { __le32 owner, type, opcode; };
#include "types.h"
#define S32_MAX INT32_MAX
#define S32_MIN INT32_MIN
#define PMIC_GLINK_OWNER_BATTMGR 32778
#define PMIC_GLINK_REQ_RESP 1
#define cpu_to_le32(v) (v)
#define le32_to_cpu(v) (v)
#define READ_ONCE(v) (v)
#define WRITE_ONCE(v, value) ((v) = (value))
#define BIT(n) (1u << (n))
#define HZ 100
#define time_after_eq(a,b) ((long)((a)-(b)) >= 0)
#define DIV_ROUND_CLOSEST(a,b) (((a) + (b)/2)/(b))
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
enum power_supply_property { POWER_SUPPLY_PROP_STATUS, POWER_SUPPLY_PROP_HEALTH, POWER_SUPPLY_PROP_PRESENT, POWER_SUPPLY_PROP_TECHNOLOGY, POWER_SUPPLY_PROP_TEMP, POWER_SUPPLY_PROP_CURRENT_NOW, POWER_SUPPLY_PROP_CAPACITY, POWER_SUPPLY_PROP_CYCLE_COUNT, POWER_SUPPLY_PROP_STATE_OF_HEALTH, POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR };
enum { POWER_SUPPLY_STATUS_UNKNOWN, POWER_SUPPLY_STATUS_CHARGING, POWER_SUPPLY_STATUS_DISCHARGING, POWER_SUPPLY_STATUS_NOT_CHARGING, POWER_SUPPLY_STATUS_FULL };
union power_supply_propval { int intval; };
struct mutex { bool locked; };
struct power_supply { void *data; };
struct qcom_battmgr {
 struct mutex lock;
 int dodge_otg_lock;
 bool service_up, dodge_otg_stopping, dodge_gauge_valid, dodge_gauge_pending;
 u32 dodge_service_generation, input_usb_epoch, dodge_gauge_generation, dodge_gauge[9];
 unsigned long dodge_gauge_updated;
 struct { int status; } status;
 struct { int online; } usb;
 struct power_supply *wireless_receiver;
};
static struct qcom_battmgr bm;
static struct power_supply battery = { .data = &bm }, receiver;
static unsigned long jiffies = 100;
static int present, present_error, online, fw_status, gauge_error, requests, gauges, snapshots;
static int step, inject_at, property_error, info_error;
static u32 raw_current;
static enum { NONE, SERVICE, USB_EVENT, RECEIVER_EDGE, DETACH, STOP, IO_ERROR } event;
static struct nu1669_snapshot fresh;
static void mutex_lock(struct mutex *m) { assert(!m->locked); m->locked = true; }
static void mutex_unlock(struct mutex *m) { assert(m->locked); m->locked = false; }
static void *power_supply_get_drvdata(struct power_supply *psy) { return psy->data; }
static void boundary(void)
{
 step++;
 if (!inject_at || step != inject_at) return;
 if (event == SERVICE) bm.dodge_service_generation++;
 if (event == USB_EVENT) bm.input_usb_epoch++;
 if (event == RECEIVER_EDGE) fresh.generation++;
 if (event == DETACH) present = 0;
 if (event == STOP) bm.dodge_otg_stopping = true;
 if (event == IO_ERROR) property_error = gauge_error = info_error = present_error = -EIO;
}
static int power_supply_get_property(struct power_supply *psy, enum power_supply_property prop, union power_supply_propval *value)
{
 assert(psy == &receiver && prop == POWER_SUPPLY_PROP_PRESENT);
 boundary(); if (present_error) return present_error;
 value->intval = present; return 0;
}
static int nu1669_get_snapshot(struct power_supply *psy, struct nu1669_snapshot *snapshot)
{
 assert(bm.lock.locked && psy == &receiver); snapshots++; boundary();
 if (info_error) return info_error;
 if (!present) return -ENODEV;
 *snapshot = fresh; return 0;
}
static int qcom_battmgr_charge_get_behaviour(struct qcom_battmgr *bm, union power_supply_propval *val) { assert(!"unexpected policy path"); return -EIO; }
static int qcom_battmgr_bat_get_property(struct power_supply *psy, enum power_supply_property psp, union power_supply_propval *val) { assert(!"STATUS escaped to generic getter"); return -EIO; }
static int qcom_battmgr_request(struct qcom_battmgr *bm, void *data, size_t len);
#include "production.c"
static int qcom_battmgr_request(struct qcom_battmgr *bm, void *data, size_t len)
{
 const struct qcom_battmgr_property_request *req = data;
 assert(bm->lock.locked && req->hdr.owner == 32778 && req->hdr.type == 1);
 boundary(); requests++;
 if (req->hdr.opcode == DODGE_GAUGE_OPCODE) {
  assert(len == sizeof(struct qcom_battmgr_dodge_request) && bm->dodge_gauge_pending);
  gauges++; if (gauge_error) return gauge_error;
  struct qcom_battmgr_dodge_response response = { .hdr = req->hdr, .data_size = 36 };
  response.data[1] = raw_current; response.data[3] = 10000;
  return qcom_battmgr_dodge_decode(&response, sizeof(response), bm->dodge_gauge);
 }
 assert(len == sizeof(*req) && req->battery == 0 && req->value == 0);
 if (property_error) return property_error;
 if (req->hdr.opcode == BATTMGR_BAT_PROPERTY_GET) { assert(req->property == BATT_STATUS); bm->status.status = fw_status; }
 else { assert(req->hdr.opcode == BATTMGR_USB_PROPERTY_GET && req->property == USB_ONLINE); bm->usb.online = online; }
 return 0;
}
static void reset(void)
{
 memset(&bm, 0, sizeof(bm)); bm.service_up = true; bm.dodge_service_generation = 7; bm.wireless_receiver = &receiver;
 present = 1; online = 0; fw_status = POWER_SUPPLY_STATUS_DISCHARGING;
 present_error = gauge_error = property_error = info_error = requests = gauges = snapshots = step = inject_at = 0;
 event = NONE; raw_current = (u32)-200000;
 fresh = (struct nu1669_snapshot) { .generation = 11, .chip_id = 0x1669, .fw_version = 0x6b, .protocol = 4, .vout_mv = 5500 };
}
static int status(int *result)
{
 union power_supply_propval val = { .intval = 99 };
 int ret = qcom_battmgr_dodge_get_property(&battery, POWER_SUPPLY_PROP_STATUS, &val);
 *result = val.intval; assert(!bm.lock.locked); return ret;
}
int main(void)
{
 int output;
 int currents[] = { INT32_MAX, 200000, 50001, 50000, 1, 0, -1, -50000, -50001, -200000, -INT32_MAX };
 for (size_t i = 0; i < sizeof(currents)/sizeof(currents[0]); i++) {
  reset(); raw_current = (u32)-currents[i];
  int expected = currents[i] > 50000 ? POWER_SUPPLY_STATUS_CHARGING : currents[i] < -50000 ? POWER_SUPPLY_STATUS_DISCHARGING : POWER_SUPPLY_STATUS_NOT_CHARGING;
  assert(!status(&output) && output == expected && gauges == 1 && snapshots == 2);
  assert(bm.dodge_gauge_valid && bm.dodge_gauge_generation == 7);
  union power_supply_propval current; assert(!qcom_battmgr_dodge_get_property(&battery, POWER_SUPPLY_PROP_CURRENT_NOW, &current));
  assert(current.intval == currents[i] && gauges == 1); /* Coherent uevent gauge cache. */
 }
 reset(); bm.dodge_gauge_valid = true; bm.dodge_gauge_generation = 7; bm.dodge_gauge_updated = jiffies;
 bm.dodge_gauge[1] = 100000; assert(!status(&output) && output == POWER_SUPPLY_STATUS_CHARGING && gauges == 1);
 reset(); raw_current = 0; bm.status.status = POWER_SUPPLY_STATUS_FULL;
 assert(!status(&output) && output == POWER_SUPPLY_STATUS_NOT_CHARGING); /* Fresh FW supersedes stale FULL. */
 reset(); raw_current = 0; fw_status = POWER_SUPPLY_STATUS_FULL;
 assert(!status(&output) && output == POWER_SUPPLY_STATUS_FULL);
 reset(); fw_status = POWER_SUPPLY_STATUS_FULL; assert(!status(&output) && output == POWER_SUPPLY_STATUS_CHARGING);
 reset(); raw_current = 100000; fw_status = POWER_SUPPLY_STATUS_FULL; assert(!status(&output) && output == POWER_SUPPLY_STATUS_DISCHARGING);
 for (int fallback = 0; fallback < 4; fallback++) {
  reset(); fw_status = POWER_SUPPLY_STATUS_FULL;
  if (fallback == 0) bm.wireless_receiver = NULL;
  if (fallback == 1) present = 0;
  if (fallback == 2) { online = 1; present_error = -EIO; }
  if (fallback == 3) fresh.protocol = 0x31;
  assert(!status(&output) && output == POWER_SUPPLY_STATUS_FULL && !gauges);
 }
 for (int failure = 0; failure < 6; failure++) {
  reset(); bm.status.status = POWER_SUPPLY_STATUS_FULL;
  if (failure == 0) property_error = 1;
  if (failure == 1) present_error = -EIO;
  if (failure == 2) info_error = -EREMOTEIO;
  if (failure == 3) gauge_error = -ETIMEDOUT;
  if (failure == 4) raw_current = UINT32_C(0x80000000);
  if (failure == 5) bm.service_up = false;
  assert(status(&output) && output == 99);
 }
 reset(); assert(!status(&output)); int total = step;
 for (int e = SERVICE; e <= IO_ERROR; e++) {
  for (int at = 1; at <= total; at++) {
   reset(); event = e; inject_at = at;
   int ret = status(&output);
   if (!ret) { /* A source transition before qualification may legitimately select fallback/new baseline. */
    assert((e == DETACH && at <= 2 && output == POWER_SUPPLY_STATUS_DISCHARGING) ||
           (e == RECEIVER_EDGE && at <= 4 && output == POWER_SUPPLY_STATUS_CHARGING) ||
           (e == USB_EVENT && at <= 4 && output == POWER_SUPPLY_STATUS_CHARGING));
   } else assert(output == 99);
  }
 }
 printf("wireless STATUS: signed gauge/50mA boundaries, fresh FULL only nearzero, wired/absent fallback, errors/no stale output, CURRENT coherence and %d generation/source boundaries passed; all requests GET/read-only\n", total);
 return 0;
}
