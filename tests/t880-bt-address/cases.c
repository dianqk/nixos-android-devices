/* SPDX-License-Identifier: GPL-2.0 */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct { unsigned char b[6]; } bdaddr_t;
static const bdaddr_t any, original = {{0x1f, 0x97, 0x17, 0x19, 0x0a, 0x10}};
static const bdaddr_t firmware_default = {{1, 0x61, 0x67, 0x46, 0, 0}};
#define BDADDR_ANY (&any)
#define bacmp(a,b) memcmp(a,b,sizeof(bdaddr_t))
#define HCI_QUIRK_NON_PERSISTENT_SETUP 1
#define HCI_INIT_TIMEOUT 10
#define BTMTK_INFO(...) ((void)0)
#define BTMTK_ERR(...) ((void)0)
#define bt_dev_err(...) ((void)0)
#define IS_ERR(p) ((intptr_t)(p) < 0)
#define PTR_ERR(p) ((int)(intptr_t)(p))
struct btmtk_dev { int chip_id; };
struct hci_dev { bool persistent_quirk; struct btmtk_dev bdev; int (*setup)(struct hci_dev *); };
struct sk_buff { int unused; };
static struct sk_buff response;
static bdaddr_t controller;
static char *t880_bdaddr;
static int hook_error, command_error, hook_calls, writes, frees;
static struct btmtk_dev *hci_get_drvdata(struct hci_dev *hdev) { return &hdev->bdev; }
static bool is_mt66xx(int chip) { return chip == 0x6637; }
static void hci_set_quirk(struct hci_dev *hdev, int quirk) {
    assert(quirk == HCI_QUIRK_NON_PERSISTENT_SETUP); hdev->persistent_quirk = true;
}
static int hook_open(struct hci_dev *hdev) { (void)hdev; hook_calls++; return hook_error; }
static struct { struct { int (*open)(struct hci_dev *); } hif_hook; } main_info = {{hook_open}};
static struct sk_buff *__hci_cmd_sync(struct hci_dev *hdev, int opcode, int len,
                                    const bdaddr_t *addr, int timeout) {
    (void)hdev; assert(opcode == 0xfc1a && len == 6 && timeout == HCI_INIT_TIMEOUT);
    writes++;
    if (command_error) return (struct sk_buff *)(intptr_t)command_error;
    controller = *addr; return &response;
}
static void kfree_skb(struct sk_buff *skb) { assert(skb == &response); frees++; }
#include "production.h"
/* Linux hci_dev_setup_sync skips setup after first open unless this quirk is
 * set. Physical open reloads firmware; successful init then reads BD_ADDR. */
static int physical_open(struct hci_dev *hdev, bool first, bdaddr_t *core_addr) {
    controller = firmware_default;
    int ret = (first || hdev->persistent_quirk) ? hdev->setup(hdev) : 0;
    if (!ret) *core_addr = controller;
    return ret;
}
int main(void) {
    struct hci_dev hdev = {.bdev = {0x6637}};
    bdaddr_t core = any;
    register_setup(&hdev);
    t880_bdaddr = "10:0A:19:17:97:1F";
    assert(physical_open(&hdev, true, &core) == 0 && !bacmp(&core, &original));
    assert(hook_calls == 1 && writes == 1 && frees == 1);
    for (int i = 0; i < 3; i++) {
        assert(physical_open(&hdev, false, &core) == 0);
        assert(!bacmp(&core, &original));
    }
    assert(hook_calls == 4 && writes == 4 && frees == 4);
    /* Negative control reproduces the old wrong identity after reopen. */
    hdev.persistent_quirk = false;
    assert(physical_open(&hdev, false, &core) == 0);
    assert(!bacmp(&core, &firmware_default) && bacmp(&core, &original));
    hdev.persistent_quirk = true;
    int before = writes;
    hook_error = -5; core = original;
    assert(physical_open(&hdev, false, &core) == -5);
    assert(writes == before && !bacmp(&core, &original));
    hook_error = 0; command_error = -110;
    assert(physical_open(&hdev, false, &core) == -110);
    assert(writes == before + 1 && frees == 4 && !bacmp(&core, &original));
    command_error = 0;
    assert(physical_open(&hdev, false, &core) == 0 && !bacmp(&core, &original));
    before = writes;
    t880_bdaddr = NULL;
    assert(physical_open(&hdev, false, &core) == 0 && writes == before);
    t880_bdaddr = "00:00:00:00:00:00";
    assert(physical_open(&hdev, false, &core) == 0 && writes == before);
    t880_bdaddr = "invalid";
    assert(physical_open(&hdev, false, &core) == 0 && writes == before);
    puts("first open, repeated reopen, old-driver negative control, hook/command errors and recovery passed");
}
