// SPDX-License-Identifier: GPL-2.0
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define BIT(x) (1U << (x))
#define FALSE false
/* Distinct mocked existing register endpoints; only the imported ACK address
 * is a new physical-address contract in this regression.
 */
#define BGF_IRQ_STAT 1U
#define BGF_IRQ_STAT2 2U
#define CONN_INFRA_RGU_BGFSYS_CPU_SW_RST 3U
#define BTMTK_DBG(...) do { } while (0)
#define BTMTK_INFO(...) (intents++)
#define BTMTK_ERR(fmt, ...) do { \
	errors++; \
	snprintf(error_text, sizeof(error_text), fmt, __VA_ARGS__); \
} while (0)
#define REG_WRITEL(addr, value) write_existing(addr, value)
#define SET_BIT(addr, value) release_cpu(addr, value)

static unsigned int ack_word, reset_word;
static unsigned int stage, writes, releases, maps, unmaps, intents, errors;
static bool fail_mapping;
static char error_text[120];

static void write_existing(unsigned int addr, unsigned int value)
{
	assert(value == 1);
	assert(addr == (stage == 0 ? BGF_IRQ_STAT : BGF_IRQ_STAT2));
	assert(stage < 2);
	stage++;
}

static unsigned int *ioremap(unsigned int addr, unsigned int size)
{
	assert(addr == 0x1803e014 && size == 0x10);
	maps++;
	return fail_mapping ? NULL : &ack_word;
}

static void iounmap(unsigned int *address)
{
	assert(address == &ack_word);
	unmaps++;
	writes++;
}

static void release_cpu(unsigned int addr, unsigned int value)
{
	assert(addr == CONN_INFRA_RGU_BGFSYS_CPU_SW_RST && value == 1);
	assert(stage == 2);
	if (!fail_mapping) {
		/* Exact old startup block fails here before CPU release. */
		assert(writes == 1 && ack_word == 0xff);
		assert(maps == 1 && unmaps == 1);
	} else {
		/* Existing void helper logs mapping failure and cannot write. */
		assert(errors == 1 && writes == 0);
	}
	reset_word |= value;
	releases++;
}

#include "production.h"

static void setup(unsigned int prior, bool fail)
{
	ack_word = prior;
	reset_word = 0xa5a50000;
	stage = 0;
	writes = 0;
	releases = 0;
	maps = 0;
	unmaps = 0;
	intents = 0;
	errors = 0;
	fail_mapping = fail;
	error_text[0] = 0;
}

int main(void)
{
	(void)write_existing;
	(void)release_cpu;
	/* This also exercises the unchanged helper directly in the ATF build. */
	setup(0x12345678, false);
	bt_write_cr(0x1803e014, 0xff, false);
	assert(ack_word == 0xff && writes == 1);
	bt_write_cr(0x1803e014, 0x100, true);
	assert(ack_word == 0x1ff && writes == 2);

	for (unsigned int epoch = 0; epoch < 4; epoch++) {
		setup(epoch & 1 ? 0xffffffff : 0xabcdef00, false);
		production_start();
#if CFG_BT_ATF_SUPPORT == 0
		assert(stage == 2 && writes == 1 && releases == 1);
		assert(ack_word == 0xff && reset_word == 0xa5a50001);
		assert(intents == 1 && errors == 0);
#else
		assert(stage == 0 && maps == 0 && releases == 0);
		assert(writes == 0 && intents == 0);
#endif
	}

	setup(0x12345678, true);
	production_start();
#if CFG_BT_ATF_SUPPORT == 0
	assert(ack_word == 0x12345678 && maps == 1 && unmaps == 0);
	assert(errors == 1 && strstr(error_text, "remapping 0x1803e014 fail"));
	assert(releases == 1); /* Preserve existing void-helper semantics. */
#else
	assert(maps == 0 && errors == 0 && releases == 0);
#endif
	puts("startup sequence/epochs/arguments/mapping failure/ATF guard PASS");
	return 0;
}
