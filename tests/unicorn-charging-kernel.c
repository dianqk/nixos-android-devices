/* Host transport fixture. Structures and driver functions are inserted verbatim. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <sys/types.h>
#include <stdarg.h>
typedef uint32_t u32;
typedef int32_t s32;
typedef uint32_t __le32;
typedef uint16_t __le16;
typedef uint8_t u8;
typedef unsigned int spinlock_t;
struct pmic_glink_hdr { __le32 owner, type, opcode; };
struct completion { unsigned int done; };
struct work_struct { int unused; };
struct mutex { bool locked; };
struct power_supply { int unused; };
#define PMIC_GLINK_OWNER_BATTMGR 32778
#define PMIC_GLINK_REQ_RESP 1
#define PMIC_GLINK_NOTIFY 2
#define SERVREG_SERVICE_STATE_UP 1
#define HZ 100
#define cpu_to_le32(x) ((uint32_t)(x))
#define le32_to_cpu(x) ((uint32_t)(x))
#define ARRAY_SIZE(x) (sizeof(x) / sizeof(*(x)))
#define DIV_ROUND_CLOSEST(x,d) (((x) + (d) / 2) / (d))
#define dev_warn(...) ((void)0)
#define dev_err(...) ((void)0)
#define fallthrough __attribute__((__fallthrough__))
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x, v) ((x) = (v))
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (flags) = 0; } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
static void mutex_lock(struct mutex *m) { assert(!m->locked); m->locked = true; }
static void mutex_unlock(struct mutex *m) { assert(m->locked); m->locked = false; }
static void complete(struct completion *ack) { ack->done++; }
static void reinit_completion(struct completion *ack) { ack->done = 0; }
static unsigned long wait_for_completion_timeout(struct completion *ack, unsigned long timeout)
{ (void)timeout; return ack->done != 0; }
static void power_supply_changed(struct power_supply *p) { (void)p; }
static void schedule_work(struct work_struct *w) { (void)w; }
static void strscpy(char *dest, const char *src, size_t size)
{ size_t n = strnlen(src, size - 1); memcpy(dest, src, n); dest[n] = 0; }
static u32 get_unaligned_be32(const u8 *p)
{ return (u32)p[0] << 24 | (u32)p[1] << 16 | (u32)p[2] << 8 | p[3]; }
/* DEFINITIONS */
static void qcom_battmgr_callback(const void *, size_t, void *);
static void qcom_battmgr_pdr_notify(void *, int);
static void qcom_battmgr_sc8280xp_callback(struct qcom_battmgr *b,
        const struct qcom_battmgr_message *m, size_t len) { (void)b; (void)m; (void)len; }
static u8 sent[128];
static size_t sent_len;
static struct qcom_battmgr *active;
static unsigned int sends;
enum reply_mode { SCALAR, BLOB, FW_ERROR, SHORT_BLOB, WRONG_PROPERTY, WRONG_OPCODE,
                  NO_REPLY, SEND_ERROR, UNRELATED_THEN_BLOB, SCALAR_FOR_BLOB, BAD_SLAVE, PDR_DOWN };
static enum reply_mode mode;
static int pmic_glink_send(struct pmic_glink_client *client, const void *data, size_t len)
{
    (void)client;
    assert(len <= sizeof(sent));
    memcpy(sent, data, len); sent_len = len; sends++;
    if (!active->unicorn.pending) {
        const struct qcom_battmgr_property_request *req = data;
        struct qcom_battmgr_message resp = { .hdr = req->hdr,
                                            .intval = { req->property, 0, 0 } };
        qcom_battmgr_callback(&resp, sizeof(resp.hdr) + sizeof(resp.intval), active);
        return 0;
    }
    if (mode == SEND_ERROR)
        return -EIO;
    if (mode == NO_REPLY)
        return 0;
    if (mode == PDR_DOWN) { qcom_battmgr_pdr_notify(active, 0); return 0; }
    struct unicorn_xm_state *xm = &active->unicorn;
    struct unicorn_xm_digest response = {
        .hdr = { 32778, 1, xm->opcode }, .property = xm->property,
    };
    for (unsigned int i = 0; i < sizeof(response.digest); i++) response.digest[i] = i;
    size_t reply_len = xm->kind == UNICORN_XM_DIGEST ? sizeof(response) : sizeof(struct unicorn_xm_vdm);
    if (mode == UNRELATED_THEN_BLOB) {
        struct qcom_battmgr_message unrelated = { .hdr = { 32778, 1, BATTMGR_USB_PROPERTY_GET },
                                                  .intval = { USB_ONLINE, 1, 0 } };
        qcom_battmgr_callback(&unrelated, sizeof(unrelated.hdr) + sizeof(unrelated.intval), active);
        assert(active->ack.done == 0 && active->unicorn.pending);
    }
    if (mode == SCALAR || mode == FW_ERROR || mode == SCALAR_FOR_BLOB) {
        struct qcom_battmgr_message scalar = { .hdr = response.hdr,
            .intval = { xm->property, 123, mode == FW_ERROR ? 7 : 0 } };
        qcom_battmgr_callback(&scalar, sizeof(scalar.hdr) + sizeof(scalar.intval), active);
        return 0;
    }
    if (mode == SHORT_BLOB) reply_len--;
    if (mode == WRONG_PROPERTY) response.property++;
    if (mode == WRONG_OPCODE) response.hdr.opcode ^= 1;
    if (mode == BAD_SLAVE) response.slave = 1;
    qcom_battmgr_callback(&response, reply_len, active);
    return 0;
}
struct device { struct qcom_battmgr *data; };
struct device_attribute { int unused; };
struct unicorn_xm_attribute { struct device_attribute attr; u32 property; bool hex; };
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
static struct qcom_battmgr *dev_get_drvdata(struct device *dev) { return dev->data; }
static int kstrtobool(const char *buf, bool *out)
{
    if (!strcmp(buf, "1") || !strcmp(buf, "1\n")) { *out = true; return 0; }
    if (!strcmp(buf, "0") || !strcmp(buf, "0\n")) { *out = false; return 0; }
    return -EINVAL;
}
static int hex2bin(u8 *out, const char *hex, size_t count)
{
    for (size_t i = 0; i < count * 2; i++) {
        const char *digit = strchr("0123456789abcdef", hex[i]);
        if (!digit || !hex[i]) return -EINVAL;
        unsigned int v = digit - "0123456789abcdef";
        if (!(i & 1)) out[i / 2] = v << 4; else out[i / 2] |= v;
    }
    return 0;
}
static void bin2hex(char *out, const u8 *data, size_t count)
{ for (size_t i = 0; i < count; i++) snprintf(out + i * 2, 3, "%02x", data[i]); }
static u32 get_unaligned_le32(const u8 *p)
{ return p[0] | (u32)p[1] << 8 | (u32)p[2] << 16 | (u32)p[3] << 24; }
static int sysfs_emit(char *out, const char *format, ...)
{ va_list args; va_start(args, format); int n = vsnprintf(out, 4096, format, args); va_end(args); return n; }
/* FUNCTIONS */

static void scalar_reply(struct qcom_battmgr *b, u32 opcode, u32 property, u32 value)
{
    struct qcom_battmgr_message m = { .hdr = { 32778, 1, opcode }, .intval = { property, value, 0 } };
    qcom_battmgr_callback(&m, sizeof(m.hdr) + sizeof(m.intval), b);
}

int main(void)
{
    _Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "fixture uses little endian wire layout");
    _Static_assert(sizeof(struct unicorn_xm_vdm) == 32, "VDM wire size");
    _Static_assert(sizeof(struct unicorn_xm_digest) == 52, "digest wire size");
    struct qcom_battmgr b = { .variant = QCOM_BATTMGR_SM8350, .unicorn_abi = true, .service_up = true };
    active = &b;
    /* USB_ADAP_TYPE is Unicorn's USB_TYPE source. Other boards retain property 6. */
    assert(!qcom_battmgr_request_property(&b, BATTMGR_USB_PROPERTY_GET, USB_TYPE, 0));
    assert(((struct qcom_battmgr_property_request *)sent)->property == 7);
    scalar_reply(&b, BATTMGR_USB_PROPERTY_GET, 7, 8);
    assert(b.usb.usb_type == POWER_SUPPLY_USB_TYPE_PD_PPS);
    b.unicorn_abi = false;
    assert(!qcom_battmgr_request_property(&b, BATTMGR_USB_PROPERTY_GET, USB_TYPE, 0));
    assert(((struct qcom_battmgr_property_request *)sent)->property == 6);
    scalar_reply(&b, BATTMGR_USB_PROPERTY_GET, 6, 8);
    assert(b.usb.usb_type == 8);
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -EOPNOTSUPP);
    b.unicorn_abi = true;
    b.service_up = false;
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -EAGAIN);
    b.service_up = true;
    mode = SCALAR;
    u32 value = 0;
    assert(!unicorn_xm_scalar(&b, UNICORN_XM_GET, UNICORN_XM_ADAPTER_SVID, 0, &value));
    assert(value == 123 && sent_len == 24);
    assert(((struct qcom_battmgr_property_request *)sent)->battery == 0);
    assert(((struct qcom_battmgr_property_request *)sent)->property == 0x12);
    assert(UNICORN_XM_REAL_TYPE == 6 && UNICORN_XM_PD_VERIFED == 0x13);
    assert(UNICORN_XM_FASTCHG_MODE == 0x26 && UNICORN_XM_APDO_MAX == 0x2b);
    assert(UNICORN_XM_FB_BLANK_STATE == 0x57 && UNICORN_XM_SPORT_MODE == 0x5a);
    u8 input[32], output[32];
    for (unsigned int i = 0; i < 32; i++) input[i] = 31 - i;
    mode = BLOB;
    assert(!unicorn_xm_vdm(&b, UNICORN_XM_SET, UNICORN_XM_VDM_SEED, input, NULL));
    assert(sent_len == 32 && sent[16] == input[3] && sent[19] == input[0]);
    assert(!unicorn_xm_digest(&b, UNICORN_XM_SET, input, NULL));
    assert(sent_len == 52 && !memcmp(sent + 16, input, 32));
    assert(!sent[48] && !sent[49] && !sent[50] && !sent[51]);
    memset(output, 255, sizeof(output));
    assert(!unicorn_xm_digest(&b, UNICORN_XM_GET, NULL, output));
    for (unsigned int i = 0; i < 32; i++) assert(output[i] == i);
    mode = UNRELATED_THEN_BLOB;
    assert(!unicorn_xm_vdm(&b, UNICORN_XM_GET, UNICORN_XM_VDM_AUTH, NULL, output));
    for (unsigned int i = 0; i < 16; i++) assert(output[i] == i);
    /* Scalar SET acknowledgements are valid for both blob formats. */
    mode = SCALAR;
    assert(!unicorn_xm_digest(&b, UNICORN_XM_SET, input, NULL));
    assert(!unicorn_xm_vdm(&b, UNICORN_XM_SET, UNICORN_XM_VDM_SEED, input, NULL));
    mode = SCALAR_FOR_BLOB;
    assert(unicorn_xm_digest(&b, UNICORN_XM_GET, NULL, output) == -EPROTO);
    mode = FW_ERROR;
    value = 456;
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, &value) == -EREMOTEIO && value == 456);
    assert(unicorn_xm_digest(&b, UNICORN_XM_GET, NULL, output) == -EREMOTEIO);
    assert(unicorn_xm_vdm(&b, UNICORN_XM_GET, UNICORN_XM_VDM_AUTH, NULL, output) == -EREMOTEIO);
    mode = SHORT_BLOB;
    assert(unicorn_xm_digest(&b, UNICORN_XM_GET, NULL, output) == -EPROTO);
    mode = BAD_SLAVE;
    assert(unicorn_xm_digest(&b, UNICORN_XM_GET, NULL, output) == -EPROTO);
    mode = SEND_ERROR;
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -EIO);
    assert(!b.unicorn.timed_out);
    const enum reply_mode timeout_modes[] = { WRONG_PROPERTY, WRONG_OPCODE, NO_REPLY };
    for (unsigned int i = 0; i < ARRAY_SIZE(timeout_modes); i++) {
        mode = timeout_modes[i];
        assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -ETIMEDOUT);
        unsigned int before = sends;
        assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -EAGAIN && sends == before);
        scalar_reply(&b, UNICORN_XM_GET, 4, 1);
        assert(b.unicorn.timed_out);
        struct qcom_battmgr_message short_reply = { .hdr = { 32778, 1, UNICORN_XM_GET },
                                                   .intval = { 3, 0, 0 } };
        qcom_battmgr_callback(&short_reply, 16, &b);
        assert(b.unicorn.timed_out);
        scalar_reply(&b, UNICORN_XM_GET, 3, 1);
        assert(!b.unicorn.timed_out && !b.ack.done);
    }
    mode = NO_REPLY;
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -ETIMEDOUT);
    qcom_battmgr_pdr_notify(&b, 0);
    assert(!b.service_up && !b.unicorn.timed_out && b.unicorn.generation == 1);
    qcom_battmgr_pdr_notify(&b, SERVREG_SERVICE_STATE_UP);
    assert(b.service_up && b.unicorn.generation == 2);
    mode = SCALAR;
    assert(!unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL));
    mode = PDR_DOWN;
    assert(unicorn_xm_scalar(&b, UNICORN_XM_GET, 3, 0, NULL) == -ENOTCONN);
    assert(!b.unicorn.pending && !b.unicorn.timed_out && !b.service_up);
    qcom_battmgr_pdr_notify(&b, SERVREG_SERVICE_STATE_UP);
    mode = SCALAR;
    struct device device = { .data = &b };
    struct unicorn_xm_attribute sport = { .property = UNICORN_XM_SPORT_MODE };
    unsigned int before = sends;
    assert(unicorn_xm_store(&device, &sport.attr, "1", 1) == -EOPNOTSUPP && sends == before);
    assert(unicorn_xm_store(&device, &sport.attr, "0", 1) == 1);
    const char *valid[] = { "1,null", "2,null\n", "3,null", "4,000102030405060708090a0b0c0d0e0f",
                            "5,000102030405060708090a0b0c0d0e0f", "6,01000000", "7,00000000",
                            "8,000102030405060708090a0b0c0d0e0f" };
    for (unsigned int i = 0; i < ARRAY_SIZE(valid); i++) {
        assert(request_vdm_cmd_store(&device, NULL, valid[i], strlen(valid[i])) == (ssize_t)strlen(valid[i]));
        if (i == 3) assert(sent[16] == 3 && sent[19] == 0);
    }
    const char *invalid[] = { "", "0,null", "9,null", "1,garbage", "4,00", "6,00000001",
                              "4,zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "1,null extra",
                              "4,000102030405060708090a0b0c0d0e0f00" };
    for (unsigned int i = 0; i < ARRAY_SIZE(invalid); i++) {
        before = sends;
        assert(request_vdm_cmd_store(&device, NULL, invalid[i], strlen(invalid[i])) == -EINVAL);
        assert(sends == before);
    }
    char digest_hex[66];
    memset(digest_hex, 'a', 64); digest_hex[64] = '\n'; digest_hex[65] = 0;
    assert(verify_digest_store(&device, NULL, digest_hex, 65) == 65);
    assert(sent_len == 52 && sent[16] == 0xaa && sent[47] == 0xaa);
    assert(verify_digest_store(&device, NULL, digest_hex, 63) == -EINVAL);
    char rendered[4096];
    mode = BLOB;
    assert(verify_digest_show(&device, NULL, rendered) == 65);
    assert(!strcmp(rendered, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n"));
    /* Truncated header/property frames must not access bytes outside the frame. */
    for (size_t len = 0; len < 16; len++) {
        u8 *frame = calloc(1, len ? len : 1);
        if (len >= 12) ((struct pmic_glink_hdr *)frame)->opcode = UNICORN_XM_GET;
        qcom_battmgr_callback(frame, len, &b);
        free(frame);
    }
    puts("Unicorn battmgr wire formats, errors, timeout quarantine, PDR and USB regression: PASS");
    return 0;
}
