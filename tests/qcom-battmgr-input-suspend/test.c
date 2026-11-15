// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include "production-defines.h"
typedef uint32_t u32;
typedef uint32_t __le32;
typedef uint64_t u64;
#define S32_MAX INT32_MAX
#define PMIC_GLINK_OWNER_BATTMGR 32778
#define PMIC_GLINK_REQ_RESP 1
#define cpu_to_le32(v) (v)
#define le32_to_cpu(v) (v)
#define WRITE_ONCE(x, v) ((x) = (v))
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
#define DEFINE_DEBUGFS_ATTRIBUTE(...)
struct pmic_glink_hdr { __le32 owner, type, opcode; };
struct mutex { bool locked; };
struct qcom_battmgr {
 struct mutex lock;
 int dodge_otg_lock;
 bool service_up, dodge_otg_stopping, dodge_otg_broken, dodge_gauge_pending;
 u32 dodge_service_generation, dodge_input_suspend;
 int dodge_input_suspend_error;
 u32 dodge_voltage_word2, dodge_voltage_word13, dodge_voltage_words;
 int dodge_voltage_error;
};
static void mutex_lock(struct mutex *m) { assert(!m->locked); m->locked = true; }
static void mutex_unlock(struct mutex *m) { assert(m->locked); m->locked = false; }
static int qcom_battmgr_request(struct qcom_battmgr *bm, void *data, size_t len);
#include "production.c"
static struct qcom_battmgr_dodge_response reply;
static size_t reply_len;
static int fault, requests;
static int qcom_battmgr_request(struct qcom_battmgr *bm, void *data, size_t len)
{
 const struct qcom_battmgr_dodge_request *req = data;
 assert(bm->lock.locked && bm->dodge_gauge_pending);
 assert(len == sizeof(*req) && req->hdr.opcode == DODGE_GAUGE_OPCODE);
 assert(req->data_size == DODGE_GAUGE_WORDS * sizeof(__le32));
 requests++;
 if (fault == 1) return -ETIMEDOUT;
 if (fault == 5) return 0;
 if (fault == 2) bm->service_up = false;
 if (fault == 3) bm->dodge_service_generation++;
 if (fault == 4) bm->dodge_otg_stopping = true;
 u32 gauge[9];
 int ret = qcom_battmgr_dodge_decode(&reply, reply_len, gauge);
 bm->dodge_input_suspend_error = ret ?:
  qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &bm->dodge_input_suspend);
 bm->dodge_voltage_error = ret ?:
  qcom_battmgr_dodge_decode_voltage_samples(&reply, reply_len,
   &bm->dodge_voltage_word2, &bm->dodge_voltage_word13, &bm->dodge_voltage_words);
 return ret;
}
static void packet(void)
{
 memset(&reply, 0, sizeof(reply));
 reply.hdr = (struct pmic_glink_hdr) { PMIC_GLINK_OWNER_BATTMGR, PMIC_GLINK_REQ_RESP, DODGE_GAUGE_OPCODE };
 reply.data_size = 40;
 reply.data[9] = 1;
 reply_len = sizeof(reply);
}
static void voltage_samples(void)
{
 struct qcom_battmgr bm = { .service_up = true, .dodge_service_generation = 7 };
 u32 w2, w13, words, generation, gauge[9];
 fault = 0; packet(); reply.data[2] = UINT32_MAX; reply.data[13] = UINT32_MAX;
 for (int count = 9; count <= 14; count++) {
  reply.data_size = count * 4;
  w2 = w13 = words = generation = 99;
  assert(!qcom_battmgr_dodge_decode(&reply, reply_len, gauge));
  int ret = qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation);
  if (count < 14) assert(ret == -ENODATA && w2 == 99 && w13 == 99 && words == 99 && generation == 99);
  else assert(!ret && w2 == UINT32_MAX && w13 == UINT32_MAX && words == 14 && generation == 7);
 }
 reply.data_size = 128 * 4;
 assert(!qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation) && words == 128);
 reply.data_size = 36; w2 = w13 = words = generation = 99;
 assert(qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation) == -ENODATA);
 assert(w2 == 99 && w13 == 99 && words == 99 && generation == 99);
 for (int malformed = 0; malformed < 4; malformed++) {
  packet(); reply.data_size = 56;
  if (malformed == 0) reply.hdr.owner++;
  if (malformed == 1) reply_len--;
  if (malformed == 2) reply.data_size = 55;
  if (malformed == 3) reply.data_size = 516;
  assert(qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation) == -EPROTO);
  assert(w2 == 99 && w13 == 99 && words == 99 && generation == 99);
 }
 for (fault = 1; fault <= 5; fault++) {
  packet(); reply.data_size = 56;
  bm = (struct qcom_battmgr) { .service_up = true, .dodge_service_generation = 7 };
  int ret = qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation);
  assert(ret == (fault == 1 ? -ETIMEDOUT : fault == 5 ? -ENODATA : -ENOTCONN));
  assert(w2 == 99 && w13 == 99 && words == 99 && generation == 99 && !bm.lock.locked);
  if (fault == 1) {
   int before = requests;
   assert(qcom_battmgr_dodge_normal_voltage_samples_get(&bm, &w2, &w13, &words, &generation) == -ENOTCONN && requests == before);
  }
 }
 puts("raw voltage samples:9/13word compatibility,14+ same-response rawpair/fullu32/declaredwords/gen, malformed/stale/transport/lifecycle/timeout failures passed; zero SET");
}

int main(void)
{
 u32 gauge[9], value = 99;
 packet();
 assert(!qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &value) && value == 1);
 reply.data[9] = 0;
 assert(!qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &value) && !value);
 reply.data_size = 36;
 assert(!qcom_battmgr_dodge_decode(&reply, reply_len, gauge));
 assert(qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &value) == -ENODATA);
 packet(); reply.data[9] = 2;
 assert(!qcom_battmgr_dodge_decode(&reply, reply_len, gauge));
 assert(qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &value) == -EPROTO);
 for (int i = 0; i < 6; i++) {
  packet();
  if (i == 0) reply.hdr.owner++;
  if (i == 1) reply.hdr.type++;
  if (i == 2) reply.hdr.opcode++;
  if (i == 3) reply_len--;
  if (i == 4) reply.data_size = 39;
  if (i == 5) reply.data_size = 516;
  assert(qcom_battmgr_dodge_decode_input_suspend(&reply, reply_len, &value) == -EPROTO);
 }
 struct qcom_battmgr bm = { .service_up = true, .dodge_service_generation = 7 };
 u64 output = 99;
 packet();
 assert(!qcom_battmgr_dodge_normal_input_suspend_get(&bm, &output) && output == 1);
 reply.data_size = 36; output = 99;
 assert(qcom_battmgr_dodge_normal_input_suspend_get(&bm, &output) == -ENODATA && output == 99);
 packet(); reply.data[9] = 3;
 assert(qcom_battmgr_dodge_normal_input_suspend_get(&bm, &output) == -EPROTO && output == 99);
 for (fault = 1; fault <= 5; fault++) {
  packet(); bm = (struct qcom_battmgr) { .service_up = true, .dodge_service_generation = 7 };
  assert(qcom_battmgr_dodge_normal_input_suspend_get(&bm, &output) == (fault == 1 ? -ETIMEDOUT : fault == 5 ? -ENODATA : -ENOTCONN));
  assert(output == 99 && !bm.lock.locked && !bm.dodge_gauge_pending);
  if (fault == 1) {
   int before = requests;
   assert(bm.dodge_otg_broken);
   assert(qcom_battmgr_dodge_normal_input_suspend_get(&bm, &output) == -ENOTCONN);
   assert(requests == before);
  }
 }
 voltage_samples();
 puts("optional input suspend: nine-word compatibility, strict fresh decode, no stale output, service/lifecycle/timeout retirement passed");
}
