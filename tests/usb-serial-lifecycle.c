/* Host fixture for real u_serial.c callbacks; no USB controller is accessed. */
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

struct mutex { bool held; };
typedef struct { bool held; } spinlock_t;
struct file { int unused; };
struct tty_struct { int index; void *driver_data; };
struct kfifo { bool initialized; unsigned int len; };
struct gserial {
	void (*connect)(struct gserial *);
	void (*disconnect)(struct gserial *);
};
struct gs_port {
	struct { int count; struct tty_struct *tty; } port;
	spinlock_t port_lock;
	struct gserial *port_usb;
	unsigned int port_num;
	struct kfifo port_write_buf;
	int drain_wait, close_wait;
	bool suspended, start_delayed;
};
static struct { struct mutex lock; struct gs_port *port; } ports[1];
static struct gs_port port;
static struct tty_struct tty;
static struct file file;
static int allocation_error;
static unsigned int locks, allocations, frees, resets, wakes, waits;
static unsigned int connects, disconnects, io_starts;

#define WRITE_BUF_SIZE 8192
#define GFP_KERNEL 0
#define GS_CLOSE_TIMEOUT 15
#define HZ 100
#define pr_debug(...) ((void)0)
#define WARN_ON(condition) assert(!(condition))

static void mutex_lock(struct mutex *lock)
{
	assert(lock == &ports[0].lock && !lock->held);
	lock->held = true;
}

static void mutex_unlock(struct mutex *lock)
{
	assert(lock == &ports[0].lock && lock->held);
	lock->held = false;
}

static void spin_lock_irq(spinlock_t *lock)
{
	/* Catch an invalid address before dereferencing it, including NULL+offset. */
	assert(lock == &port.port_lock);
	assert(!lock->held);
	lock->held = true;
	locks++;
}

static void spin_unlock_irq(spinlock_t *lock)
{
	assert(lock == &port.port_lock && lock->held);
	lock->held = false;
}

static bool kfifo_initialized(struct kfifo *fifo) { return fifo->initialized; }
static unsigned int kfifo_len(struct kfifo *fifo) { return fifo->len; }

static int kfifo_alloc(struct kfifo *fifo, unsigned int size, int flags)
{
	assert(ports[0].lock.held && !port.port_lock.held);
	assert(!fifo->initialized && size == WRITE_BUF_SIZE);
	allocations++;
	if (allocation_error)
		return allocation_error;
	fifo->initialized = true;
	return 0;
}

static void kfifo_free(struct kfifo *fifo)
{
	assert(port.port_lock.held && fifo->initialized);
	fifo->initialized = false;
	fifo->len = 0;
	frees++;
}

static void kfifo_reset(struct kfifo *fifo)
{
	assert(port.port_lock.held && fifo->initialized);
	fifo->len = 0;
	resets++;
}

static void gs_start_io(struct gs_port *p)
{
	assert(p == &port && port.port_lock.held);
	io_starts++;
}

static void connect_port(struct gserial *gser)
{
	assert(gser == port.port_usb && port.port_lock.held);
	connects++;
}

static void disconnect_port(struct gserial *gser)
{
	assert(gser == port.port_usb && port.port_lock.held);
	disconnects++;
}

static struct gserial gserial = { connect_port, disconnect_port };

static void wake_up(int *queue)
{
	assert(queue == &port.close_wait && port.port_lock.held);
	wakes++;
}

/* Complete a queued write while gs_close() has dropped port_lock. */
static void drain_writes(int *queue, unsigned int timeout)
{
	assert(queue == &port.drain_wait && !port.port_lock.held);
	assert(timeout == GS_CLOSE_TIMEOUT * HZ);
	waits++;
	port.port_write_buf.len = 0;
}

#define wait_event_interruptible_timeout(queue, condition, timeout) do { \
	drain_writes(&(queue), (timeout)); \
	assert(condition); \
} while (0)

/* @USB_SERIAL_FUNCTIONS@ */

static void reset(void)
{
	memset(&port, 0, sizeof(port));
	memset(&tty, 0, sizeof(tty));
	memset(ports, 0, sizeof(ports));
	ports[0].port = &port;
	allocation_error = 0;
	locks = allocations = frees = resets = wakes = waits = 0;
	connects = disconnects = io_starts = 0;
}

static void assert_unlocked(void)
{
	assert(!ports[0].lock.held && !port.port_lock.held);
}

static void assert_failed_close(void)
{
	unsigned int previous_locks = locks;
	assert(tty.driver_data == NULL && port.port.count == 0);
	gs_close(&tty, &file);
	assert(locks == previous_locks);
	assert(frees == 0 && resets == 0 && wakes == 0);
	assert_unlocked();
}

static void test_missing_port(void)
{
	reset();
	ports[0].port = NULL;
	assert(gs_open(&tty, &file) == -ENODEV);
	assert_failed_close();
	assert(allocations == 0 && locks == 0);
}

static void test_failed_allocation_and_retry(void)
{
	reset();
	allocation_error = -ENOMEM;
	assert(gs_open(&tty, &file) == -ENOMEM);
	assert_failed_close();
	assert(!port.port_write_buf.initialized && allocations == 1);
	allocation_error = 0;
	assert(gs_open(&tty, &file) == 0);
	assert(tty.driver_data == &port && port.port.tty == &tty);
	assert(port.port.count == 1 && allocations == 2);
	gs_close(&tty, &file);
	assert(port.port.count == 0 && port.port.tty == NULL);
	assert(frees == 1 && wakes == 1);
	assert_unlocked();
}

static void test_repeated_open_and_close(void)
{
	reset();
	assert(gs_open(&tty, &file) == 0);
	assert(gs_open(&tty, &file) == 0);
	assert(port.port.count == 2 && allocations == 1);
	gs_close(&tty, &file);
	assert(port.port.count == 1 && port.port.tty == &tty);
	assert(frees == 0 && wakes == 0);
	gs_close(&tty, &file);
	assert(port.port.count == 0 && port.port.tty == NULL);
	assert(frees == 1 && wakes == 1);
	assert_unlocked();
}

static void test_connected_close_drains_writes(void)
{
	reset();
	port.port_usb = &gserial;
	assert(gs_open(&tty, &file) == 0);
	assert(connects == 1 && io_starts == 1);
	port.port_write_buf.len = 8;
	gs_close(&tty, &file);
	assert(disconnects == 1 && waits == 1 && resets == 1);
	assert(frees == 0 && wakes == 1 && port.port_write_buf.initialized);
	assert(port.port.count == 0 && port.port.tty == NULL);
	assert_unlocked();
}

static void test_suspended_open_and_close(void)
{
	reset();
	port.port_usb = &gserial;
	port.suspended = true;
	assert(gs_open(&tty, &file) == 0);
	assert(port.start_delayed && connects == 0 && io_starts == 0);
	gs_close(&tty, &file);
	assert(!port.start_delayed && disconnects == 0);
	assert(resets == 1 && frees == 0 && waits == 0 && wakes == 1);
	assert(port.port.count == 0 && port.port.tty == NULL);
	assert_unlocked();
}

int main(void)
{
	test_missing_port();
	test_failed_allocation_and_retry();
	test_repeated_open_and_close();
	test_connected_close_drains_writes();
	test_suspended_open_and_close();
	puts("PASS: gadget TTY failed opens, retry, reference counts, drain and suspend");
	return 0;
}
