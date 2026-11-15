// SPDX-License-Identifier: GPL-2.0
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define BIT(n) (1U << (n))
#define BGF_LPCTL 1
#define BGF_IRQ_STAT 2
#define BGF_IRQ_STAT2 3
#define BGF_HOST_CLR_FW_OWN_B BIT(1)
#define BGF_OWNER_STATE_SYNC_B BIT(2)
#define BGF_IRQ_FW_OWN_CLR_B BIT(0)
#define BGF_HOST_SET_FW_OWN_B BIT(0)
#define BGF_IRQ_FW_OWN_SET_B BIT(0)
#define SMC_BT_FW_OWN_CLR_FIRST 1
#define SMC_BT_FW_OWN_CLR_SECOND 2
#define SMC_BT_FW_OWN_SET_FIRST 1
#define SMC_BT_FW_OWN_SET_SECOND 2
#define BTMTK_DBG(...) do { } while (0)
#define BTMTK_WARN(...) do { } while (0)
#define BTMTK_ERR(...) do { } while (0)
#define bt_dbg_tp_evt(...) do { } while (0)
static int g_bt_trace_pt;
static bool snapshots, firmware;
static unsigned int poll_count, success_at;
static char ordinary[32768], timeline[32768];

static void append(char *buffer, const char *fmt, ...)
{
	va_list args;
	size_t length = strlen(buffer);
	int n;

	va_start(args, fmt);
	n = vsnprintf(buffer + length, 32768 - length, fmt, args);
	va_end(args);
	assert(n >= 0 && length + n < 32768);
}

static void event(const char *fmt, ...)
{
	char text[128];
	va_list args;

	va_start(args, fmt);
	vsnprintf(text, sizeof(text), fmt, args);
	va_end(args);
	append(ordinary, "%s", text);
	append(timeline, "%s", text);
}

static uint32_t legacy_read(unsigned int address)
{
	uint32_t value;

	assert(address == (firmware ? BGF_IRQ_STAT2 : BGF_LPCTL));
	poll_count++;
	value = firmware ? 1 : poll_count < success_at ? 4 : 0;
	event("R:%u:%u;", address, value);
	return value;
}

static void legacy_write(unsigned int address, unsigned int value)
{
	event("W:%u:%u;", address, value);
}

#define REG_READL(address) legacy_read(address)
#define REG_WRITEL(address, value) legacy_write(address, value)
#define btmtk_cif_fw_own_clr_smc(op) legacy_write(20, op)
#define btmtk_cif_fw_own_set_smc(op) legacy_write(21, op)
#define bt_dump_cif_own_cr() event("DUMP;")
#define bt_dump_cpupcr(a, b) event("PC:%u:%u;", a, b)
#define usleep_range(a, b) event("SLEEP:%u:%u;", a, b)

static void btmtk_cif_own_snapshot(const char *phase, int retry,
				 bool valid, uint32_t polled, bool full)
{
	if (!snapshots)
		return;
	if (!strcmp(phase, "drv-first-fail")) {
		/* Value is from poll at retry4065, before current4064 poll. */
		assert(retry == 4096 - 32 && poll_count == 32 && valid && polled == 4 && full);
	}
	if (!strcmp(phase, "drv-first-poll"))
		assert(poll_count == 1 && valid && !full);
	if (!strcmp(phase, "fw-ack"))
		assert(poll_count == 1 && valid && polled == 1 && full);
	if (!strcmp(phase, "drv-pre") || !strcmp(phase, "fw-first-write"))
		assert(!valid && !full);
	if (!strcmp(phase, "fw-pre"))
		assert(!valid && full);
	append(timeline, "SNAP:%s;", phase);
}

#include "callers.h"

static void setup(bool fw, unsigned int success)
{
	firmware = fw;
	poll_count = 0;
	success_at = success;
	ordinary[0] = timeline[0] = 0;
}

int main(int argc, char **argv)
{
	(void)argv;
	(void)btmtk_cif_own_snapshot;
	snapshots = argc == 1;
	setup(true, 1);
	assert(btmtk_cif_fw_own_set() == 0);
	if (snapshots) {
		assert(strstr(timeline, "SNAP:fw-pre;W:1:1;SNAP:fw-first-write;R:3:1;SNAP:fw-ack;W:3:1;"));
	} else {
		puts(ordinary);
	}
	setup(false, 1);
	assert(btmtk_cif_fw_own_clr() == 0);
	if (snapshots) {
		assert(strstr(timeline, "SNAP:drv-pre;W:1:2;R:1:0;SNAP:drv-first-poll;SNAP:drv-ack;W:2:1;"));
	} else {
		puts(ordinary);
	}
	setup(false, 33);
	assert(btmtk_cif_fw_own_clr() == 0);
	if (snapshots) {
		assert(strstr(timeline, "SNAP:drv-first-fail;DUMP;W:1:2;DUMP;R:1:0;SNAP:drv-ack;W:2:1;"));
		puts("actual caller hook/polled value/first request/W1C/dump order PASS");
	} else {
		puts(ordinary);
	}
	return 0;
}
