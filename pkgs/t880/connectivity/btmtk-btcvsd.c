// SPDX-License-Identifier: GPL-2.0-only
/* MT6897 shared-SRAM SCO transport. See btcvsd-layout.h for vendor provenance.
 * Optional SCO transports for the observed controller flow-control-disabled mode.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/mfd/syscon.h>
#include <linux/regmap.h>
#include <linux/mutex.h>
#include <linux/unaligned.h>
#include <linux/ktime.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include <linux/debugfs.h>
#include <linux/seq_file.h>
#include <linux/workqueue.h>
#include <net/bluetooth/bluetooth.h>
#include <net/bluetooth/hci_core.h>
#include "btmtk-btcvsd.h"
#include "btcvsd-layout.h"
#include "btcvsd-cvsd.h"

static bool sco_diagnostic;
module_param(sco_diagnostic, bool, 0444);
MODULE_PARM_DESC(
	sco_diagnostic,
	"read-only MT6897 SCO SRAM diagnostics (12 seconds per connection)");

static bool sco_msbc;
module_param(sco_msbc, bool, 0444);
MODULE_PARM_DESC(
	sco_msbc,
	"enable MT6897 mSBC SRAM transport (SCO flow control disabled only)");

static bool sco_rx_diagnostic;
module_param(sco_rx_diagnostic, bool, 0444);
MODULE_PARM_DESC(sco_rx_diagnostic,
		 "retain four damaged RX payload snapshots (debugfs root-only)");

static bool sco_cvsd_observe;
module_param(sco_cvsd_observe, bool, 0444);
MODULE_PARM_DESC(sco_cvsd_observe,
		 "receive-only CVSD SRAM capture; consumes SCO without transmitting audio");

static bool sco_cvsd;
module_param(sco_cvsd, bool, 0444);
MODULE_PARM_DESC(sco_cvsd,
		 "enable MT6897 CVSD SRAM conversion (SCO flow control disabled only)");

#define BTCVSD_CVSD_RX_BATCHES 8
struct btcvsd_cvsd_batch {
	u64 ns;
	unsigned int bytes, generation;
	unsigned char data[180], valid[180];
};

#define BTCVSD_OBSERVATIONS 2048
struct btcvsd_observation {
	u64 ns;
	unsigned int generation, ctl, address, bytes;
	unsigned char data[180];
};

#define BTCVSD_SNAPSHOTS 4
struct btcvsd_snapshot {
	u64 raised_ns, service_ns, copied_ns, reread_ns, interval_ns;
	unsigned int serial, generation, handle, ctl, ctl_after, address,
		address_after;
	unsigned int layout, bytes, frame_index, status, changed, ctl_second,
		address_second;
	unsigned char first[180], second[180], frame[60];
};

static struct {
	struct hci_dev *hdev;
	void __iomem *pkv, *sram, *infra;
	resource_size_t sram_size, sram_phys;
	spinlock_t lock;
	struct delayed_work poll, configure;
	struct workqueue_struct *codec_wq;
	struct work_struct codec_work;
	struct btcvsd_cvsd_fifo pcm_tx, encoded_tx;
	struct btcvsd_cvsd_batch cvsd_rx[BTCVSD_CVSD_RX_BATCHES];
	unsigned int cvsd_rx_head, cvsd_rx_used, codec_generation;
	struct btcvsd_cvsd_tx cvsd_encoder;
	struct btcvsd_cvsd_rx cvsd_decoder;
	struct btcvsd_cvsd_packet cvsd_packet;
	bool cvsd_starved;
	unsigned int pcm_high_water, encoded_high_water, cvsd_rx_high_water;
	unsigned int codec_stale, codec_batches;
	u64 codec_max_ns, codec_max_delay_ns;
	struct mutex control;
	struct regmap *gate_map;
	int irq;
	bool owned, rejected, armed, irq_on, gate_owned;
	unsigned int original_gate;
	struct btcvsd_txq txq;
	struct btcvsd_rxq rxq;
	unsigned char batch[180];
	unsigned int staged;
	unsigned long activate_deadline;
	unsigned int irqs, tx_frames, rx_frames, underflows, overflows;
	unsigned int tx_discard, rx_discard, duplicates, rx_drops,
		rejected_codec;
	struct dentry *debug, *rx_debug;
	struct dentry *observe_debug;
	struct btcvsd_observation *observations;
	unsigned int observation_count;
	u64 irq_raised_ns, previous_irq_ns, max_delay_ns, max_service_ns,
		max_read_delay_ns;
	u64 last_underflow_ns, first_tx_ns, last_resync_ns;
	unsigned int snapshots, mutations;
	struct btcvsd_snapshot snapshot[BTCVSD_SNAPSHOTS];
	bool ready, active, running;
	unsigned int generation, handle, air, samples, pending, invalid;
	unsigned int ctl, rx, tx, gate, flowctl;
	unsigned long deadline;
} sco;

static bool btcvsd_transport_enabled(void)
{
	return sco_msbc || sco_cvsd_observe || sco_cvsd;
}

/* Called under sco.lock. Observation has no PCM conversion or TX writes. */
static bool btcvsd_codec_supported(unsigned int ctl)
{
	return btcvsd_supported(sco.air, sco.flowctl, (ctl >> 25) & 3) ||
	       ((sco_cvsd_observe || sco_cvsd) && btcvsd_cvsd_supported(sco.air,
					sco.flowctl, (ctl >> 25) & 3));
}

/* The syscon MMIO regmap uses its own spinlock. Never perform a raw RMW on
 * the shared infra register. control serializes sleeping IRQ lifecycle work;
 * lock serializes packets/notify/IRQ state, and never nests the hdev lock. */
static void btcvsd_stop_irq(void)
{
	int ret;
	if (!sco.irq_on)
		return;
	ret = regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0x800);
	if (ret)
		dev_warn(&sco.hdev->dev, "BTCVSD gate mask failed: %d\n", ret);
	disable_irq(sco.irq); /* synchronizes the threaded handler */
	sco.irq_on = false;
	if (sco.gate_owned) {
		ret = regmap_update_bits(sco.gate_map, 0xf00, 0x800,
					 sco.original_gate);
		if (ret)
			dev_warn(&sco.hdev->dev,
				 "BTCVSD gate restore failed: %d\n", ret);
		sco.gate_owned = false;
	}
}
static unsigned int btcvsd_read_io(void *io, unsigned int offset,
				   unsigned int width)
{
	return width == 4 ? readl((void __iomem *)io + offset) :
			    readw((void __iomem *)io + offset);
}
static void btcvsd_write_io(void *io, unsigned int offset, unsigned int width,
			    unsigned int value)
{
	if (width == 4)
		writel(value, (void __iomem *)io + offset);
	else
		writew(value, (void __iomem *)io + offset);
}

/* A CVSD discontinuity cannot be repaired by an H2 resynchronization. Stop
 * ownership on queue failure instead of silently removing encoded time. */
static void btcvsd_cvsd_reject_locked(void)
{
	if (sco.armed)
		regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0x800);
	sco.owned = sco.armed = false;
	sco.rejected = true;
	btcvsd_cvsd_fifo_reset(&sco.pcm_tx, sco.generation, 2160);
	btcvsd_cvsd_fifo_reset(&sco.encoded_tx, sco.generation, 1080);
	sco.cvsd_rx_head = sco.cvsd_rx_used = 0;
	mod_delayed_work(system_wq, &sco.configure, 0);
}

static bool btcvsd_cvsd_current(unsigned int generation)
{
	return sco_cvsd && sco.running && sco.active && sco.owned &&
	       !sco.rejected && sco.air == SCO_AIRMODE_CVSD &&
	       sco.generation == generation;
}

/* Only this ordered worker owns codec/filter state. Producers and consumers
 * hold the spinlock for bounded queue copies; all DSP runs outside it. */
static void btcvsd_codec_work(struct work_struct *work)
{
	struct btcvsd_cvsd_batch rx;
	unsigned char pcm[360], encoded[180], decoded[360], status[180];
	unsigned long flags;
	unsigned int iteration, generation, tx_bytes, i;
	bool have_rx, again;
	u64 started;
	for (iteration = 0; iteration < 8; iteration++) {
		spin_lock_irqsave(&sco.lock, flags);
		generation = sco.generation;
		if (!btcvsd_cvsd_current(generation)) {
			spin_unlock_irqrestore(&sco.lock, flags);
			return;
		}
		if (sco.codec_generation != generation) {
			spin_unlock_irqrestore(&sco.lock, flags);
			btcvsd_cvsd_tx_reset(&sco.cvsd_encoder);
			btcvsd_cvsd_rx_reset(&sco.cvsd_decoder);
			btcvsd_cvsd_packet_reset(&sco.cvsd_packet);
			sco.codec_generation = generation;
			continue;
		}
		have_rx = sco.cvsd_rx_used != 0;
		if (have_rx) {
			rx = sco.cvsd_rx[sco.cvsd_rx_head];
			sco.cvsd_rx_head = (sco.cvsd_rx_head + 1) % BTCVSD_CVSD_RX_BATCHES;
			sco.cvsd_rx_used--;
		}
		tx_bytes = min(180u, min(sco.pcm_tx.used / 2,
			sco.encoded_tx.capacity - sco.encoded_tx.used));
		if (tx_bytes)
			btcvsd_cvsd_fifo_pop(&sco.pcm_tx, generation, pcm, tx_bytes * 2);
		spin_unlock_irqrestore(&sco.lock, flags);
		if (!have_rx && !tx_bytes)
			return;
		started = ktime_get_mono_fast_ns();
		if (tx_bytes)
			btcvsd_cvsd_encode(&sco.cvsd_encoder, pcm, tx_bytes * 2,
					  encoded, sizeof(encoded), 1);
		if (have_rx)
			btcvsd_cvsd_decode(&sco.cvsd_decoder, rx.data, rx.bytes,
					  rx.valid, decoded, sizeof(decoded), status, 1);
		spin_lock_irqsave(&sco.lock, flags);
		if (!btcvsd_cvsd_current(generation)) {
			sco.codec_stale++;
			spin_unlock_irqrestore(&sco.lock, flags);
			continue;
		}
		sco.codec_batches++;
		sco.codec_max_ns = max(sco.codec_max_ns,
			ktime_get_mono_fast_ns() - started);
		if (tx_bytes) {
			if (!btcvsd_cvsd_fifo_push(&sco.encoded_tx, generation,
						 encoded, tx_bytes)) {
				sco.overflows++;
				btcvsd_cvsd_reject_locked();
				spin_unlock_irqrestore(&sco.lock, flags);
				return;
			}
			sco.encoded_high_water = max(sco.encoded_high_water,
						    sco.encoded_tx.used);
		}
		if (have_rx)
			sco.codec_max_delay_ns = max(sco.codec_max_delay_ns,
				ktime_get_mono_fast_ns() - rx.ns);
		spin_unlock_irqrestore(&sco.lock, flags);
		if (!have_rx)
			continue;
		for (i = 0; i < rx.bytes; i++) {
			struct sk_buff *skb;
			if (!btcvsd_cvsd_packet_push(&sco.cvsd_packet,
					decoded + i * 2, status[i]))
				continue;
			skb = bt_skb_alloc(51, GFP_KERNEL);
			spin_lock_irqsave(&sco.lock, flags);
			if (!btcvsd_cvsd_current(generation)) {
				sco.codec_stale++;
				spin_unlock_irqrestore(&sco.lock, flags);
				kfree_skb(skb);
				break;
			}
			if (!skb) {
				sco.rx_drops++;
				btcvsd_cvsd_reject_locked();
				spin_unlock_irqrestore(&sco.lock, flags);
				return;
			}
			put_unaligned_le16(sco.handle |
				(btcvsd_cvsd_status(sco.cvsd_packet.status, 24) << 12), skb_put(skb, 2));
			*(u8 *)skb_put(skb, 1) = 48;
			skb_put_data(skb, sco.cvsd_packet.pcm, 48);
			hci_skb_pkt_type(skb) = HCI_SCODATA_PKT;
			sco.rx_frames++;
			hci_recv_frame(sco.hdev, skb);
			spin_unlock_irqrestore(&sco.lock, flags);
		}
	}
	spin_lock_irqsave(&sco.lock, flags);
	again = btcvsd_cvsd_current(sco.generation) &&
		(sco.cvsd_rx_used || (sco.pcm_tx.used >= 2 &&
		 sco.encoded_tx.used < sco.encoded_tx.capacity));
	if (again)
		queue_work(sco.codec_wq, &sco.codec_work);
	spin_unlock_irqrestore(&sco.lock, flags);
}
/* Timestamp dispatch only. Do not access power-dependent registers here. */
static irqreturn_t btcvsd_irq_top(int irq, void *unused)
{
	WRITE_ONCE(sco.irq_raised_ns, ktime_get_mono_fast_ns());
	return IRQ_WAKE_THREAD;
}
static irqreturn_t btcvsd_irq(int irq, void *unused)
{
	unsigned long flags;
	unsigned int ctl, layout, rx, tx, count, status, n;
	unsigned int address, address_after = 0, ctl_after = 0, frame_index = 0;
	unsigned int discarded;
	u64 service_ns = ktime_get_mono_fast_ns(), raised_ns, interval_ns,
	    copied_ns = 0;
	bool captured = false;
	unsigned char data[180], frame[60];
	struct sk_buff *skb;
	bool wrote = false;
	spin_lock_irqsave(&sco.lock, flags);
	discarded = sco.rx_discard;
	if (!sco.armed || !sco.owned || !sco.active || !sco.running) {
		regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0x800);
		goto out;
	}
	ctl = readl(sco.pkv + 0x148);
	if (!(ctl & BIT(31)))
		goto out;
	layout = (ctl >> 18) & 7;
	sco.irqs++;
	raised_ns = READ_ONCE(sco.irq_raised_ns);
	interval_ns = sco.previous_irq_ns ? raised_ns - sco.previous_irq_ns : 0;
	sco.previous_irq_ns = raised_ns;
	sco.max_delay_ns = max(sco.max_delay_ns, service_ns - raised_ns);
	address = readl(sco.pkv + 0x140);
	if (!btcvsd_control(ctl) ||
	    !btcvsd_codec_supported(ctl) ||
	    !btcvsd_address(address, layout, sco.sram_size, &rx) ||
	    !btcvsd_address(readl(sco.pkv + 0x144), layout, sco.sram_size,
			    &tx)) {
		sco.invalid++;
		sco.rejected = true;
		sco.owned = sco.armed = false;
		btcvsd_tx_reset(&sco.txq, sco.generation);
		btcvsd_rx_reset(&sco.rxq, sco.generation);
		sco.staged = 0;
		regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0x800);
		mod_delayed_work(system_wq, &sco.configure, 0);
		goto out;
	}
	count = btcvsd_payload(layout);
	btcvsd_copy(layout, sco.sram + rx, data, sizeof(data), 0,
		    btcvsd_read_io, btcvsd_write_io);
	if (sco_cvsd_observe && sco.air == SCO_AIRMODE_CVSD) {
		if (sco.observation_count < BTCVSD_OBSERVATIONS) {
			struct btcvsd_observation *o =
				&sco.observations[sco.observation_count++];
			o->ns = service_ns;
			o->generation = sco.generation;
			o->ctl = ctl;
			o->address = address;
			o->bytes = count;
			memcpy(o->data, data, count);
		}
		goto acknowledge;
	}
	if (sco_cvsd && sco.air == SCO_AIRMODE_CVSD) {
		struct btcvsd_cvsd_batch *b;
		unsigned int i;
		if (sco.cvsd_rx_used == BTCVSD_CVSD_RX_BATCHES) {
			sco.overflows++;
			btcvsd_cvsd_reject_locked();
			goto acknowledge;
		}
		b = &sco.cvsd_rx[(sco.cvsd_rx_head + sco.cvsd_rx_used) %
				BTCVSD_CVSD_RX_BATCHES];
		b->ns = service_ns;
		b->generation = sco.generation;
		b->bytes = count;
		memcpy(b->data, data, count);
		for (i = 0; i < count; i++)
			b->valid[i] = btcvsd_valid(ctl, layout, i / 30);
		sco.cvsd_rx_used++;
		sco.cvsd_rx_high_water = max(sco.cvsd_rx_high_water, sco.cvsd_rx_used);
		/* The vendor waits for two batches when recovering from starvation. */
		if (sco.encoded_tx.used >= count * (sco.cvsd_starved ? 2 : 1)) {
			btcvsd_cvsd_fifo_pop(&sco.encoded_tx, sco.generation, data, count);
			btcvsd_copy(layout, sco.sram + tx, data, sizeof(data),
				    1, btcvsd_read_io, btcvsd_write_io);
			sco.cvsd_starved = false;
			if (!sco.first_tx_ns)
				sco.first_tx_ns = service_ns;
			sco.tx_frames += count / 60;
			wrote = true;
		} else {
			sco.cvsd_starved = true;
			sco.underflows++;
			sco.last_underflow_ns = service_ns;
		}
		queue_work(sco.codec_wq, &sco.codec_work);
		goto acknowledge;
	}
	if (sco_rx_diagnostic) {
		copied_ns = ktime_get_mono_fast_ns();
		ctl_after = readl(sco.pkv + 0x148);
		address_after = readl(sco.pkv + 0x140);
		if (ctl_after != ctl || address_after != address)
			sco.mutations++;
		sco.max_read_delay_ns =
			max(sco.max_read_delay_ns, copied_ns - raised_ns);
	}
	if (!btcvsd_rx_push(&sco.rxq, sco.generation, data, layout, ctl)) {
		sco.rx_drops++;
		btcvsd_rx_reset(&sco.rxq, sco.generation);
		btcvsd_rx_push(&sco.rxq, sco.generation, data, layout, ctl);
	}
	while (btcvsd_rx_frame(&sco.rxq, sco.generation, frame, &status,
			       &sco.rx_discard)) {
		if (sco_rx_diagnostic && !captured &&
		    (status || !btcvsd_msbc(frame))) {
			struct btcvsd_snapshot *snap =
				&sco.snapshot[sco.snapshots % BTCVSD_SNAPSHOTS];
			memset(snap, 0, sizeof(*snap));
			snap->serial = ++sco.snapshots;
			snap->raised_ns = raised_ns;
			snap->service_ns = service_ns;
			snap->copied_ns = copied_ns;
			snap->interval_ns = interval_ns;
			snap->generation = sco.generation;
			snap->handle = sco.handle;
			snap->ctl = ctl;
			snap->ctl_after = ctl_after;
			snap->address = address;
			snap->address_after = address_after;
			snap->layout = layout;
			snap->bytes = count;
			snap->frame_index = frame_index;
			snap->status = status;
			memcpy(snap->first, data, count);
			memcpy(snap->frame, frame, 60);
			btcvsd_copy(layout, sco.sram + rx, snap->second,
				    sizeof(snap->second), 0, btcvsd_read_io,
				    btcvsd_write_io);
			snap->reread_ns = ktime_get_mono_fast_ns();
			snap->ctl_second = readl(sco.pkv + 0x148);
			snap->address_second = readl(sco.pkv + 0x140);
			snap->changed =
				memcmp(snap->first, snap->second, count) != 0;
			if (snap->changed)
				sco.mutations++;
			captured = true;
		}
		frame_index++;
		skb = bt_skb_alloc(63, GFP_ATOMIC);
		if (!skb) {
			sco.rx_drops++;
			continue;
		}
		put_unaligned_le16(sco.handle | (status << 12),
				   skb_put(skb, 2));
		*(u8 *)skb_put(skb, 1) = 60;
		skb_put_data(skb, frame, 60);
		hci_skb_pkt_type(skb) = HCI_SCODATA_PKT;
		sco.rx_frames++;
		hci_recv_frame(sco.hdev, skb);
	}
	if (sco.rx_discard != discarded)
		sco.last_resync_ns = service_ns;
	/* A short batch survives this IRQ intact, including after resync. */
	if (btcvsd_tx_batch(&sco.txq, sco.generation, sco.batch, &sco.staged,
			    count, &sco.tx_discard)) {
		btcvsd_copy(layout, sco.sram + tx, sco.batch, sizeof(sco.batch),
			    1, btcvsd_read_io, btcvsd_write_io);
		sco.staged -= count;
		memmove(sco.batch, sco.batch + count, sco.staged);
		if (!sco.first_tx_ns)
			sco.first_tx_ns = service_ns;
		sco.tx_frames += count / 60;
		wrote = true;
	} else {
		sco.underflows++;
		sco.last_underflow_ns = service_ns;
	}
acknowledge:
	/* Vendor protocol: clear pending/ready/overflow, preserving underflow.
	 * Set underflow only when no complete batch was written; no SRAM sweep. */
	n = readl(sco.pkv + 0x148);
	writel(n & ~(BIT(21) | BIT(22) | BIT(24) | BIT(31)), sco.pkv + 0x148);
	if (!wrote)
		writel(readl(sco.pkv + 0x148) | BIT(23), sco.pkv + 0x148);
out:
	sco.max_service_ns =
		max(sco.max_service_ns, ktime_get_mono_fast_ns() - service_ns);
	spin_unlock_irqrestore(&sco.lock, flags);
	return IRQ_HANDLED;
}
static void btcvsd_configure(struct work_struct *work)
{
	unsigned long flags;
	unsigned int ctl, layout, off, generation;
	bool retry = false;
	int ret;
	mutex_lock(&sco.control);
	spin_lock_irqsave(&sco.lock, flags);
	generation = sco.generation;
	if (!sco.active || !sco.owned || !sco.running || sco.rejected) {
		sco.armed = false;
		spin_unlock_irqrestore(&sco.lock, flags);
		btcvsd_stop_irq();
		goto out;
	}
	if (sco.armed) {
		spin_unlock_irqrestore(&sco.lock, flags);
		goto out;
	}
	ctl = readl(sco.pkv + 0x148);
	layout = (ctl >> 18) & 7;
	if (!btcvsd_control(ctl) || !btcvsd_codec_supported(ctl)) {
		if (time_before(jiffies, sco.activate_deadline)) {
			retry = true;
		} else {
			sco.rejected = true;
			sco.owned = false;
			sco.rejected_codec++;
			btcvsd_tx_reset(&sco.txq, generation);
			sco.staged = 0;
			dev_warn(
				&sco.hdev->dev,
				"BTCVSD activation refused ctl=%#x (requires matching codec and pending IRQ)\n",
				ctl);
		}
		spin_unlock_irqrestore(&sco.lock, flags);
		if (!retry)
			btcvsd_stop_irq();
		goto out;
	}
	if (!btcvsd_address(readl(sco.pkv + 0x140), layout, sco.sram_size,
			    &off) ||
	    !btcvsd_address(readl(sco.pkv + 0x144), layout, sco.sram_size,
			    &off)) {
		sco.invalid++;
		sco.rejected = true;
		sco.owned = false;
		btcvsd_tx_reset(&sco.txq, generation);
		sco.staged = 0;
		spin_unlock_irqrestore(&sco.lock, flags);
		btcvsd_stop_irq();
		goto out;
	}
	spin_unlock_irqrestore(&sco.lock, flags);
	/* Old generation's handler must be stopped before re-arming a new link. */
	btcvsd_stop_irq();
	ret = regmap_read(sco.gate_map, 0xf00, &sco.original_gate);
	if (ret)
		goto refuse;
	sco.original_gate &= 0x800;
	ret = regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0x800);
	if (ret)
		goto refuse;
	sco.gate_owned = true;
	enable_irq(sco.irq);
	sco.irq_on = true;
	spin_lock_irqsave(&sco.lock, flags);
	if (generation == sco.generation && sco.active && sco.owned &&
	    sco.running) {
		ret = regmap_update_bits(sco.gate_map, 0xf00, 0x800, 0);
		sco.armed = !ret;
		if (ret) {
			spin_unlock_irqrestore(&sco.lock, flags);
			btcvsd_stop_irq();
			goto refuse;
		}
	} else {
		spin_unlock_irqrestore(&sco.lock, flags);
		btcvsd_stop_irq();
		goto out;
	}
	spin_unlock_irqrestore(&sco.lock, flags);
	goto out;
refuse:
	spin_lock_irqsave(&sco.lock, flags);
	if (generation == sco.generation) {
		sco.owned = sco.armed = false;
		sco.rejected = true;
		sco.invalid++;
		btcvsd_tx_reset(&sco.txq, generation);
		sco.staged = 0;
	}
	spin_unlock_irqrestore(&sco.lock, flags);
out:
	mutex_unlock(&sco.control);
	if (retry)
		mod_delayed_work(system_wq, &sco.configure,
				 msecs_to_jiffies(20));
}
/* 1: leave skb to BEIF; 0: consumed; negative: caller frees failed packet. */
int btmtk_btcvsd_send(struct sk_buff *skb)
{
	unsigned char data[258];
	unsigned long flags;
	unsigned int n;
	int ret = 1;
	if (!btcvsd_transport_enabled() || !sco.hdev ||
	    hci_skb_pkt_type(skb) != HCI_SCODATA_PKT)
		return 1;
	spin_lock_irqsave(&sco.lock, flags);
	if (!sco.active || (!sco.owned && !sco.rejected))
		goto out;
	if (sco.rejected) {
		ret = -EOPNOTSUPP;
		goto out;
	}
	if (skb->len > sizeof(data) || skb_copy_bits(skb, 0, data, skb->len) ||
	    !(n = btcvsd_sco_header(data, skb->len, sco.handle))) {
		ret = -EINVAL;
		goto out;
	}
	/* Receive-only observation deliberately consumes validated PCM packets.
	 * No encoded TX data is available until packing has been established. */
	if (sco_cvsd_observe && sco.air == SCO_AIRMODE_CVSD)
		goto consumed;
	if (sco_cvsd && sco.air == SCO_AIRMODE_CVSD) {
		if ((n & 1) || !btcvsd_cvsd_fifo_push(&sco.pcm_tx,
						 sco.generation, data + 3, n)) {
			sco.overflows++;
			btcvsd_cvsd_reject_locked();
			ret = (n & 1) ? -EINVAL : -ENOBUFS;
			goto out;
		}
		sco.pcm_high_water = max(sco.pcm_high_water, sco.pcm_tx.used);
		queue_work(sco.codec_wq, &sco.codec_work);
		goto consumed;
	}
	if (!btcvsd_tx_push(&sco.txq, sco.generation, data + 3, n)) {
		sco.overflows++;
		sco.tx_discard += sco.txq.used + sco.staged;
		btcvsd_tx_reset(&sco.txq, sco.generation);
		sco.staged = 0;
		btcvsd_tx_push(&sco.txq, sco.generation, data + 3, n);
	}
consumed:
	sco.hdev->stat.sco_tx++;
	sco.hdev->stat.byte_tx += skb->len;
	ret = 0;
out:
	spin_unlock_irqrestore(&sco.lock, flags);
	if (!ret)
		kfree_skb(skb);
	return ret;
}
int btmtk_btcvsd_recv(struct hci_dev *hdev, struct sk_buff *skb)
{
	unsigned long flags;
	unsigned char header[2];
	bool discard = false;
	if (btcvsd_transport_enabled() && sco.hdev &&
	    hci_skb_pkt_type(skb) == HCI_SCODATA_PKT &&
	    skb->len >= 3 && !skb_copy_bits(skb, 0, header, 2)) {
		spin_lock_irqsave(&sco.lock, flags);
		discard = sco.active && (sco.owned || sco.rejected) &&
			  (get_unaligned_le16(header) & 0xfff) == sco.handle;
		if (discard)
			sco.duplicates++;
		spin_unlock_irqrestore(&sco.lock, flags);
	}
	if (discard) {
		kfree_skb(skb);
		return 0;
	}
	return hci_recv_frame(hdev, skb);
}

static void btcvsd_notify(struct hci_dev *hdev, unsigned int event)
{
	struct hci_conn *conn;
	unsigned long flags;
	unsigned int handle = 0, air = 0, setting = 0;
	bool active = false;
	if (event != HCI_NOTIFY_ENABLE_SCO_TRANSP &&
	    event != HCI_NOTIFY_ENABLE_SCO_CVSD &&
	    event != HCI_NOTIFY_DISABLE_SCO)
		return;
	/* Called with the hdev lock held. Never lock hdev again or sleep here. */
	if (event != HCI_NOTIFY_DISABLE_SCO) {
		list_for_each_entry(conn, &hdev->conn_hash.list, list) {
			if ((conn->type == SCO_LINK ||
			     conn->type == ESCO_LINK) &&
			    conn->state == BT_CONNECTED &&
			    conn->codec.data_path == 0) {
				if (active) {
					active = false;
					break;
				} /* one link only */
				active = true;
				handle = conn->handle;
				setting = conn->setting;
				air = conn->setting & SCO_AIRMODE_MASK;
			}
		}
	}
	spin_lock_irqsave(&sco.lock, flags);
	if (!sco.ready || !sco.running)
		active = false;
	sco.active = active;
	sco.generation++;
	sco.armed = sco.owned = sco.rejected = false;
	btcvsd_tx_reset(&sco.txq, sco.generation);
	btcvsd_rx_reset(&sco.rxq, sco.generation);
	btcvsd_cvsd_fifo_reset(&sco.pcm_tx, sco.generation, 2160);
	btcvsd_cvsd_fifo_reset(&sco.encoded_tx, sco.generation, 1080);
	sco.cvsd_rx_head = sco.cvsd_rx_used = 0;
	sco.cvsd_starved = true;
	sco.staged = 0;
	if (active) {
		sco.previous_irq_ns = sco.first_tx_ns = sco.last_underflow_ns =
			sco.last_resync_ns = 0;
		sco.handle = handle;
		sco.air = air;
		sco.flowctl = hci_dev_test_flag(hdev, HCI_SCO_FLOWCTL);
		sco.samples = sco.pending = sco.invalid = 0;
		sco.deadline = jiffies + 12 * HZ;
		sco.activate_deadline = jiffies + 2 * HZ;
		sco.owned = !sco.flowctl && ((sco_msbc && air == 3) ||
					    ((sco_cvsd_observe || sco_cvsd) && air == SCO_AIRMODE_CVSD));
		if (sco.owned && sco_cvsd && air == SCO_AIRMODE_CVSD &&
		    !btcvsd_cvsd_pcm_supported(setting, hdev->sco_mtu)) {
			sco.owned = false;
			sco.rejected = true;
			dev_warn(&hdev->dev,
				 "BTCVSD CVSD requires PCM16 voice setting0x60 and MTU>=120 (setting=%#x mtu=%u)\n",
				 setting, hdev->sco_mtu);
		}
		if (sco_cvsd_observe && air == SCO_AIRMODE_CVSD)
			sco.observation_count = 0;
		if (btcvsd_transport_enabled() && sco.flowctl)
			dev_warn(
				&hdev->dev,
				"BTCVSD transport requires disabled SCO flow control\n");
	}
	spin_unlock_irqrestore(&sco.lock, flags);
	if (btcvsd_transport_enabled())
		mod_delayed_work(system_wq, &sco.configure, 0);
	if (sco_diagnostic && active)
		mod_delayed_work(system_wq, &sco.poll, 0);
}

static void btcvsd_poll(struct work_struct *work)
{
	unsigned long flags;
	unsigned int offset, ctl, rx, tx, layout;
	bool again;
	spin_lock_irqsave(&sco.lock, flags);
	if (!sco.ready || !sco.active || time_after_eq(jiffies, sco.deadline))
		goto out;
	ctl = readl(sco.pkv + 0x148);
	rx = readl(sco.pkv + 0x140);
	tx = readl(sco.pkv + 0x144);
	layout = (ctl >> 18) & 7;
	sco.samples++;
	sco.pending += !!(ctl & BIT(31));
	if (!btcvsd_address(rx, layout, sco.sram_size, &offset) ||
	    !btcvsd_address(tx, layout, sco.sram_size, &offset))
		sco.invalid++;
	if (sco.samples == 1 || ((ctl ^ sco.ctl) & (7u << 25)))
		dev_info(
			&sco.hdev->dev,
			"BTCVSD diagnostic handle=%u air=%u flowctl=%u ctl=%#x codec=%u layout=%u rx=%#x tx=%#x\n",
			sco.handle, sco.air, sco.flowctl, ctl, (ctl >> 25) & 3,
			layout, rx, tx);
	sco.ctl = ctl;
	sco.rx = rx;
	sco.tx = tx;
	sco.gate = readl(sco.infra + 0xf00);
	again = sco.active &&
		time_before(jiffies + msecs_to_jiffies(20), sco.deadline);
	if (again)
		mod_delayed_work(system_wq, &sco.poll, msecs_to_jiffies(20));
out:
	spin_unlock_irqrestore(&sco.lock, flags);
}

static int btcvsd_stats_show(struct seq_file *s, void *unused)
{
	unsigned long flags;
	spin_lock_irqsave(&sco.lock, flags);
	seq_printf(
		s,
		"diagnostic=%u active=%u generation=%u handle=%u air=%u flowctl=%u samples=%u pending=%u invalid=%u ctl=%#x codec=%u layout=%u rx=%#x tx=%#x gate=%#x\n",
		sco_diagnostic, sco.active, sco.generation, sco.handle, sco.air,
		sco.flowctl, sco.samples, sco.pending, sco.invalid, sco.ctl,
		(sco.ctl >> 25) & 3, (sco.ctl >> 18) & 7, sco.rx, sco.tx,
		sco.gate);
	seq_printf(
		s,
		"stream=%u owned=%u armed=%u rejected=%u irq=%u tx_frames=%u rx_frames=%u underflows=%u overflows=%u tx_discard=%u rx_discard=%u duplicates=%u rx_drops=%u rejected_codec=%u queued=%u staged=%u\n",
		sco_msbc, sco.owned, sco.armed, sco.rejected, sco.irqs,
		sco.tx_frames, sco.rx_frames, sco.underflows, sco.overflows,
		sco.tx_discard, sco.rx_discard, sco.duplicates, sco.rx_drops,
		sco.rejected_codec, sco.txq.used, sco.staged);
	seq_printf(
		s,
		"rx_diagnostic=%u snapshots=%u mutations=%u max_delay_ns=%llu max_read_delay_ns=%llu max_service_ns=%llu first_tx_ns=%llu last_underflow_ns=%llu last_resync_ns=%llu\n",
		sco_rx_diagnostic, sco.snapshots, sco.mutations,
		sco.max_delay_ns, sco.max_read_delay_ns, sco.max_service_ns,
		sco.first_tx_ns, sco.last_underflow_ns, sco.last_resync_ns);
	seq_printf(s, "cvsd=%u pcm_queued=%u encoded_queued=%u rx_batches=%u pcm_high=%u encoded_high=%u rx_high=%u codec_batches=%u codec_stale=%u codec_max_ns=%llu codec_max_rx_delay_ns=%llu\n",
		   sco_cvsd, sco.pcm_tx.used, sco.encoded_tx.used, sco.cvsd_rx_used,
		   sco.pcm_high_water, sco.encoded_high_water, sco.cvsd_rx_high_water,
		   sco.codec_batches, sco.codec_stale, sco.codec_max_ns,
		   sco.codec_max_delay_ns);
	spin_unlock_irqrestore(&sco.lock, flags);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(btcvsd_stats);

static int btcvsd_rx_show(struct seq_file *s, void *unused)
{
	struct btcvsd_snapshot *copy;
	unsigned long flags;
	unsigned int i, j;
	copy = kmalloc(sizeof(sco.snapshot), GFP_KERNEL);
	if (!copy)
		return -ENOMEM;
	spin_lock_irqsave(&sco.lock, flags);
	memcpy(copy, sco.snapshot, sizeof(sco.snapshot));
	spin_unlock_irqrestore(&sco.lock, flags);
	for (i = 0; i < BTCVSD_SNAPSHOTS; i++) {
		struct btcvsd_snapshot *v = &copy[i];
		if (!v->serial)
			continue;
		seq_printf(
			s,
			"serial=%u generation=%u handle=%u raised_ns=%llu service_ns=%llu copied_ns=%llu reread_ns=%llu interval_ns=%llu ctl=%#x ctl_after=%#x address=%#x address_after=%#x layout=%u bytes=%u frame_index=%u status=%u changed=%u ctl_second=%#x address_second=%#x\n",
			v->serial, v->generation, v->handle, v->raised_ns,
			v->service_ns, v->copied_ns, v->reread_ns,
			v->interval_ns, v->ctl, v->ctl_after, v->address,
			v->address_after, v->layout, v->bytes, v->frame_index,
			v->status, v->changed, v->ctl_second,
			v->address_second);
		seq_printf(s, "frame=%60phN\n", v->frame);
		for (j = 0; j < v->bytes; j += 30)
			seq_printf(s, "offset=%u first=%30phN second=%30phN\n",
				   j, v->first + j, v->second + j);
	}
	kfree(copy);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(btcvsd_rx);

static int btcvsd_observe_show(struct seq_file *s, void *unused)
{
	struct btcvsd_observation o;
	unsigned long flags;
	unsigned int i, j, count;
	spin_lock_irqsave(&sco.lock, flags);
	count = sco.observation_count;
	spin_unlock_irqrestore(&sco.lock, flags);
	seq_printf(s, "capacity=%u count=%u\n", BTCVSD_OBSERVATIONS, count);
	for (i = 0; i < count; i++) {
		spin_lock_irqsave(&sco.lock, flags);
		o = sco.observations[i];
		spin_unlock_irqrestore(&sco.lock, flags);
		seq_printf(s, "index=%u ns=%llu generation=%u ctl=%08x address=%08x bytes=%u\n",
			   i, o.ns, o.generation, o.ctl, o.address, o.bytes);
		for (j = 0; j < o.bytes; j += 30)
			seq_printf(s, "offset=%u data=%30phN\n", j, o.data + j);
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(btcvsd_observe);

static void btcvsd_free_observations(void *data)
{
	kvfree(data);
}

static void btcvsd_destroy_codec_queue(void *data)
{
	destroy_workqueue(data);
}

int btmtk_btcvsd_init(struct platform_device *pdev, struct hci_dev *hdev)
{
	struct device_node *node;
	struct resource res;
	struct of_phandle_args irq;
	const char *names[] = { "sco-pkv", "sco-sram", "infracfg" };
	void __iomem *mapped[3];
	int ret = 0, i, index;
	if (!pdev || !of_machine_is_compatible("mediatek,mt6897"))
		return 0;
	if (sco_cvsd && sco_cvsd_observe)
		return -EINVAL;
	spin_lock_init(&sco.lock);
	INIT_DELAYED_WORK(&sco.poll, btcvsd_poll);
	INIT_DELAYED_WORK(&sco.configure, btcvsd_configure);
	INIT_WORK(&sco.codec_work, btcvsd_codec_work);
	mutex_init(&sco.control);
	sco.hdev = hdev;
	/* The vendor uses a synthetic platform_device with no of_node. Hold the
  * matching DT node explicitly while translating the named resources. */
	node = of_find_compatible_node(NULL, NULL, "mediatek,bt");
	if (!node) {
		ret = -ENODEV;
		goto put_node;
	}
	index = of_property_match_string(node, "reg-names", "sco-pkv");
	if (index < 0) {
		ret = (sco_diagnostic || btcvsd_transport_enabled()) ? -ENODEV : 0;
		goto put_node;
	}
	for (i = 0; i < 3; i++) {
		index = of_property_match_string(node, "reg-names", names[i]);
		if (index < 0 || of_address_to_resource(node, index, &res)) {
			ret = -EINVAL;
			goto put_node;
		}
		if (resource_size(&res) < (i == 0 ? 0x14c :
					   i == 1 ? 180 :
						    0xf04)) {
			ret = -EINVAL;
			goto put_node;
		}
		mapped[i] = devm_ioremap(&pdev->dev, res.start,
					 resource_size(&res));
		if (!mapped[i]) {
			ret = -ENOMEM;
			goto put_node;
		}
		if (i == 1) {
			sco.sram_size = resource_size(&res);
			sco.sram_phys = res.start;
		}
	}
	sco.pkv = mapped[0];
	sco.sram = mapped[1];
	sco.infra = mapped[2];
	index = of_property_match_string(node, "interrupt-names", "sco");
	if (index < 0 || of_irq_parse_one(node, index, &irq)) {
		ret = -EINVAL;
		goto put_node;
	}
	/* Parse only: no IRQ request, unmask or gate write in diagnostic mode. */
	if (irq.args_count < 3 || irq.args[0] != 0 ||
	    irq.args[2] != IRQ_TYPE_LEVEL_HIGH) {
		of_node_put(irq.np);
		ret = -EINVAL;
		goto put_node;
	}
	dev_info(
		&pdev->dev,
		"BTCVSD resources: SRAM=%pa+%pa IRQ-spec=%u/%u/%u diagnostic=%u\n",
		&sco.sram_phys, &sco.sram_size, irq.args[0], irq.args[1],
		irq.args[2], sco_diagnostic);
	of_node_put(irq.np);
	if (btcvsd_transport_enabled()) {
		sco.gate_map = syscon_regmap_lookup_by_compatible(
			"mediatek,mt6897-infracfg-ao");
		if (IS_ERR(sco.gate_map)) {
			ret = PTR_ERR(sco.gate_map);
			goto put_node;
		}
		if (regmap_might_sleep(sco.gate_map)) {
			ret = -EINVAL;
			goto put_node;
		}
		sco.irq = of_irq_get(node, index);
		if (sco.irq <= 0) {
			ret = sco.irq ?: -EINVAL;
			goto put_node;
		}
		ret = devm_request_threaded_irq(&pdev->dev, sco.irq,
						btcvsd_irq_top, btcvsd_irq,
						IRQF_ONESHOT | IRQF_NO_AUTOEN,
						"btmtk-btcvsd", &sco);
		if (ret)
			goto put_node;
	}
	if (sco_cvsd) {
		sco.codec_wq = alloc_ordered_workqueue("btmtk-cvsd",
						      WQ_HIGHPRI | WQ_MEM_RECLAIM);
		if (!sco.codec_wq) {
			ret = -ENOMEM;
			goto put_node;
		}
		ret = devm_add_action_or_reset(&pdev->dev,
					       btcvsd_destroy_codec_queue, sco.codec_wq);
		if (ret)
			goto put_node;
	}
	if (sco_cvsd_observe) {
		sco.observations = kvcalloc(BTCVSD_OBSERVATIONS,
					    sizeof(*sco.observations), GFP_KERNEL);
		if (!sco.observations) {
			ret = -ENOMEM;
			goto put_node;
		}
		ret = devm_add_action_or_reset(&pdev->dev,
					       btcvsd_free_observations,
					       sco.observations);
		if (ret)
			goto put_node;
		sco.observe_debug = debugfs_create_file("btmtk_btcvsd_cvsd", 0400,
							NULL, NULL,
							&btcvsd_observe_fops);
	}
	sco.debug = debugfs_create_file("btmtk_btcvsd", 0444, NULL, NULL,
					&btcvsd_stats_fops);
	if (sco_rx_diagnostic)
		sco.rx_debug = debugfs_create_file("btmtk_btcvsd_rx", 0400,
						   NULL, NULL, &btcvsd_rx_fops);
	sco.ready = true;
	hdev->notify = btcvsd_notify;
put_node:
	if (ret)
		sco.hdev = NULL;
	of_node_put(node);
	return ret;
}

void btmtk_btcvsd_open(void)
{
	unsigned long flags;
	if (!sco.hdev)
		return;
	spin_lock_irqsave(&sco.lock, flags);
	if (sco.ready)
		sco.running = true;
	spin_unlock_irqrestore(&sco.lock, flags);
}

void btmtk_btcvsd_shutdown(void)
{
	unsigned long flags;
	if (!sco.hdev)
		return;
	spin_lock_irqsave(&sco.lock, flags);
	sco.running = false;
	sco.active = sco.owned = sco.armed = false;
	sco.generation++;
	btcvsd_cvsd_fifo_reset(&sco.pcm_tx, sco.generation, 2160);
	btcvsd_cvsd_fifo_reset(&sco.encoded_tx, sco.generation, 1080);
	sco.cvsd_rx_head = sco.cvsd_rx_used = 0;
	spin_unlock_irqrestore(&sco.lock, flags);
	cancel_delayed_work_sync(&sco.poll);
	cancel_delayed_work_sync(&sco.configure);
	mutex_lock(&sco.control);
	btcvsd_stop_irq();
	mutex_unlock(&sco.control);
	cancel_work_sync(&sco.codec_work);
}
void btmtk_btcvsd_remove(void)
{
	unsigned long flags;
	if (!sco.hdev)
		return;
	/* Serialize detachment with notify before cancelling any queued poll. */
	hci_dev_lock(sco.hdev);
	sco.hdev->notify = NULL;
	spin_lock_irqsave(&sco.lock, flags);
	sco.ready = false;
	sco.running = false;
	sco.active = sco.owned = sco.armed = false;
	sco.generation++;
	btcvsd_cvsd_fifo_reset(&sco.pcm_tx, sco.generation, 2160);
	btcvsd_cvsd_fifo_reset(&sco.encoded_tx, sco.generation, 1080);
	sco.cvsd_rx_head = sco.cvsd_rx_used = 0;
	spin_unlock_irqrestore(&sco.lock, flags);
	hci_dev_unlock(sco.hdev);
	cancel_delayed_work_sync(&sco.poll);
	cancel_delayed_work_sync(&sco.configure);
	mutex_lock(&sco.control);
	btcvsd_stop_irq();
	mutex_unlock(&sco.control);
	cancel_work_sync(&sco.codec_work);
	debugfs_remove(sco.debug);
	debugfs_remove(sco.rx_debug);
	debugfs_remove(sco.observe_debug);
	sco.hdev = NULL;
}
