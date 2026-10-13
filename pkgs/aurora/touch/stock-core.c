// SPDX-License-Identifier: MIT
/* Native ARM64 compatibility adapter for one hash-pinned Aurora touch library.
 * Executes the recovered core boundary, not the full Android touch daemon.
 * Supports saved HTRF replay or continuous input with Linux uinput.
 */
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/uinput.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "sha256.h"

#if !defined(__aarch64__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error This adapter executes ARM64 little-endian instructions.
#endif

static const char library_pin[] =
	"25354d7b53285a086e94d32543848f22e472cae958c65bdad0f5545e0a37947f";
static const char config_pin[] =
	"125577bcf8e8816e7f425264a222a4488a5497ff7f1bd7fe200169908cfe20fd";
static unsigned char *image, *configuration;
static size_t config_size;
static uint64_t frame_time;
static unsigned long frames_decoded, frames_processed, frames_skipped;
static unsigned long states[3];
static void *unavailable_object;
static bool json_frames = true, input_created, active_slots[12];
static int input_fd = -1, tracking_id;
static volatile sig_atomic_t stop_requested;

static void die(const char *message)
{
	fprintf(stderr, "stock-core: %s\n", message);
	exit(1);
}

static void require(bool condition, const char *message)
{
	if (!condition)
		die(message);
}

static uint16_t get16(const void *p) { uint16_t v; memcpy(&v, p, 2); return v; }
static uint32_t get32(const void *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t get64(const void *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static void put32(void *p, uint32_t v) { memcpy(p, &v, 4); }
static void put64(void *p, uint64_t v) { memcpy(p, &v, 8); }

static void write_all(int fd, const void *data, size_t size)
{
	const unsigned char *p = data;
	while (size) {
		ssize_t n = write(fd, p, size);
		if (n < 0 && errno == EINTR) continue;
		require(n > 0, "output write failed");
		p += n;
		size -= n;
	}
}

static void emit(int type, int code, int value)
{
	struct input_event e = { .type = type, .code = code, .value = value };
	if (input_fd >= 0)
		write_all(input_fd, &e, sizeof(e));
}

static void cleanup_input(void)
{
	if (input_fd < 0) return;
	/* Destruction also releases contacts in the kernel, including error exits. */
	if (input_created) ioctl(input_fd, UI_DEV_DESTROY);
	close(input_fd);
	input_fd = -1;
}

static void create_input(void)
{
	input_fd = open("/dev/uinput", O_WRONLY | O_CLOEXEC);
	require(input_fd >= 0, "cannot open uinput");
	require(!ioctl(input_fd, UI_SET_EVBIT, EV_KEY) &&
		!ioctl(input_fd, UI_SET_KEYBIT, BTN_TOUCH) &&
		!ioctl(input_fd, UI_SET_KEYBIT, BTN_TOOL_FINGER) &&
		!ioctl(input_fd, UI_SET_EVBIT, EV_ABS) &&
		!ioctl(input_fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT), "uinput capabilities failed");
	const unsigned int codes[] = { ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_TRACKING_ID,
		ABS_MT_POSITION_X, ABS_MT_POSITION_Y };
	const int maxima[] = { 143999, 319999, 11, 65535, 143999, 319999 };
	for (size_t i = 0; i < sizeof(codes) / sizeof(*codes); ++i) {
		struct uinput_abs_setup abs = { .code = codes[i], .absinfo.maximum = maxima[i] };
		require(!ioctl(input_fd, UI_SET_ABSBIT, codes[i]) &&
			!ioctl(input_fd, UI_ABS_SETUP, &abs), "uinput axis setup failed");
	}
	struct uinput_setup setup = {
		.id = { .bustype = BUS_VIRTUAL, .vendor = 0x1d6b, .product = 0x14 },
		.name = "Xiaomi 14 Ultra Touchscreen",
	};
	require(!ioctl(input_fd, UI_DEV_SETUP, &setup) &&
		!ioctl(input_fd, UI_DEV_CREATE), "uinput creation failed");
	input_created = true;
}

static void report_input(unsigned char *points)
{
	if (input_fd < 0) return;
	for (unsigned int i = 0; i < 12; ++i) {
		unsigned char *p = points + 172 * i;
		if (!get32(p)) continue;
		unsigned int state = get32(p + 8), id = get32(p + 12);
		int32_t x = get32(p + 20), y = get32(p + 24);
		require(state < 3 && id < 12, "unexpected input contact");
		if (state)
			require(x >= 0 && x <= 143999 && y >= 0 && y <= 319999,
				"contact outside configured geometry");
	}
	bool changed = false;
	for (unsigned int i = 0; i < 12; ++i) {
		unsigned char *p = points + 172 * i;
		if (!get32(p)) continue;
		unsigned int state = get32(p + 8), id = get32(p + 12);
		int x = get32(p + 20), y = get32(p + 24);
		require(state < 3 && id < 12, "unexpected input contact");
		if (state)
			require(x >= 0 && x <= 143999 && y >= 0 && y <= 319999,
				"contact outside configured geometry");
		emit(EV_ABS, ABS_MT_SLOT, id);
		if (!state) {
			if (active_slots[id]) emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
			active_slots[id] = false;
		} else {
			if (state == 1 || !active_slots[id]) {
				tracking_id = (tracking_id + 1) & 65535;
				emit(EV_ABS, ABS_MT_TRACKING_ID, tracking_id);
			}
			active_slots[id] = true;
			emit(EV_ABS, ABS_MT_POSITION_X, x);
			emit(EV_ABS, ABS_MT_POSITION_Y, y);
			emit(EV_ABS, ABS_X, x);
			emit(EV_ABS, ABS_Y, y);
		}
		changed = true;
	}
	if (changed) {
		bool active = false;
		for (unsigned int i = 0; i < 12; ++i) active |= active_slots[i];
		emit(EV_KEY, BTN_TOUCH, active);
		emit(EV_KEY, BTN_TOOL_FINGER, active);
		emit(EV_SYN, SYN_REPORT, 0);
	}
}

static unsigned char *read_file(const char *path, size_t *length, size_t limit)
{
	FILE *f = fopen(path, "rb");
	struct stat st;
	if (!f || fstat(fileno(f), &st))
		die("cannot open input");
	require(S_ISREG(st.st_mode) && st.st_size >= 0 &&
		(uint64_t)st.st_size <= limit, "input is not a bounded regular file");
	*length = (size_t)st.st_size;
	unsigned char *data = calloc(1, *length + 1);
	require(data != NULL, "allocation failed");
	require(fread(data, 1, *length, f) == *length, "short input read");
	fclose(f);
	return data;
}

static void check_pin(const unsigned char *data, size_t length, const char *pin)
{
	unsigned char digest[32];
	char hex[65];
	require(sha256(data, length, digest) == 0, "SHA-256 failed");
	for (size_t i = 0; i < sizeof(digest); ++i)
		snprintf(hex + 2 * i, 3, "%02x", digest[i]);
	require(!strcmp(hex, pin), "unsupported file hash");
}

/* The guest sees only the pinned INI. No Android filesystem is exposed. */
static FILE *guest_fopen(const char *path, const char *mode)
{
	require(!strcmp(path, "/odm/firmware/aurora_syna_thp_config.ini") &&
		!strcmp(mode, "r"), "unexpected guest fopen");
	FILE *f = fmemopen(configuration, config_size, "r");
	require(f != NULL, "fmemopen failed");
	return f;
}

static int guest_clock_gettime(clockid_t clock, struct timespec *ts)
{
	require(clock == CLOCK_MONOTONIC, "unmodeled guest clock");
	ts->tv_sec = frame_time / 1000000000;
	ts->tv_nsec = frame_time % 1000000000;
	return 0;
}

/* Bionic synchronization objects are not glibc objects. The core replay is
 * single-threaded and does not start any of the Android daemon's workers. */
static int guest_mutex(void *mutex, ...) { (void)mutex; return 0; }
static int guest_guard_acquire(uint8_t *guard) { return !*guard; }
static void guest_guard_release(uint8_t *guard) { *guard = 1; }

static size_t guest_strlen_chk(const char *s, size_t capacity)
{
	size_t n = strnlen(s, capacity);
	require(n < capacity, "unterminated fortified string");
	return n;
}

static const char *guest_strchr_chk(const char *s, int c, size_t capacity)
{
	(void)guest_strlen_chk(s, capacity);
	return strchr(s, c);
}

static void *guest_memcpy_chk(void *dst, const void *src, size_t n, size_t capacity)
{
	require(n <= capacity, "fortified copy overflow");
	return memcpy(dst, src, n);
}

static void *guest_memset_chk(void *dst, int value, size_t n, size_t capacity)
{
	require(n <= capacity, "fortified memset overflow");
	return memset(dst, value, n);
}

static char *guest_strncpy_chk2(char *dst, const char *src, size_t n,
			      size_t dst_capacity, size_t src_capacity)
{
	require(n <= dst_capacity, "fortified strncpy destination overflow");
	require(n <= src_capacity || strnlen(src, src_capacity) < src_capacity,
		"fortified strncpy source overflow");
	return strncpy(dst, src, n);
}

static int guest_vsnprintf_chk(char *dst, size_t n, int flags, size_t capacity,
			       const char *format, va_list ap)
{
	(void)flags;
	require(n <= capacity, "fortified snprintf overflow");
	return vsnprintf(dst, n, format, ap);
}

__attribute__((noinline, noreturn)) static void unmodeled_import(void)
{
	fprintf(stderr, "stock-core: unmodeled import from image offset %#" PRIxPTR "\n",
		(uintptr_t)__builtin_return_address(0) - (uintptr_t)image);
	exit(1);
}

struct binding { const char *name; void *address; };
#define BIND(name) { #name, (void *)(name) }
#define SHIM(name, function) { name, (void *)(function) }
static const struct binding bindings[] = {
	BIND(malloc), BIND(calloc), BIND(free), BIND(memset), BIND(memcpy), BIND(memmove),
	BIND(strlen), BIND(strchr), BIND(strncpy), BIND(strcmp), BIND(memcmp), BIND(sscanf),
	BIND(atoi), BIND(fgets), BIND(fclose), BIND(atanf), BIND(atan2f), BIND(qsort),
	BIND(vsnprintf),
	SHIM("fopen", guest_fopen), SHIM("clock_gettime", guest_clock_gettime),
	SHIM("pthread_mutex_init", guest_mutex), SHIM("pthread_mutex_lock", guest_mutex),
	SHIM("pthread_mutex_unlock", guest_mutex),
	SHIM("__cxa_guard_acquire", guest_guard_acquire),
	SHIM("__cxa_guard_release", guest_guard_release),
	SHIM("__strlen_chk", guest_strlen_chk), SHIM("__strchr_chk", guest_strchr_chk),
	SHIM("__memcpy_chk", guest_memcpy_chk), SHIM("__memset_chk", guest_memset_chk),
	SHIM("__strncpy_chk2", guest_strncpy_chk2),
	SHIM("__vsnprintf_chk", guest_vsnprintf_chk),
};

static uintptr_t resolve(const char *name, unsigned int type)
{
	for (size_t i = 0; i < sizeof(bindings) / sizeof(*bindings); ++i)
		if (!strcmp(name, bindings[i].name))
			return (uintptr_t)bindings[i].address;
	/* Bionic's FILE table is not accessed by the selected core path. */
	if (!strcmp(name, "__sF") && type == STT_OBJECT)
		return (uintptr_t)unavailable_object;
	require(type == STT_FUNC, "unknown undefined data symbol");
	return (uintptr_t)unmodeled_import;
}

static void *bounded(unsigned char *file, size_t size, uint64_t offset, uint64_t n)
{
	require(offset <= size && n <= size - offset, "ELF range out of bounds");
	return file + offset;
}

static void load_library(const char *path)
{
	size_t size;
	unsigned char *file = read_file(path, &size, 1024 * 1024);
	check_pin(file, size, library_pin);
	Elf64_Ehdr *eh = bounded(file, size, 0, sizeof(*eh));
	require(!memcmp(eh->e_ident, ELFMAG, SELFMAG) &&
		eh->e_ident[EI_CLASS] == ELFCLASS64 && eh->e_ident[EI_DATA] == ELFDATA2LSB &&
		eh->e_machine == EM_AARCH64 && eh->e_type == ET_DYN, "unsupported ELF");
	require(eh->e_phentsize == sizeof(Elf64_Phdr) &&
		eh->e_shentsize == sizeof(Elf64_Shdr), "unsupported ELF table size");
	Elf64_Phdr *ph = bounded(file, size, eh->e_phoff,
		(size_t)eh->e_phnum * sizeof(*ph));
	Elf64_Shdr *sh = bounded(file, size, eh->e_shoff,
		(size_t)eh->e_shnum * sizeof(*sh));
	require(sysconf(_SC_PAGESIZE) == 4096, "this pinned layout requires 4 KiB pages");
	const size_t image_size = 0xe7000;
	image = mmap(NULL, image_size, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	require(image != MAP_FAILED, "image allocation failed");
	unavailable_object = mmap(NULL, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	require(unavailable_object != MAP_FAILED, "guard allocation failed");
	for (unsigned int i = 0; i < eh->e_phnum; ++i) {
		if (ph[i].p_type != PT_LOAD)
			continue;
		require(ph[i].p_filesz <= ph[i].p_memsz, "invalid ELF segment");
		void *dst = bounded(image, image_size, ph[i].p_vaddr, ph[i].p_memsz);
		memcpy(dst, bounded(file, size, ph[i].p_offset, ph[i].p_filesz), ph[i].p_filesz);
	}
	for (unsigned int i = 0; i < eh->e_shnum; ++i) {
		if (sh[i].sh_type != SHT_RELA)
			continue;
		require(sh[i].sh_entsize == sizeof(Elf64_Rela) &&
			sh[i].sh_size % sizeof(Elf64_Rela) == 0 && sh[i].sh_link < eh->e_shnum,
			"invalid relocation table");
		Elf64_Shdr *symsec = &sh[sh[i].sh_link];
		require(symsec->sh_type == SHT_DYNSYM && symsec->sh_link < eh->e_shnum &&
			symsec->sh_entsize == sizeof(Elf64_Sym), "invalid dynamic symbols");
		Elf64_Sym *syms = bounded(file, size, symsec->sh_offset, symsec->sh_size);
		Elf64_Shdr *strsec = &sh[symsec->sh_link];
		char *strings = bounded(file, size, strsec->sh_offset, strsec->sh_size);
		Elf64_Rela *rel = bounded(file, size, sh[i].sh_offset, sh[i].sh_size);
		for (size_t n = 0; n < sh[i].sh_size / sizeof(*rel); ++n) {
			uintptr_t value;
			uint32_t type = ELF64_R_TYPE(rel[n].r_info);
			if (type == R_AARCH64_RELATIVE) {
				value = (uintptr_t)image + rel[n].r_addend;
			} else {
				require(type == R_AARCH64_ABS64 || type == R_AARCH64_GLOB_DAT ||
					type == R_AARCH64_JUMP_SLOT, "unsupported ELF relocation");
				size_t index = ELF64_R_SYM(rel[n].r_info);
				require(index < symsec->sh_size / sizeof(*syms), "invalid symbol index");
				Elf64_Sym *sym = &syms[index];
				require(sym->st_name < strsec->sh_size &&
					memchr(strings + sym->st_name, 0, strsec->sh_size - sym->st_name),
					"invalid symbol name");
				const char *name = strings + sym->st_name;
				/* Stock libc++ guard helpers use Android synchronization objects.
				 * Match the single-thread guard boundary used by offline replay. */
				if (!strcmp(name, "__cxa_guard_acquire") || !strcmp(name, "__cxa_guard_release")) {
					value = resolve(name, STT_FUNC);
				} else if (sym->st_shndx != SHN_UNDEF) {
					require(sym->st_value < image_size, "invalid defined symbol");
					value = (uintptr_t)image + sym->st_value;
				} else {
					require(sym->st_name < strsec->sh_size &&
						memchr(strings + sym->st_name, 0, strsec->sh_size - sym->st_name),
						"invalid symbol name");
					value = resolve(name, ELF64_ST_TYPE(sym->st_info));
				}
				value += rel[n].r_addend;
			}
			put64(bounded(image, image_size, rel[n].r_offset, 8), value);
		}
	}
	/* Android 14 disassembly: these signed thresholds guard selected log calls.
	 * Disable Android logging through data; executable instructions are unchanged. */
	const size_t log_levels[] = { 0xbfbec, 0xbfbc4, 0xc1324, 0xc13b0 };
	for (size_t i = 0; i < sizeof(log_levels) / sizeof(*log_levels); ++i)
		put32(image + log_levels[i], UINT32_MAX);
	for (unsigned int i = 0; i < eh->e_phnum; ++i) {
		if (ph[i].p_type != PT_LOAD)
			continue;
		size_t start = ph[i].p_vaddr & ~(size_t)4095;
		size_t end = (ph[i].p_vaddr + ph[i].p_memsz + 4095) & ~(size_t)4095;
		int prot = (ph[i].p_flags & PF_R ? PROT_READ : 0) |
			(ph[i].p_flags & PF_W ? PROT_WRITE : 0) |
			(ph[i].p_flags & PF_X ? PROT_EXEC : 0);
		require(!mprotect(image + start, end - start, prot), "segment mprotect failed");
	}
	__builtin___clear_cache((char *)image, (char *)image + image_size);
	free(file);
}

static unsigned char *hardware, *parameters, *decoded;
static unsigned char normal[1200], source_frame[4096];
#define FUNCTION(offset, type) ((type)(void *)(image + (offset)))
typedef void (*noargs_fn)(void);
typedef void (*onearg_fn)(void *);
typedef void (*twoargs_fn)(void *, void *);
typedef uint32_t (*copy_fn)(void *, void *);
typedef uint32_t (*alloc_fn)(void *, void *, unsigned int);
typedef void *(*compute_fn)(void *);

static void initialize_core(void)
{
	hardware = image + 0xcec30;
	parameters = image + 0xceda8;
	FUNCTION(0x935dc, noargs_fn)();
	const uint16_t geometry[] = { 1440, 3200, 18, 40 };
	const unsigned char ring_info[] = { 100, 1, 10, 5, 5 };
	memcpy(hardware, geometry, sizeof(geometry));
	memcpy(hardware + 8, ring_info, sizeof(ring_info));
	strcpy((char *)hardware + 21, "aurora_syna_thp_config.ini");
	FUNCTION(0x70fc4, twoargs_fn)(parameters, hardware);
	FUNCTION(0x3e334, onearg_fn)(hardware);
	FUNCTION(0x3e36c, onearg_fn)(parameters);
	require(!FUNCTION(0x95178, alloc_fn)(&decoded, hardware, 1), "frame allocation failed");
	require(decoded != NULL, "missing decoded frame");
}

static void validate_payload(const unsigned char *p)
{
	require(get16(p) == 0x5aa5 && get16(p + 44) == 1722 && get16(p + 46) == 1722 &&
		p[48] == 40 && p[49] == 18, "unsupported frame layout");
	require((get32(p + 4) ^ get32(p + 12)) == UINT32_MAX &&
		(get32(p + 8) ^ get32(p + 16)) == UINT32_MAX && get32(p + 8) == 425,
		"invalid frame metadata");
	uint32_t sum = 0, x = 0xa55a;
	for (unsigned int offset = 20; offset < 1720; offset += 4) {
		sum += get32(p + offset);
		x ^= get32(p + offset);
	}
	require(sum + x == get32(p + 4), "frame checksum mismatch");
	size_t extra = 1620 + p[59];
	require(extra + 4 <= 1722, "extension header out of bounds");
	size_t length = get16(p + extra + 2);
	if (length > 100) length = 100;
	require(extra + 4 + length < 1722, "extension out of bounds");
}

static void acknowledge(unsigned char *points, unsigned int changed)
{
	/* Synchronous consumer metadata from Android 14 hal_report_points (0x6f048). */
	require(!parameters[461] && !parameters[1940] && !parameters[1809], "unsupported report mode");
	uint32_t count = get32(points + 2300);
	require(count == changed, "inconsistent output count");
	if (count) {
		for (unsigned int i = 0; i < 12; ++i)
			put32(points + 172 * i, 0);
	} else if (points[2317]) {
		points[2318] = 0;
	}
	put32(points + 2312, changed);
	put32(points + 2304, count);
}

static void process_record(const unsigned char *header, const unsigned char *payload)
{
	validate_payload(payload);
	uint32_t sequence = get32(header + 4);
	frame_time = get64(header + 8);
	put64(source_frame, frame_time);
	put64(source_frame + 8, sequence);
	memcpy(source_frame + 24, payload, 1722);
	require(!FUNCTION(0x9536c, copy_fn)(decoded, source_frame), "stock decoder rejected frame");
	require(!FUNCTION(0x955f0, copy_fn)(decoded, normal), "stock normalization failed");
	++frames_decoded;
	require(normal[43] != 17, "debug frames require another main-loop path");
	FUNCTION(0x423f4, twoargs_fn)(parameters, normal);
	int32_t skip = (int32_t)get32(parameters + 17);
	require(skip >= 0, "negative startup skip count");
	if (skip) {
		put32(parameters + 17, skip - 1);
		++frames_skipped;
		if (json_frames)
			printf("{\"sequence\":%u,\"controller_frame\":%u,\"skipped\":true,\"slots\":[]}\n",
				sequence, get16(payload + 28));
		return;
	}
	unsigned char *points = FUNCTION(0x3e27c, compute_fn)(normal);
	require(points == image + 0xc93c8, "unexpected core output pointer");
	++frames_processed;
	unsigned int changed = 0;
	if (json_frames)
		printf("{\"sequence\":%u,\"controller_frame\":%u,\"report_count\":%u,\"slots\":[",
			sequence, get16(payload + 28), get32(points + 2300));
	for (unsigned int i = 0; i < 12; ++i) {
		unsigned char *point = points + 172 * i;
		if (!get32(point)) continue;
		uint32_t state = get32(point + 8), id = get32(point + 12);
		require(state < 3 && id < 12, "unexpected point state or ID");
		++states[state];
		if (json_frames)
			printf("%s{\"index\":%u,\"state\":%u,\"id\":%u,\"x_raw\":%d,\"y_raw\":%d}",
				changed ? "," : "", i, state, id,
				(int32_t)get32(point + 20), (int32_t)get32(point + 24));
		++changed;
	}
	if (json_frames) puts("]}");
	/* Android14 computes the temporal-state update inside 0x3cde4. */
	require(!parameters[461] && !parameters[1940] && !parameters[1809],
		"unsupported report mode");
	require(get32(points + 2300) == changed, "inconsistent output count");
	report_input(points);
	acknowledge(points, changed);
}

static void request_stop(int signal) { (void)signal; stop_requested = 1; }

static uint64_t monotonic_ms(void)
{
	struct timespec ts;
	require(!clock_gettime(CLOCK_MONOTONIC, &ts), "host clock failed");
	return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void live(const char *device, unsigned int seconds, const char *capture, bool input)
{
	/* Zero duration is reserved for --continuous; it writes no frame capture. */
	require((seconds >= 1 && seconds <= 600) || (!seconds && !capture),
		"invalid continuous/live mode");
	struct sigaction action = { .sa_handler = request_stop };
	sigemptyset(&action.sa_mask);
	require(!sigaction(SIGTERM, &action, NULL) && !sigaction(SIGINT, &action, NULL),
		"signal setup failed");
	if (input) create_input();
	int saved = -1;
	if (capture) {
		saved = open(capture, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
		require(saved >= 0, "cannot create capture (must not already exist)");
	}
	int fd = open(device, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	require(fd >= 0, "cannot open continuous raw stream");
	struct stat st;
	require(!fstat(fd, &st) && S_ISCHR(st.st_mode), "live input must be a character device");
	json_frames = false;
	uint64_t start = monotonic_ms(), last_frame = start;
	uint32_t previous_sequence = 0;
	uint16_t previous_controller = 0;
	uint64_t previous_timestamp = 0;
	unsigned long records_saved = 0;
	unsigned char record[24 + 4096];
	fprintf(stderr, "Stock touch core ready: continuous input, %u seconds, uinput=%u\n", seconds, input);
	while (!stop_requested && (!seconds || monotonic_ms() - start < (uint64_t)seconds * 1000)) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		int ret = poll(&pfd, 1, 250);
		if (ret < 0 && errno == EINTR) continue;
		require(ret >= 0, "raw stream poll failed");
		require(!(pfd.revents & (POLLERR | POLLHUP | POLLNVAL)), "raw stream stopped or overflowed");
		if (!(pfd.revents & POLLIN)) {
			require(monotonic_ms() - last_frame < 2000, "raw stream stalled");
			continue;
		}
		ssize_t n = read(fd, record, sizeof(record));
		if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
		require(n == 1746 && !memcmp(record, "HTRF", 4) && get16(record + 16) == 1722 &&
			!memcmp(record + 18, "\0\0\0\0\0\0", 6), "invalid continuous record");
		uint32_t sequence = get32(record + 4);
		uint16_t controller = get16(record + 24 + 28);
		uint64_t timestamp = get64(record + 8);
		if (frames_decoded && (sequence - previous_sequence != 1 ||
			(uint16_t)(controller - previous_controller) != 1)) {
			fprintf(stderr, "Frame discontinuity: transport=%u->%u controller=%u->%u interval_ns=%" PRIu64 "\n",
				previous_sequence, sequence, previous_controller, controller,
				timestamp - previous_timestamp);
			die("gap in continuous frame sequence");
		}
		previous_timestamp = timestamp;
		previous_sequence = sequence;
		previous_controller = controller;
		last_frame = monotonic_ms();
		/* At most ~6.5 MB is retained in RAM; processing continues afterwards. */
		if (saved >= 0 && records_saved < 4096) {
			write_all(saved, record, n);
			++records_saved;
		}
		process_record(record, record + 24);
	}
	close(fd);
	if (saved >= 0) require(!close(saved), "capture close failed");
	fprintf(stderr, "Continuous capture: %lu records saved, %lu frames consumed\n", records_saved, frames_decoded);
}

static void replay(const char *path)
{
	FILE *f = fopen(path, "rb");
	require(f != NULL, "cannot open capture");
	unsigned char header[24], payload[1722];
	const unsigned char zero[6] = { 0 };
	for (;;) {
		size_t n = fread(header, 1, sizeof(header), f);
		if (!n && feof(f)) break;
		require(n == sizeof(header), "truncated capture header");
		require(!memcmp(header, "HTRF", 4) && get16(header + 16) == sizeof(payload) &&
			!memcmp(header + 18, zero, sizeof(zero)), "unsupported HTRF header");
		require(fread(payload, 1, sizeof(payload), f) == sizeof(payload), "truncated frame");
		process_record(header, payload);
	}
	fclose(f);
}

int main(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "Usage: %s LIBRARY INI [--events FILE] CAPTURE [CAPTURE ...]\n"
			"       %s LIBRARY INI --live DEVICE SECONDS CAPTURE [--uinput]\n"
			"       %s LIBRARY INI --continuous DEVICE [--uinput]\n", argv[0], argv[0], argv[0]);
		return 2;
	}
	configuration = read_file(argv[2], &config_size, 1024 * 1024);
	check_pin(configuration, config_size, config_pin);
	load_library(argv[1]);
	initialize_core();
	atexit(cleanup_input);
	if (!strcmp(argv[3], "--continuous")) {
		require(argc == 5 || (argc == 6 && !strcmp(argv[5], "--uinput")),
			"invalid continuous arguments");
		live(argv[4], 0, NULL, argc == 6);
	} else if (!strcmp(argv[3], "--live")) {
		require(argc == 7 || (argc == 8 && !strcmp(argv[7], "--uinput")), "invalid live arguments");
		char *end;
		unsigned long duration = strtoul(argv[5], &end, 10);
		require(*argv[5] && !*end && duration >= 1 && duration <= 600, "invalid live duration");
		live(argv[4], duration, argv[6], argc == 8);
	} else {
		int first = 3;
		if (!strcmp(argv[first], "--events")) {
			require(argc >= 6, "missing event output or capture");
			input_fd = open(argv[4], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
			require(input_fd >= 0, "cannot create event output");
			first = 5;
		}
		for (int i = first; i < argc; ++i) replay(argv[i]);
	}
	require(frames_decoded != 0, "no input frames");
	fprintf(stderr, "{\"decoded\":%lu,\"startup_skipped\":%lu,\"core_processed\":%lu,"
		"\"down\":%lu,\"move\":%lu,\"up\":%lu}\n",
		frames_decoded, frames_skipped, frames_processed, states[1], states[2], states[0]);
	return ferror(stdout) ? 1 : 0;
}
