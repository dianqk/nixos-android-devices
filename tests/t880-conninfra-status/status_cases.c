/* SPDX-License-Identifier: GPL-2.0 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint64_t u64;
struct platform_device;
@PRODUCTION_TYPES@
struct arm_smccc_res { unsigned long a0, a1, a2, a3; };
#define MTK_SIP_KERNEL_CONNSYS_CONTROL 0xc2000534UL
@PRODUCTION_SMC@
@PRODUCTION_CONSTANTS@
#define pr_debug(...) do { if (0) printf(__VA_ARGS__); } while (0)
#define pr_info(...) do { if (0) printf(__VA_ARGS__); } while (0)
#define pr_err(...) do { if (0) printf(__VA_ARGS__); } while (0)
enum { CLOCK = 100, PMIC, CLOCKBUF, PINMUX, POWER, POLL, EMI, DDIE,
       PATCH, CAL, PLL, UPDATE, RAISE, PMICLP, WAKE, SLEEP, ROLLBACK, PMIC_CB };
struct call { int kind; unsigned int a, b; int result; };
static struct call calls[64];
static unsigned int nr, current_mask, next_mask;
static bool check_masks;
static int result[128], platform_config = 0x23;
static struct consys_hw_env conn_hw_env;
static struct consys_hw_ops_struct ops;
static const struct consys_hw_ops_struct *consys_hw_ops = &ops;

static int record(int kind, unsigned int a, unsigned int b, int ret)
{
	assert(nr < sizeof(calls) / sizeof(calls[0]));
	calls[nr++] = (struct call){kind, a, b, ret};
	return ret;
}
static void arm_smccc_smc(unsigned long fn, unsigned long op,
	unsigned long a2, unsigned long a3, unsigned long a4, unsigned long a5,
	unsigned long a6, unsigned long a7, struct arm_smccc_res *res)
{
	assert(fn == MTK_SIP_KERNEL_CONNSYS_CONTROL);
	assert(!a4 && !a5 && !a6 && !a7);
	assert(op == SMC_CONNSYS_INIT_ATF_DATA_OPID ||
	       op == SMC_CONNSYS_SPI_MASTER_CFG_OPID ||
	       op == SMC_CONNSYS_A_DIE_CFG_OPID ||
	       op == SMC_CONNSYS_LOW_POWER_SETTING_OPID);
	if (check_masks && op != SMC_CONNSYS_INIT_ATF_DATA_OPID) {
		assert(a2 == current_mask && "SMC current radio mask lost");
		assert(a3 == next_mask && "SMC next radio mask lost");
	}
	if (op == SMC_CONNSYS_INIT_ATF_DATA_OPID) {
		assert(a2 == (unsigned int)platform_config);
		assert(a3 == conn_hw_env.clock_type);
	}
	record(op, a2, a3, result[op]);
	*res = (struct arm_smccc_res){(unsigned long)result[op], 0x66378a01, 0, 0};
}
static int consys_hw_get_platform_config(void) { return platform_config; }
@PRODUCTION_ATF@
#if HAVE_STATUS
#define SPI(c, n) connsys_spi_master_cfg_mt6897_atf(c, n)
#define ADIE(c, n) connsys_a_die_cfg_mt6897_atf(c, n)
#else
#define SPI(c, n) connsys_spi_master_cfg_mt6897_atf(n)
#define ADIE(c, n) connsys_a_die_cfg_mt6897_atf()
#endif

/* These only model the untouched framework operations, not firmware state. */
static int clock_type(void) { return record(CLOCK, 0, 0, result[CLOCK]); }
static int init_data(void) { return record(0, 0, 0, result[0]); }
static int clockbuf(unsigned int on) { return record(CLOCKBUF, on, 0, 0); }
static void pinmux(unsigned int on) { record(PINMUX, on, 0, 0); }
static int power(unsigned int on) { return record(POWER, on, 0, result[POWER]); }
static int chipid(void) { return record(POLL, 0, 0, result[POLL]); }
static int ddie(void) { return record(DDIE, 0, 0, 0); }
static void sw_patch(void) { record(PATCH, 0, 0, 0); }
static int calibrate(void) { return record(CAL, 0, 0, 0); }
static int pll(void) { return record(PLL, 0, 0, 0); }
static int update(bool on, int radio) { return record(UPDATE, radio, on, 0); }
static int legacy_spi(unsigned int next) { return record(12, ~0U, next, result[12]); }
static int legacy_adie(void) { return record(13, ~0U, ~0U, result[13]); }
static int pmic_mng_common_power_ctrl(unsigned int on)
{
	return record(PMIC, on, 0, result[PMIC]);
}
static int pmic_mng_common_power_low_power_mode(unsigned int on)
{
	return record(PMICLP, on, 0, 0);
}
static void pmic_mng_event_cb(unsigned int a, unsigned int b)
{
	record(PMIC_CB, a, b, 0);
}
static int consys_hw_raise_voltage(unsigned int radio, bool raise, bool onoff)
{
	assert(onoff);
	return record(RAISE, radio, raise, 0);
}
static int _consys_hw_raise_voltage(unsigned int radio, bool raise, bool onoff)
{
	return consys_hw_raise_voltage(radio, raise, onoff);
}
static int _consys_hw_conninfra_wakeup(void) { return record(WAKE, 0, 0, result[WAKE]); }
static void _consys_hw_conninfra_sleep(void) { record(SLEEP, 0, 0, 0); }
static void emi_mng_set_remapping_reg(void) { record(EMI, 0, 0, 0); }
@PRODUCTION_ROLLBACK_ENUM@
static int _consys_hw_pwr_on_rollback(enum conninfra_pwr_on_rollback_type type)
{
	return record(ROLLBACK, type, 0, 0);
}
@PRODUCTION_FRAMEWORK@
static const struct consys_hw_ops_struct atf_bindings = {
@PRODUCTION_BINDINGS@
};
static void setup(bool status, unsigned int curr, unsigned int next)
{
	memset(result, 0, sizeof(result));
	memset(&ops, 0, sizeof(ops));
	nr = 0;
	current_mask = curr;
	next_mask = next;
	check_masks = true;
	ops.consys_plt_co_clock_type = clock_type;
	ops.consys_plt_init_atf_data = init_data;
	ops.consys_plt_clock_buffer_ctrl = clockbuf;
	ops.consys_plt_set_if_pinmux = pinmux;
	ops.consys_plt_conninfra_on_power_ctrl = power;
	ops.consys_plt_polling_consys_chipid = chipid;
	ops.consys_plt_d_die_cfg = ddie;
	ops.consys_plt_afe_sw_patch = sw_patch;
	ops.consys_plt_afe_wbg_cal = calibrate;
	ops.consys_plt_subsys_pll_initial = pll;
	ops.consys_plt_subsys_status_update = update;
	ops.consys_plt_spi_master_cfg = legacy_spi;
	ops.consys_plt_a_die_cfg = legacy_adie;
	ops.consys_plt_low_power_setting = connsys_low_power_setting_mt6897_atf;
	if (status) {
#if HAVE_STATUS
		ops.consys_plt_spi_master_cfg_status = atf_bindings.consys_plt_spi_master_cfg_status;
		ops.consys_plt_a_die_cfg_status = atf_bindings.consys_plt_a_die_cfg_status;
#else
		ops.consys_plt_spi_master_cfg = atf_bindings.consys_plt_spi_master_cfg;
		ops.consys_plt_a_die_cfg = atf_bindings.consys_plt_a_die_cfg;
#endif
	}
}
static void expect_order(const int *expected, size_t count)
{
	assert(nr == count);
	for (unsigned int i = 0; i < nr; i++)
		assert(calls[i].kind == expected[i]);
}
#define EXPECT_ORDER(...) do { const int e[] = {__VA_ARGS__}; expect_order(e, sizeof(e) / sizeof(e[0])); } while (0)
static void print_trace(const char *phase, unsigned int mask, unsigned int radio)
{
	printf("%s %x %u:", phase, mask, radio);
	for (unsigned int i = 0; i < nr; i++)
		printf(" %d/%x/%x/%d", calls[i].kind, calls[i].a, calls[i].b, calls[i].result);
	putchar('\n');
}
static void masks(bool status, bool trace)
{
	for (unsigned int mask = 0; mask < (1U << CONNDRV_TYPE_CONNINFRA); mask++) {
		for (unsigned int radio = 0; radio <= CONNDRV_TYPE_MAWD; radio++) {
			setup(status, mask, mask | (1U << radio));
			assert(consys_hw_pwr_on(mask, radio) == 0);
			if (!mask) {
				EXPECT_ORDER(CLOCK, 0, PMIC, CLOCKBUF, PINMUX, POWER,
					POLL, EMI, DDIE, 12, 13, PATCH, CAL, PLL,
					UPDATE, RAISE, 17, PMICLP);
			} else if (status) {
				EXPECT_ORDER(WAKE, 13, UPDATE, 12, RAISE, 17, SLEEP);
			} else {
				EXPECT_ORDER(WAKE, UPDATE, 12, RAISE, 17, SLEEP);
			}
			if (trace)
				print_trace("on", mask, radio);
			setup(status, mask, mask & ~(1U << radio));
			assert(consys_hw_pwr_off(mask, radio) == 0);
			if (!next_mask)
				EXPECT_ORDER(PMIC_CB, RAISE, POWER, PINMUX, CLOCKBUF, PMIC);
			else
				EXPECT_ORDER(WAKE, UPDATE, RAISE, 12, 17, SLEEP);
			if (trace)
				print_trace("off", mask, radio);
		}
	}
}
static void wrappers(int init_result)
{
	setup(true, 0, 0);
	conn_hw_env.clock_type = 2;
	result[0] = init_result;
	assert(consys_init_atf_data_mt6897_atf() == init_result);
	assert(nr == 1);
	assert(consys_init_atf_data_mt6897_atf() == 0);
	assert(nr == 1); /* Existing initialized-on-error cache policy is unchanged. */
	for (unsigned int mi = 0; mi <= (1U << CONNDRV_TYPE_MAX); mi++) {
		unsigned int mask = mi == (1U << CONNDRV_TYPE_MAX) ? 0x80000000U : mi;

		for (unsigned int ni = 0; ni <= (1U << CONNDRV_TYPE_MAX); ni++) {
			unsigned int next = ni == (1U << CONNDRV_TYPE_MAX) ? 0x80000000U : ni;
			const int errors[] = {0, -5, -110, 7};
			for (unsigned int i = 0; i < sizeof(errors) / sizeof(errors[0]); i++) {
				setup(true, mask, next);
				result[12] = result[13] = result[17] = errors[i];
				assert(SPI(mask, next) == errors[i]);
				assert(ADIE(mask, next) == errors[i]);
				assert(conn_hw_env.adie_hw_version == 0x66378a01);
				assert(connsys_low_power_setting_mt6897_atf(mask, next) == errors[i]);
				EXPECT_ORDER(12, 13, 17);
			}
		}
	}
}
static void errors_and_fallback(void)
{
#if HAVE_STATUS
	setup(true, 8, 9);
	result[12] = -11;
	result[13] = 7;
	assert(consys_hw_spi_master_cfg(8, 9) == -11);
	assert(consys_hw_a_die_cfg(8, 9) == 7);
	EXPECT_ORDER(12, 13); /* Status callbacks win over populated legacy slots. */
	setup(false, 8, 9);
	result[12] = -11;
	result[13] = 7;
	assert(consys_hw_spi_master_cfg(8, 9) == -11);
	assert(consys_hw_a_die_cfg(8, 9) == 7);
	assert(calls[0].a == ~0U && calls[0].b == 9);
	assert(calls[1].a == ~0U && calls[1].b == ~0U);
	ops.consys_plt_spi_master_cfg = NULL;
	ops.consys_plt_a_die_cfg = NULL;
	nr = 0;
	assert(consys_hw_spi_master_cfg(8, 9) == 0);
	assert(consys_hw_a_die_cfg(8, 9) == 0);
	assert(!nr);

	for (unsigned int status = 0; status < 2; status++) {
		setup(status, 0, 1);
		result[13] = -5;
		assert(consys_hw_pwr_on(0, 0) == CONNINFRA_POWER_ON_A_DIE_FAIL);
		assert(calls[nr - 1].kind == ROLLBACK &&
		       calls[nr - 1].a == CONNINFRA_PWR_ON_A_DIE_FAIL);
		const int failures[] = {PMIC, POWER, POLL};
		const unsigned int rollbacks[] = {CONNINFRA_PWR_ON_PMIC_ON_FAIL,
			CONNINFRA_PWR_ON_CONNINFRA_HW_POWER_FAIL,
			CONNINFRA_PWR_ON_POLLING_CHIP_ID_FAIL};

		for (unsigned int i = 0; i < 3; i++) {
			setup(status, 0, 1);
			result[failures[i]] = -5;
			assert(consys_hw_pwr_on(0, 0) == CONNINFRA_POWER_ON_D_DIE_FAIL);
			assert(calls[nr - 1].kind == ROLLBACK &&
			       calls[nr - 1].a == rollbacks[i]);
		}
	}
	setup(true, 8, 9);
	result[13] = -5;
	assert(consys_hw_pwr_on(8, 0) == 0);
	EXPECT_ORDER(WAKE, 13, UPDATE, 12, RAISE, 17, SLEEP);
	setup(true, 8, 9);
	result[WAKE] = -5;
	assert(consys_hw_pwr_on(8, 0) == CONNINFRA_POWER_ON_CONFIG_FAIL);
	EXPECT_ORDER(WAKE);
	setup(true, 9, 8);
	result[WAKE] = -5;
	assert(consys_hw_pwr_off(9, 0) == 0);
	EXPECT_ORDER(WAKE, UPDATE, RAISE, 12, 17);
	setup(true, 0, 1);
	result[12] = result[17] = -5;
	assert(consys_hw_pwr_on(0, 0) == 0); /* Existing ignored SPI/LP returns. */
	assert(calls[nr - 1].kind == PMICLP);
	setup(true, 0, 1);
	result[CLOCK] = -5;
	assert(consys_hw_pwr_on(0, 0) == CONNINFRA_POWER_ON_D_DIE_FAIL);
	EXPECT_ORDER(CLOCK);
#endif
}
int main(int argc, char **argv)
{
	_Static_assert(SMC_CONNSYS_SPI_MASTER_CFG_OPID == 0x0c, "SPI opcode");
	_Static_assert(SMC_CONNSYS_A_DIE_CFG_OPID == 0x0d, "A-die opcode");
	_Static_assert(SMC_CONNSYS_LOW_POWER_SETTING_OPID == 0x11, "low-power opcode");
	if (argc > 1 && !strcmp(argv[1], "legacy")) {
		masks(false, true);
		return 0;
	}
	wrappers(argc > 2 ? atoi(argv[2]) : 0);
	if (argc > 1 && !strcmp(argv[1], "wrappers"))
		return 0;
#if HAVE_STATUS
	masks(true, false);
#endif
	masks(false, false);
	errors_and_fallback();
	puts("ATF masks, raw errors, dispatch, ordering and legacy fallback PASS");
	return 0;
}
