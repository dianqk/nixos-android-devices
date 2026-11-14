#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t u8;
enum phy_mode { PHY_MODE_INVALID, PHY_MODE_USB_HOST, PHY_MODE_USB_DEVICE, PHY_MODE_USB_OTG };
#define NUM_SUPPLIES 2
#define PTN3222_USB2_TX_CONTROL1 7
#define PTN3222_USB2_TX_CONTROL2 8
struct i2c_client { int dev; };
struct ptn3222 {
    struct i2c_client *client;
    void *regmap, *reset_gpio, *supplies;
    u8 tx_control[2], tx_control_host[2];
    bool have_tx_control, have_tx_control_host, initialized;
    enum phy_mode mode;
};
struct phy { struct ptn3222 *data; };
static struct ptn3222 *phy_get_drvdata(struct phy *p) { return p->data; }
static int regs[256], fail_write, writes, fail_read, reads, power, reset, fail_power;
static int regmap_read(void *map, int reg, unsigned int *value) {
    if (++reads == fail_read) return -EIO;
    *value = regs[reg]; return 0;
}
static int regmap_write(void *map, int reg, int value) {
    regs[reg] = value; /* An I2C failure can happen after the target took the write. */
    return ++writes == fail_write ? -EIO : 0;
}
static int regulator_bulk_enable(int n, void *supplies) {
    if (fail_power) return -EIO;
    ++power; return 0;
}
static int regulator_bulk_disable(int n, void *supplies) { --power; return 0; }
static void gpiod_set_value_cansleep(void *gpio, int value) { reset = value; }
static void usleep_range(int a, int b) { }
#define dev_err(dev, ...) ((void)0)
#include "callbacks.h"

static struct ptn3222 device(void) {
    power = 0; reset = 1; fail_power = 0; reads = writes = 0;
    fail_read = fail_write = 0;
    regs[7] = 0; regs[8] = 0x62;
    return (struct ptn3222){ .mode = PHY_MODE_USB_DEVICE,
        .have_tx_control = true, .have_tx_control_host = true,
        .tx_control = {0, 0x62}, .tx_control_host = {0x22, 0x63} };
}
int main(void) {
    struct ptn3222 d = device(); struct phy p = { &d };
    assert(!ptn3222_init(&p));
    assert(power == 1 && reset == 0 && d.initialized);
    assert(!ptn3222_set_mode(&p, PHY_MODE_USB_HOST, 0));
    assert(d.mode == PHY_MODE_USB_HOST && regs[7] == 0x22 && regs[8] == 0x63);
    assert(!ptn3222_set_mode(&p, PHY_MODE_USB_DEVICE, 0));
    assert(regs[7] == 0 && regs[8] == 0x62);
    assert(ptn3222_set_mode(&p, PHY_MODE_INVALID, 0) == -EINVAL);
    assert(!ptn3222_exit(&p) && power == 0 && reset == 1);
    assert(!ptn3222_set_mode(&p, PHY_MODE_USB_HOST, 0));
    assert(!ptn3222_init(&p)); /* Resume/reinitialization replays the latest mode. */
    assert(regs[7] == 0x22 && regs[8] == 0x63);
    assert(!ptn3222_exit(&p));
    for (int failure = 1; failure <= 2; ++failure) {
        d = device(); assert(!ptn3222_init(&p));
        writes = 0; fail_write = failure;
        assert(ptn3222_set_mode(&p, PHY_MODE_USB_HOST, 0) == -EIO);
        assert(d.mode == PHY_MODE_USB_DEVICE);
        assert(regs[7] == 0 && regs[8] == 0x62);
        fail_write = 0; assert(!ptn3222_exit(&p));
    }
    d = device(); fail_read = 1;
    assert(ptn3222_init(&p) == -EIO);
    assert(!d.initialized && reset == 1 && power == 0);
    d = device(); fail_power = 1;
    assert(ptn3222_init(&p) == -EIO);
    assert(!d.initialized && reset == 1 && power == 0);
    puts("PTN3222 roles, I2C rollback, power rollback and resume: passed");
}
