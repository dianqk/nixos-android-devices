// SPDX-License-Identifier: GPL-2.0-only
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <pthread.h>
#include <sys/types.h>
#include <unistd.h>
#include "production-defines.h"
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef struct { u32 value; } atomic_t;
#define ATOMIC_INIT(v) { (v) }
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
static void atomic_set(atomic_t *v, u32 value) { v->value = value; }
static u32 atomic_read(atomic_t *v) { return __atomic_load_n(&v->value, __ATOMIC_SEQ_CST); }
static void atomic_inc(atomic_t *v) { __atomic_add_fetch(&v->value, 1, __ATOMIC_SEQ_CST); }
struct mutex { pthread_mutex_t native; bool locked; };
struct gpio_desc { int unused; };
struct regmap { int unused; };
struct device { int unused; };
struct delayed_work { int unused; };
struct dentry { int unused; };
struct power_supply { void *data, *desc; };
struct file { void *private_data; };
struct seq_file { void *private; int reply_prints, unavailable_prints; };
#define BIT(n) (UINT32_C(1) << (n))
#define GENMASK(h, l) ((UINT32_MAX >> (31 - (h))) & (UINT32_MAX << (l)))
#define U32_MAX UINT32_MAX
#define HZ 1000
#define xchg(p, v) __atomic_exchange_n((p), (v), __ATOMIC_SEQ_CST)
#define READ_ONCE(x) __atomic_load_n(&(x), __ATOMIC_SEQ_CST)
#define time_after_eq(a, b) ((long)((a) - (b)) >= 0)
#define __user
#define EXPORT_SYMBOL_GPL(x)
static unsigned long jiffies;
static int nu1669_psy_desc;
static void mutex_lock(struct mutex *m) { assert(!pthread_mutex_lock(&m->native)); m->locked = true; }
static void mutex_unlock(struct mutex *m) { assert(m->locked); m->locked = false; assert(!pthread_mutex_unlock(&m->native)); }
static int mutex_trylock(struct mutex *m) { int ret = pthread_mutex_trylock(&m->native); assert(!ret || ret == EBUSY); if (!ret) m->locked = true; return !ret; }
static void *power_supply_get_drvdata(struct power_supply *psy) { return psy->data; }
static u16 get_unaligned_le16(const void *data) { const u8 *p = data; return p[0] | (u16)p[1] << 8; }
static u32 get_unaligned_le32(const void *data) { const u8 *p = data; return get_unaligned_le16(p) | (u32)get_unaligned_le16(p + 2) << 16; }
static int copy_from_user(void *to, const void *from, size_t size) { memcpy(to, from, size); return 0; }
static void seq_printf(struct seq_file *s, const char *format, ...) { if (!strcmp(format, "reply=%*ph\n")) s->reply_prints++; }
static void seq_puts(struct seq_file *s, const char *value) { assert(!strcmp(value, "reply=unavailable\n")); s->unavailable_prints++; }
static int gpiod_get_value_cansleep(struct gpio_desc *gpio);
static int regmap_bulk_read(struct regmap *map, unsigned int reg, void *data, size_t size);
static int regmap_read(struct regmap *map, unsigned int reg, unsigned int *value);
static int regmap_write(struct regmap *map, unsigned int reg, unsigned int value);
static int regmap_bulk_write(struct regmap *map, unsigned int reg, const void *data, size_t size);
static void disable_irq(int irq);
static void cancel_delayed_work_sync(struct delayed_work *work);
static void debugfs_remove_recursive(struct dentry *entry);
static void msleep(unsigned int ms);
static void usleep_range(unsigned long low, unsigned long high);
#include "production.c"

static struct nu1669 rx;
static struct power_supply psy = { .data = &rx, .desc = &nu1669_psy_desc };
static u8 info[NU1669_INFO_SIZE], bc[6], pending[10], fod[NU1669_FOD_SHADOW_SIZE];
static int fod_reads, info_reads, bpp_step;
static bool bpp_test;
static bool fod_torn, identity_changed, mag_changed;
static unsigned int flags, busy, length, stage;
static int gpio_value, writes, queries, acks, steps, inject_at, bc_reads, response_reads;
static bool io_error, response_pending, initialized;
static enum { GOOD, NO_REPLY, BUSY, COMMIT_BUSY, ACK_STUCK, ACK_LOSS, NEW_FAULT,
              TORN, BAD_FRAME, UNRELATED, NEW_TIMEOUT, ALL_ONES, STALE_LATE, UNRELATED_REPEAT, IDENTITY_CHANGE, PATH_CHANGE, ACK_NEW_FAULT } mode;
static enum { NONE, EDGE, DETACH, SUSPEND, STOP, IO_FAIL } event;
static pthread_mutex_t barrier = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static bool block_query, query_blocked, unblock;
static int snapshot_done, irq_disabled, work_cancelled, debugfs_removed, query_ret;

static void disable_irq(int irq) { irq_disabled++; }
static void cancel_delayed_work_sync(struct delayed_work *work) { work_cancelled++; }
static void debugfs_remove_recursive(struct dentry *entry)
{
 assert(rx.stopped && !rx.lock.locked && !rx.result_valid && irq_disabled && work_cancelled);
 if (entry) debugfs_removed++;
}

static void boundary(void)
{
 steps++;
 if (!inject_at || steps != inject_at) return;
 if (event == EDGE) atomic_inc(&rx.generation);
 if (event == DETACH) { gpio_value = 0; atomic_inc(&rx.generation); }
 if (event == SUSPEND) { rx.suspended = true; atomic_inc(&rx.generation); }
 if (event == STOP) { rx.stopped = true; atomic_inc(&rx.generation); }
 if (event == IO_FAIL) { io_error = true; gpio_value = -EIO; }
}
static int gpiod_get_value_cansleep(struct gpio_desc *gpio) { boundary(); return gpio_value; }
static int regmap_bulk_read(struct regmap *map, unsigned int reg, void *data, size_t size)
{
 assert(rx.lock.locked);
 boundary();
 if (io_error) return -EIO;
 if (reg == NU1669_INFO_BASE) {
  assert(size == sizeof(info)); memcpy(data, info, size); info_reads++;
  if (info_reads == 2 && identity_changed) ((u8 *)data)[4] ^= 1;
  if (info_reads == 2 && mag_changed) ((u8 *)data)[0x18] ^= 1;
 }
 else if (reg == NU1669_FOD_SHADOW) {
  assert(size == 43); memcpy(data, fod, size); fod_reads++;
  if (fod_torn && fod_reads == 2) ((u8 *)data)[42] ^= 1;
 }
 else if (reg == NU1669_FLAGS) {
  assert(size == 4);
  if (response_pending && ++response_reads >= 2 && mode != NO_REPLY) {
   flags |= BIT(12);
   if (mode == NEW_TIMEOUT) flags |= BIT(11);
   else if (mode == NEW_FAULT) flags |= BIT(0);
   else {
    flags |= NU1669_RX_DATA;
    u8 frame[] = { 0x5f, 0x05, 0xa1, 0xb2, 0xc3, 0xd4 };
    memcpy(bc, frame, 6);
    if (mode == BAD_FRAME) bc[0] = 0;
    if ((mode == UNRELATED && !acks) || mode == UNRELATED_REPEAT) { bc[0] = 0x4f; bc[1] = 0xa5; bc[2] = 0x5a; bc[3] = 0; bc[4] = 0xff; }
   }
  }
  u8 *p = data;
  for (int i = 0; i < 4; i++) p[i] = flags >> (i * 8);
 } else {
  assert(reg == NU1669_BC && size == 6);
  memcpy(data, bc, size);
  if (mode == TORN && ++bc_reads % 2 == 0) ((u8 *)data)[5] ^= 1;
 }
 return 0;
}
static int regmap_read(struct regmap *map, unsigned int reg, unsigned int *value)
{
 assert(rx.lock.locked && reg == NU1669_BUSY);
 boundary();
 if (io_error) return -EIO;
 *value = busy;
 return 0;
}
static int regmap_write(struct regmap *map, unsigned int reg, unsigned int value)
{
 assert(rx.lock.locked);
 writes++;
 if (reg == NU1669_BUSY) {
  assert(!stage && !busy && value == 1);
  busy = 1; stage = 1;
  if (block_query) {
   pthread_mutex_lock(&barrier); query_blocked = true; pthread_cond_broadcast(&condition);
   while (!unblock) pthread_cond_wait(&condition, &barrier);
   pthread_mutex_unlock(&barrier);
  }
 } else if (reg == 0) {
  assert(stage == 1 && (bpp_test ? value == 1 || value == 10 : value == 4 || value == 5)); length = value; stage = 2;
 } else {
  assert(reg == 0x60 && stage == 3);
  if (bpp_test) {
   static const u8 objects[] = { 0x18, 0xa1, 0xa3, 0xad, 0xb7, 0xc1, 0xa0 };
   assert(bpp_step < 7 && value == objects[bpp_step]);
   if (bpp_step == 0) { assert(length == 1 && pending[0] == 0); info[0x18] = 0; }
   else if (bpp_step == 1) { assert(length == 1 && pending[0] == 40); fod[1] = 12; }
   else if (bpp_step == 6) { assert(length == 1 && pending[0] == 1); fod[0] = 1; }
   else { assert(length == 10 && !memcmp(pending, rx.bpp_parameters + (bpp_step - 2) * 10, 10)); memcpy(fod + 3 + (bpp_step - 2) * 10, pending, 10); }
   bpp_step++;
  } else if (value == 0x51) {
   assert(length == 5 && pending[0] == 0x18 && pending[1] == 5 && !pending[2] && !pending[3] && !pending[4]);
   assert(!(flags & NU1669_RX_DATA));
   queries++; response_pending = true;
  } else {
   assert(value == 0x28 && length == 4 && !pending[0] && pending[1] == 4 && !pending[2] && !pending[3]);
   acks++;
   if (mode != ACK_STUCK) flags &= ~NU1669_RX_DATA;
   if (mode == ACK_LOSS) flags = 0;
   if (mode == ACK_NEW_FAULT) flags |= BIT(0);
   response_pending = mode == UNRELATED_REPEAT;
   if (response_pending) response_reads = 0;
  }
  stage = 0; busy = mode == COMMIT_BUSY ? 1 : 0;
 }
 boundary();
 return io_error ? -EIO : 0;
}
static int regmap_bulk_write(struct regmap *map, unsigned int reg, const void *data, size_t size)
{
 assert(rx.lock.locked && reg == 1 && stage == 2 && size == length);
 assert(bpp_test ? size == 1 || size == 10 : size == 4 || size == 5);
 memcpy(pending, data, size); writes++; stage = 3;
 if (size == 5 && mode == STALE_LATE) flags |= NU1669_RX_DATA;
 if (size == 5 && mode == IDENTITY_CHANGE) info[4]++;
 if (size == 5 && mode == PATH_CHANGE) info[0x44] = 1;
 boundary();
 return io_error ? -EIO : 0;
}
static void msleep(unsigned int ms) { jiffies += ms; boundary(); }
static void usleep_range(unsigned long low, unsigned long high) { assert(low == 1000 && high == 2000); msleep(1); }
static void reset(void)
{
 bpp_test = false; bpp_step = 0; atomic_set(&nu1669_bpp_uncertain, 0);
 if (initialized) assert(!pthread_mutex_destroy(&rx.lock.native));
 memset(&rx, 0, sizeof(rx));
 pthread_mutexattr_t attr; pthread_mutexattr_init(&attr);
 pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
 assert(!pthread_mutex_init(&rx.lock.native, &attr)); pthread_mutexattr_destroy(&attr); initialized = true;
 memset(info, 0, sizeof(info)); info[0] = 0x69; info[1] = 0x16; info[3] = 4; info[4] = 0x6b;
 info[0x11] = 4; info[0x34] = 0x7c; info[0x35] = 0x15; info[0x46] = 4;
 memset(bc, 0, sizeof(bc));
 for (size_t i = 0; i < sizeof(fod); i++) fod[i] = i * 7;
 fod_reads = info_reads = 0; fod_torn = identity_changed = mag_changed = false;
 flags = BIT(7); busy = stage = length = 0;
 gpio_value = 1; writes = queries = acks = steps = inject_at = bc_reads = response_reads = 0;
 jiffies = 0; mode = GOOD; event = NONE; io_error = response_pending = false;
 block_query = query_blocked = unblock = false;
 snapshot_done = irq_disabled = work_cancelled = debugfs_removed = query_ret = 0;
}
static void show(bool expected)
{
 struct seq_file s = { .private = &rx };
 assert(!nu1669_last_tx_id_show(&s, NULL));
 assert(s.reply_prints == expected && s.unavailable_prints == !expected);
}
static void basic(void)
{
 reset();
 for (unsigned int reg = 0; reg < 0x2200; reg++)
  assert(nu1669_writeable_reg(NULL, reg) == (reg <= 10 || reg == 0x60 || reg == NU1669_BUSY));
 struct file file = { .private_data = &rx }; loff_t position = 0;
 assert(nu1669_query_tx_id_write(&file, "0", 1, &position) == -EINVAL);
 assert(nu1669_query_tx_id_write(&file, "01", 2, &position) == -EINVAL);
 assert(nu1669_query_tx_id_write(&file, "1 ", 2, &position) == -EINVAL);
 assert(nu1669_query_tx_id_write(&file, "1\n\n", 3, &position) == -EINVAL);
 assert(!rx.query_used && !writes);
 mutex_lock(&rx.lock);
 assert(nu1669_query_tx_id(&rx) == -EBUSY && !rx.query_used && !writes);
 mutex_unlock(&rx.lock);
 assert(nu1669_query_tx_id_write(&file, "1\n", 2, &position) == 2);
 assert(rx.result_valid && !rx.query_quarantined && queries == 1 && acks == 1 && writes == 8);
 assert(flags == (BIT(7) | BIT(12)) && rx.query_reply[0] == 0x5f && rx.query_reply[1] == 5);
 show(true);
 int before = writes; assert(nu1669_query_tx_id(&rx) == -EBUSY && before == writes);
 gpio_value = 0; show(false);
 gpio_value = 1; show(false); assert(rx.query_rearm);
 assert(!nu1669_query_tx_id(&rx) && rx.physical_verified);
 reset(); flags |= BIT(0) | BIT(11); /* Preserve old faults and packet timeout; never ACK them. */
 assert(!nu1669_query_tx_id(&rx) && (flags & (BIT(0) | BIT(11) | BIT(7))) == (BIT(0) | BIT(11) | BIT(7)));
 reset(); flags |= NU1669_RX_DATA; memset(bc, 0xcc, sizeof(bc)); bc[0] = 0x5f; bc[1] = 5;
 assert(!nu1669_query_tx_id(&rx) && acks == 2 && queries == 1 && rx.query_reply[2] == 0xa1);
 puts("GET05: exact trigger, one attach attempt, no queued writes, byte-exact five-byte GET/mask10 ACK, stale drain and old fault preservation passed");
}
static void faults(void)
{
 for (int m = NO_REPLY; m <= ACK_NEW_FAULT; m++) {
  reset(); mode = m;
  if (mode == BUSY) busy = 1;
  if (mode == ALL_ONES) flags = UINT32_MAX;
  if (mode == UNRELATED) { /* One valid unrelated frame is consumed, not a success. */
   assert(nu1669_query_tx_id(&rx) == -ETIMEDOUT);
  } else assert(nu1669_query_tx_id(&rx));
  assert(rx.query_quarantined && !rx.result_valid);
  show(false);
  int before = writes;
  assert(nu1669_query_tx_id(&rx) == -EBUSY && writes == before);
  atomic_inc(&rx.generation); rx.suspended = true; rx.suspended = false;
  assert(nu1669_query_tx_id(&rx) == -EBUSY && writes == before);
  if (m == BUSY || m == ALL_ONES) assert(!writes);
  if (m == STALE_LATE) assert(!queries && writes == 3);
  if (m == UNRELATED_REPEAT) assert(queries == 1 && acks == 2);
 }
 reset(); mode = NO_REPLY;
 assert(nu1669_query_tx_id(&rx) == -ETIMEDOUT);
 flags |= NU1669_RX_DATA; bc[0] = 0x5f; bc[1] = 5; /* Late matching reply cannot complete another attempt. */
 int before = writes; assert(nu1669_query_tx_id(&rx) == -EBUSY && writes == before);
 mutex_lock(&rx.lock); nu1669_observe_presence(&rx, 0); nu1669_observe_presence(&rx, 1); mutex_unlock(&rx.lock);
 mode = GOOD; response_pending = false; response_reads = 0;
 assert(!nu1669_query_tx_id(&rx) && rx.physical_verified && !rx.query_quarantined);
 puts("GET05 faults: busy/no writes, timeout/late reply, no logical rearm, torn/malformed reply, unrelated packet, new faults, ACK-sticky loss/stuck and physical recovery passed");
}
static void boundaries(void)
{
 for (int stale = 0; stale <= 1; stale++) {
  reset(); if (stale) { flags |= NU1669_RX_DATA; bc[0] = 0x5f; bc[1] = 5; }
  assert(!nu1669_query_tx_id(&rx)); int total = steps;
  for (int e = EDGE; e <= IO_FAIL; e++) {
   for (int at = 1; at <= total; at++) {
    reset(); if (stale) { flags |= NU1669_RX_DATA; bc[0] = 0x5f; bc[1] = 5; }
    event = e; inject_at = at;
    assert(nu1669_query_tx_id(&rx));
    assert(!rx.result_valid && rx.query_quarantined && !rx.lock.locked);
    int before = writes;
    assert(nu1669_query_tx_id(&rx) == -EBUSY && writes == before);
   }
  }
  printf("GET05 boundaries: edge/detach/suspend/stop/I2C ambiguity at all %d GPIO/I2C/poll boundaries (%s stale event) passed\n", total, stale ? "with" : "without");
 }
}

static void *query_thread(void *unused) { query_ret = nu1669_query_tx_id(&rx); return NULL; }
static void *snapshot_thread(void *unused)
{
 struct nu1669_snapshot sample;
 assert(!nu1669_get_snapshot(&psy, &sample) && sample.chip_id == 0x1669);
 __atomic_store_n(&snapshot_done, 1, __ATOMIC_SEQ_CST);
 return NULL;
}
static void concurrency(void)
{
 reset(); block_query = true;
 pthread_t query, snapshot;
 assert(!pthread_create(&query, NULL, query_thread, NULL));
 pthread_mutex_lock(&barrier);
 while (!query_blocked) pthread_cond_wait(&condition, &barrier);
 pthread_mutex_unlock(&barrier);
 assert(!pthread_create(&snapshot, NULL, snapshot_thread, NULL));
 usleep(10000); assert(!__atomic_load_n(&snapshot_done, __ATOMIC_SEQ_CST));
 assert(nu1669_query_tx_id(&rx) == -EBUSY);
 pthread_mutex_lock(&barrier); unblock = true; pthread_cond_broadcast(&condition); pthread_mutex_unlock(&barrier);
 assert(!pthread_join(query, NULL) && !pthread_join(snapshot, NULL));
 assert(!query_ret && snapshot_done && queries == 1 && rx.query_sequence == 1);
 puts("GET05 concurrency: coherent snapshot waits behind whole query, trigger trylock queues no second attempt, error-checking mutexes detect nesting passed");
}
static void *remove_thread(void *unused) { nu1669_debugfs_remove(&rx); return NULL; }
static void cleanup_order(void)
{
 reset(); block_query = true;
 struct dentry directory; rx.debugfs = &directory;
 pthread_t query, remove;
 assert(!pthread_create(&query, NULL, query_thread, NULL));
 pthread_mutex_lock(&barrier);
 while (!query_blocked) pthread_cond_wait(&condition, &barrier);
 pthread_mutex_unlock(&barrier);
 assert(!pthread_create(&remove, NULL, remove_thread, NULL));
 for (int i = 0; !READ_ONCE(rx.stopped) && i < 100; i++) usleep(1000);
 assert(READ_ONCE(rx.stopped) && !debugfs_removed);
 pthread_mutex_lock(&barrier); unblock = true; pthread_cond_broadcast(&condition); pthread_mutex_unlock(&barrier);
 assert(!pthread_join(query, NULL) && !pthread_join(remove, NULL));
 assert(query_ret == -ECANCELED && writes == 1 && !queries && !acks);
 assert(debugfs_removed == 1 && !rx.debugfs && irq_disabled == 1 && work_cancelled == 1);
 nu1669_stop(&rx); assert(irq_disabled == 1 && work_cancelled == 1);
 puts("GET05 removal: stop/generation cancels reserved transaction before debugfs drain; no length/payload/commit or teardown writes; repeated stop idempotent passed");
}

static void fod_shadow_tests(void)
{
 u8 mag, output[NU1669_FOD_SHADOW_SIZE];
 reset(); info[0x18] = 0xff; fod[0] = 0xff; fod[1] = 255; fod[2] = 0x88;
 rx.query_quarantined = rx.query_used = true; rx.query_sequence = 9;
 assert(!nu1669_fod_shadow_get(&rx, &mag, output));
 assert(mag == 0xff && !memcmp(output, fod, sizeof(output)) && fod_reads == 2 && !writes);
 assert(rx.query_quarantined && rx.query_used && rx.query_sequence == 9 && !rx.query_rearm);
 int total = steps;
 struct seq_file s = { .private = &rx };
 assert(!nu1669_fod_shadow_show(&s, NULL) && !writes);
 for (int kind = 0; kind < 8; kind++) {
  reset(); memset(output, 0xcc, sizeof(output)); mag = 0xcc;
  if (kind == 0) gpio_value = 0;
  if (kind == 1) info[0] = 0;
  if (kind == 2) identity_changed = true;
  if (kind == 3) mag_changed = true;
  if (kind == 4) fod_torn = true;
  if (kind == 5) io_error = true;
  if (kind == 6) rx.suspended = true;
  if (kind == 7) rx.stopped = true;
  int ret = nu1669_fod_shadow_get(&rx, &mag, output);
  assert(ret == (kind <= 1 ? -ENODEV : kind == 2 ? -ESTALE : kind == 5 ? -EIO : kind >= 6 ? -EBUSY : -EAGAIN));
  assert(mag == 0xcc && !writes && !rx.lock.locked);
  for (size_t i = 0; i < sizeof(output); i++) assert(output[i] == 0xcc);
 }
 for (int e = EDGE; e <= IO_FAIL; e++) {
  for (int at = 1; at <= total; at++) {
   reset(); rx.query_quarantined = rx.query_used = true; rx.query_sequence = 9;
   memset(output, 0xcc, sizeof(output)); mag = 0xcc;
   event = e; inject_at = at;
   assert(nu1669_fod_shadow_get(&rx, &mag, output));
   assert(mag == 0xcc && !writes && !rx.lock.locked);
   assert(rx.query_quarantined && rx.query_used && rx.query_sequence == 9 && !rx.query_rearm);
   for (size_t i = 0; i < sizeof(output); i++) assert(output[i] == 0xcc);
  }
 }
 printf("FOD shadow: exact43-byte read-only block, full raw values, stable identity/mag, torn/errors/no partial output, unchanged quarantine and all %d GPIO/I2C lifecycle boundaries passed\n", total);
}

static void bpp_reset(void)
{
 reset(); bpp_test = true; rx.bpp_profile = true;
 for (int i = 0; i < 40; i++) rx.bpp_parameters[i] = i + 1;
}
static void bpp_tests(void)
{
 u8 board[40] = { 0x48, 0x32, 0x48, 0x2d, 0x48, 0x32, 0x48, 0x30, 0x48, 0x37, 0x48, 0x53 };
 memset(board + 12, 0xff, 28); assert(nu1669_bpp_profile_valid(board));
 board[0] ^= 1; assert(!nu1669_bpp_profile_valid(board));
 memset(board, 0xff, 40); assert(!nu1669_bpp_profile_valid(board));

 bpp_reset(); assert(!nu1669_prepare_bpp(&psy, 0));
 assert(bpp_step == 7 && writes == 28 && !rx.bpp_quarantined && !atomic_read(&nu1669_bpp_uncertain));
 int total = steps;
 struct nu1669_snapshot snapshot;
 assert(!nu1669_get_snapshot(&psy, &snapshot) && snapshot.bpp_valid);
 fod[5] ^= 1;
 assert(nu1669_get_snapshot(&psy, &snapshot) == -EUCLEAN && rx.bpp_quarantined);
 assert(atomic_read(&nu1669_bpp_uncertain));
 for (int e = EDGE; e <= IO_FAIL; e++) {
  for (int at = 1; at <= total; at++) {
   bpp_reset(); event = e; inject_at = at;
   assert(nu1669_prepare_bpp(&psy, 0));
   if (writes) {
    assert(rx.bpp_quarantined && atomic_read(&nu1669_bpp_uncertain));
    rx.suspended = rx.stopped = false; gpio_value = 1; io_error = false;
    int before = writes; assert(nu1669_prepare_bpp(&psy, atomic_read(&rx.generation)) == -EUCLEAN && writes == before);
   }
   assert(!rx.lock.locked);
  }
 }
 bpp_reset(); busy = 1; assert(nu1669_prepare_bpp(&psy, 0) == -EBUSY && !writes);
 bpp_reset(); fod_torn = true; assert(nu1669_prepare_bpp(&psy, 0) == -EPROTO && rx.bpp_quarantined);
 bpp_reset(); info[4]++; assert(nu1669_prepare_bpp(&psy, 0) == -EOPNOTSUPP && !writes);
 bpp_reset(); info[0x20] = 1; assert(nu1669_prepare_bpp(&psy, 0) == -EIO && !writes);
 bpp_reset(); assert(nu1669_query_tx_id(&rx) == -EOPNOTSUPP && !writes);
 printf("typed BPP: seven exact whitelisted messages, 40 board bytes, normalized shadow, busy-before-write, full verification and %d lifecycle/I2C boundaries with persistent quarantine passed\n", total);
}

int main(int argc, char **argv) { if (argc == 2 && !strcmp(argv[1], "fod")) { fod_shadow_tests(); return 0; } bpp_tests(); fod_shadow_tests(); basic(); faults(); boundaries(); concurrency(); cleanup_order(); return 0; }
