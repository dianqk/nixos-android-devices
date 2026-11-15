/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef BTMTK_BTCVSD_H
#define BTMTK_BTCVSD_H
struct platform_device;
struct hci_dev;
struct sk_buff;
int btmtk_btcvsd_send(struct sk_buff *skb);
int btmtk_btcvsd_recv(struct hci_dev *hdev, struct sk_buff *skb);
int btmtk_btcvsd_init(struct platform_device *pdev, struct hci_dev *hdev);
void btmtk_btcvsd_open(void);
void btmtk_btcvsd_shutdown(void);
void btmtk_btcvsd_remove(void);
#endif
