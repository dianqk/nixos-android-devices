// SPDX-License-Identifier: GPL-2.0
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef uintptr_t phys_addr_t;
#define __iomem
#define SZ_4K 4096
#define BIT(x) (1U << (x))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define DTS_REORDERED 0
#define scnprintf snprintf
struct fake_debug { int dummy; };
#define DEFINE_DYNAMIC_DEBUG_METADATA(name, fmt) struct fake_debug name = { 0 }
#define DYNAMIC_DEBUG_BRANCH(name) ((void)(name), enabled)
typedef struct { int value; } atomic_t;
#define ATOMIC_INIT(n) { (n) }
static bool enabled, fail_map, fail_src_map, wide_clock;
static unsigned int maps, unmaps, reads, atomics, clocks, logs;
static u32 rx, tx;
static uintptr_t read_addresses[2048];
static atomic_t *last_count;
static char log_text[32][1024];

static int atomic_fetch_add_unless(atomic_t *count, int increment, int unless)
{
	int old = count->value;

	atomics++;
	last_count = count;
	if (old != unless)
		count->value += increment;
	return old;
}

static u64 ktime_get_boottime_ns(void)
{
	return wide_clock ? UINT64_MAX - clocks++ : 1000000 + clocks++;
}

static void *ioremap(phys_addr_t address, unsigned int size)
{
	assert((address == 0x1002c000 || address == 0x1c00d000) && size == 4096);
	maps++;
	return ((address == 0x1002c000 && fail_map) ||
		(address == 0x1c00d000 && fail_src_map)) ? NULL : (void *)address;
}

static void iounmap(void *address)
{
	assert((uintptr_t)address == 0x1002c000 || (uintptr_t)address == 0x1c00d000);
	unmaps++;
}

static u32 readl(const void *address)
{
	uintptr_t p = (uintptr_t)address;

	assert(reads < ARRAY_SIZE(read_addresses));
	read_addresses[reads++] = p;
	if (p == 0x1002c1cc)
		return rx;
	if (p == 0x1002c00c)
		return tx;
	if (p == 0x1c00d004)
		return 0x104014e5;
	if (p == 0x1c00d03c)
		return 0x1c029c92;
	if (p == 0x1c00d130)
		return 0xc0208963;
	return (u32)p ^ 0x1234;
}

static void __dynamic_pr_debug(struct fake_debug *debug, const char *fmt, ...)
{
	va_list args;
	int size;

	(void)debug;
	assert(logs < 32);
	va_start(args, fmt);
	size = vsnprintf(log_text[logs++], sizeof(log_text[0]), fmt, args);
	va_end(args);
	assert(size > 0 && size < (int)sizeof(log_text[0]));
}

#include "production.h"

static void mappings(void)
{
	bt_reg.reg_base_addr[CONN_INFRA_RGU_BASE_INDEX] =
		(struct consys_reg_base_addr){ 0x18000000, 0x18000000, 4096 };
	bt_reg.reg_base_addr[CONN_INFRA_CFG_BASE_INDEX] =
		(struct consys_reg_base_addr){ 0x18001000, 0x18001000, 4096 };
	bt_reg.reg_base_addr[SPM_BASE_INDEX] =
		(struct consys_reg_base_addr){ 0x18060000, 0x18060000, 4096 };
}

int main(int argc, char **argv)
{
	/* Keep unsupported-arm builds strict without hiding production warnings. */
	(void)atomic_fetch_add_unless;
	(void)ktime_get_boottime_ns;
	(void)ioremap;
	(void)iounmap;
	(void)readl;
	(void)__dynamic_pr_debug;
	assert(argc == 2);
	mappings();
	if (!strcmp(argv[1], "off") || !strcmp(argv[1], "stub")) {
		enabled = !strcmp(argv[1], "stub");
		for (unsigned int i = 0; i < 64; i++)
			btmtk_cif_own_snapshot("off", 4096, false, 0, true);
		assert(maps == 0 && reads == 0 && atomics == 0 && logs == 0 && clocks == 0);
		return 0;
	}
	enabled = true;
	if (!strcmp(argv[1], "allowed-guards")) {
		rx = 0xfffffffe;
		tx = 0x01002088;
	}
	if (!strcmp(argv[1], "cap") || !strcmp(argv[1], "cap-full")) {
		bool full_cap = !strcmp(argv[1], "cap-full");
		for (unsigned int i = 0; i < 64; i++)
			btmtk_cif_own_snapshot("cap", 4096, true, 4, full_cap);
		assert(logs == 32 && maps == 32 * (full_cap ? 2 : 1) &&
		       unmaps == maps && reads == 32 * (full_cap ? 35 : 6));
		assert(last_count->value == 32 && clocks == 64);
		for (unsigned int i = 0; i < 32; i++) {
			char id[32];

			snprintf(id, sizeof(id), "id=%u ", i + 1);
			assert(strstr(log_text[i], id));
		}
		return 0;
	}
	if (!strcmp(argv[1], "rx-protected"))
		rx = 1;
	if (!strcmp(argv[1], "tx-protected"))
		tx = BIT(25);
	if (!strcmp(argv[1], "map-fail"))
		fail_map = true;
	if (!strcmp(argv[1], "src-map-fail"))
		fail_src_map = true;
	if (!strcmp(argv[1], "mapping"))
		bt_reg.reg_base_addr[CONN_INFRA_CFG_BASE_INDEX].phy_addr = 0;
	if (!strcmp(argv[1], "host-short"))
		bt_reg.reg_base_addr[SPM_BASE_INDEX].size = 0x3c;
	if (!strcmp(argv[1], "rgu-short"))
		bt_reg.reg_base_addr[CONN_INFRA_RGU_BASE_INDEX].size = 0x424;
	if (!strcmp(argv[1], "ao-independent")) {
		bt_reg.reg_base_addr[CONN_INFRA_CFG_BASE_INDEX].vir_addr = 0;
		bt_reg.reg_base_addr[CONN_INFRA_RGU_BASE_INDEX].phy_addr = 0;
	}
	bool full = strcmp(argv[1], "ao") && strcmp(argv[1], "ao-independent");

	wide_clock = !strcmp(argv[1], "width");
	btmtk_cif_own_snapshot(wide_clock ? "01234567890123456789012345678901" : "test",
			      wide_clock ? INT32_MIN : 4064, true, 4, full);
	assert(atomics == 1 && logs == 1 && clocks == 2);
	assert(strstr(log_text[0], "poll_valid=1 poll=00000004"));
	if (fail_map) {
		assert(maps == 1 && reads == 0 && unmaps == 0);
		assert(strstr(log_text[0], "skipped=guard-map-failed guards_valid=0"));
	} else if ((rx & 1) || (tx & BIT(25)) || !strcmp(argv[1], "mapping") ||
		   !strcmp(argv[1], "host-short") || !strcmp(argv[1], "rgu-short")) {
		assert(maps == 1 && reads == 2 && unmaps == 1);
		assert(strstr(log_text[0], (rx & 1) || (tx & BIT(25)) ? "skipped=ap2conn-protected" :
			      "skipped=bank-mapping-invalid"));
		assert(!strstr(log_text[0], "18060030="));
	} else {
		static const uintptr_t expected[] = {
			0x1002c1cc, 0x1002c00c,
			0x18060030, 0x18060034, 0x18060038, 0x1806003c,
			0x180601a8, 0x18060a10, 0x18000414, 0x18000424,
			0x1800102c, 0x18001108, 0x18001200, 0x18001208,
			0x18001210, 0x18001220, 0x18001300, 0x18001304,
			0x18001308, 0x1800130c, 0x18001340, 0x18001344,
			0x18001348, 0x18001360, 0x18001364, 0x18001450,
			0x18001454, 0x18001460, 0x18001464, 0x18001600,
			0x18001640, 0x18001644,
			0x1c00d004, 0x1c00d03c, 0x1c00d130,
		};

		assert(maps == (full ? 2U : 1U));
		assert(reads == (full ? ARRAY_SIZE(expected) - (fail_src_map ? 3 : 0) : 6));
		assert(unmaps == maps - (fail_src_map ? 1 : 0));
		assert(!memcmp(read_addresses, expected, reads * sizeof(expected[0])));
		assert(strstr(log_text[0], full ? "full=1" : "full=0"));
		for (unsigned int i = 2; i < reads; i++) {
			char field[40];

			u32 value = (u32)expected[i] ^ 0x1234;

			if (expected[i] == 0x1c00d004)
				value = 0x104014e5;
			if (expected[i] == 0x1c00d03c)
				value = 0x1c029c92;
			if (expected[i] == 0x1c00d130)
				value = 0xc0208963;
			snprintf(field, sizeof(field), "%08lx=%08x",
				 (unsigned long)expected[i], value);
			assert(strstr(log_text[0], field));
		}
		if (!full) {
			assert(!strstr(log_text[0], "src_rc="));
		} else if (fail_src_map) {
			assert(strstr(log_text[0], "src_rc=unavailable(map-failed)"));
			assert(!strstr(log_text[0], "1c00d004="));
			assert(!strstr(log_text[0], "1c00d03c="));
			assert(!strstr(log_text[0], "1c00d130="));
		} else {
			assert(strstr(log_text[0], "src_rc=available"));
		}
		if (wide_clock)
			printf("bounded rendered full record: %zu bytes\n", strlen(log_text[0]));
	}
	puts("helper default-off/whitelist/order/guard/map/bounds/cap PASS");
	return 0;
}
