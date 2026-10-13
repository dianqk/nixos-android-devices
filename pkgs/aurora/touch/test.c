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

int main(void)
{
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
	return 0;
}
