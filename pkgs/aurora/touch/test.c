/* Validate the adapter boundary without executing the OEM library or uinput. */
#define main adapter_main
#include "stock-core.c"
#undef main
#include <assert.h>
#include <sys/wait.h>

static void point(unsigned char *p, unsigned state, unsigned id, int x, int y)
{
	put32(p, 1);
	put32(p + 8, state);
	put32(p + 12, id);
	put32(p + 20, x);
	put32(p + 24, y);
}

static void set_dpms(const char *path, const char *state)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	assert(fd >= 0);
	write_all(fd, state, strlen(state));
	close(fd);
}

static size_t count_events(int fd, unsigned *releases)
{
	struct input_event events[64];
	int flags = fcntl(fd, F_GETFL);
	assert(flags >= 0 && !fcntl(fd, F_SETFL, flags | O_NONBLOCK));
	ssize_t n = read(fd, events, sizeof(events));
	assert(!fcntl(fd, F_SETFL, flags));
	if (n < 0 && errno == EAGAIN) n = 0;
	assert(n >= 0 && n % sizeof(*events) == 0);
	if (releases) {
		*releases = 0;
		for (size_t i = 0; i < (size_t)n / sizeof(*events); ++i)
			if (events[i].code == ABS_MT_TRACKING_ID && events[i].value == -1) ++*releases;
	}
	return n / sizeof(*events);
}

static unsigned char record_buffer[1746];

static unsigned char *make_record(unsigned flags, unsigned length)
{
	memset(record_buffer, 0, sizeof(record_buffer));
	memcpy(record_buffer, "HTRF", 4);
	record_buffer[16] = length & 0xff;
	record_buffer[17] = length >> 8;
	record_buffer[18] = flags;
	return record_buffer;
}

/* check_record dies on invalid input: run it in a child. */
static bool record_rejected(const unsigned char *record, ssize_t n)
{
	pid_t pid = fork();
	assert(pid >= 0);
	if (!pid) {
		int null = open("/dev/null", O_WRONLY);
		dup2(null, 2);
		check_record(record, n);
		_exit(0);
	}
	int status;
	assert(waitpid(pid, &status, 0) == pid);
	return !(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

static void stream_records(void)
{
	assert(check_record(make_record(0, 1722), 1746) == 0);
	assert(check_record(make_record(STREAM_RESUMED, 1722), 1746) == STREAM_RESUMED);
	assert(check_record(make_record(STREAM_PAUSED, 0), 24) == STREAM_PAUSED);
	assert(record_rejected(make_record(STREAM_PAUSED, 0), 1746));
	assert(record_rejected(make_record(STREAM_PAUSED | STREAM_RESUMED, 0), 24));
	assert(record_rejected(make_record(4, 1722), 1746));
	assert(record_rejected(make_record(0, 1722), 24));
	assert(record_rejected(make_record(0, 1700), 1746));
	unsigned char *bad = make_record(0, 1722);
	bad[23] = 1;
	assert(record_rejected(bad, 1746));
	fprintf(stderr, "touch stream records: pause, resume and reserved-byte checks passed\n");
}

int main(void)
{
	stream_records();
	unsigned char points[2400] = { 0 };
	int pipes[2];
	assert(!pipe(pipes));
	input_fd = pipes[1];
	point(points, 1, 0, 100, 200);
	point(points + 172, 1, 9, 143999, 319999);
	report_input(points);
	assert(active_slots[0] && active_slots[9]);
	memset(points, 0, sizeof(points));
	point(points, 0, 0, -1, -1);
	point(points + 172, 0, 9, -1, -1);
	report_input(points);
	assert(!active_slots[0] && !active_slots[9]);
	close(input_fd);
	input_fd = -1;
	struct input_event events[64];
	ssize_t n = read(pipes[0], events, sizeof(events));
	assert(n > 0 && n % sizeof(*events) == 0);
	unsigned releases = 0, syncs = 0;
	for (size_t i = 0; i < (size_t)n / sizeof(*events); ++i) {
		if (events[i].type == EV_ABS && events[i].code == ABS_MT_TRACKING_ID && events[i].value == -1)
			++releases;
		if (events[i].type == EV_SYN) ++syncs;
	}
	assert(releases == 2 && syncs == 2);
	assert(events[n / sizeof(*events) - 2].code == BTN_TOOL_FINGER);
	assert(events[n / sizeof(*events) - 2].value == 0);
	close(pipes[0]);

	/* A malformed later contact must not publish the earlier valid contact. */
	assert(!pipe(pipes));
	pid_t child = fork();
	assert(child >= 0);
	if (!child) {
		close(pipes[0]);
		input_fd = pipes[1];
		memset(points, 0, sizeof(points));
		point(points, 1, 0, 100, 200);
		point(points + 172, 1, 1, 144000, 0);
		report_input(points);
		_exit(99);
	}
	close(pipes[1]);
	assert(read(pipes[0], events, sizeof(events)) == 0);
	close(pipes[0]);
	int status;
	assert(waitpid(child, &status, 0) == child);
	assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
	puts("touch event boundary: multi-contact release and atomic validation passed");
	/* The display gate releases reported contacts on Off, hides contacts that
	 * persist across wake and reports new contacts after On. */
	const char *tmp = getenv("TMPDIR");
	char root[256], path[320];
	snprintf(root, sizeof(root), "%s/aurora-touch-test.XXXXXX", tmp ? tmp : "/tmp");
	assert(mkdtemp(root));
	drm_class = root;
	snprintf(path, sizeof(path), "%s/card0-DSI-1", root);
	assert(!mkdir(path, 0700));
	strcat(path, "/dpms");
	dpms_connector = "DSI-1";
	assert(!pipe(pipes));
	input_fd = pipes[1];
	set_dpms(path, "On\n");
	update_display_state(1000);
	assert(!display_off);
	memset(points, 0, sizeof(points));
	point(points, 1, 0, 100, 200);
	report_input(points);
	assert(count_events(pipes[0], NULL) > 0 && active_slots[0]);
	set_dpms(path, "Off\n");
	update_display_state(1050);
	assert(!display_off);
	update_display_state(1100);
	unsigned released;
	assert(display_off && !active_slots[0] && suppressed_slots[0]);
	assert(count_events(pipes[0], &released) == 5 && released == 1);
	memset(points, 0, sizeof(points));
	point(points, 2, 0, 110, 210);
	point(points + 172, 1, 1, 300, 400);
	report_input(points);
	set_dpms(path, "On\n");
	update_display_state(1200);
	assert(!display_off);
	memset(points, 0, sizeof(points));
	point(points, 2, 0, 120, 220);
	point(points + 172, 2, 1, 310, 410);
	report_input(points);
	memset(points, 0, sizeof(points));
	point(points, 0, 0, -1, -1);
	report_input(points);
	assert(count_events(pipes[0], NULL) == 0 && !suppressed_slots[0] && suppressed_slots[1]);
	memset(points, 0, sizeof(points));
	point(points + 344, 1, 2, 500, 600);
	report_input(points);
	assert(active_slots[2] && !active_slots[1] && count_events(pipes[0], NULL) > 0);
	/* Read failures and disappearance fail open and resolve the path again. */
	set_dpms(path, "Off\n");
	update_display_state(1300);
	assert(display_off && !active_slots[2] && suppressed_slots[2]);
	set_dpms(path, "");
	update_display_state(1400);
	assert(!display_off && dpms_fd < 0 && dpms_warned);
	set_dpms(path, "Off\n");
	update_display_state(1500);
	assert(display_off && dpms_fd >= 0);
	assert(!unlink(path));
	close(dpms_fd);
	dpms_fd = -1;
	update_display_state(1600);
	assert(!display_off && dpms_fd < 0);
	close(pipes[0]);
	close(pipes[1]);
	input_fd = -1;
	*strrchr(path, '/') = 0;
	assert(!rmdir(path) && !rmdir(root));
	puts("touch display gate: release, wake suppression and fail-open passed");
	return 0;
}
