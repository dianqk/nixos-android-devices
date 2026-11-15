// SPDX-License-Identifier: GPL-2.0+
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <assert.h>
#include <libfdt.h>
typedef uint8_t u8;
typedef uint64_t u64;
#define CONFIG_NR_DRAM_BANKS 64
#define CONFIG_SYS_INIT_SP_BSS_OFFSET 0x180000
#define SZ_4K 0x1000UL
#define SZ_64K 0x10000UL
#define U64_MAX UINT64_MAX
#define __aligned(x) __attribute__((aligned(x)))
#define __section(x) __attribute__((section(x)))
#define ALIGN_DOWN(x, y) ((x) & ~((typeof(x))(y) - 1))
#define ALIGN(x, y) ALIGN_DOWN((x) + (y) - 1, y)
#define max(a, b) ((a) > (b) ? (a) : (b))
#define max_t(t, a, b) max((t)(a), (t)(b))
#define min_t(t, a, b) min((t)(a), (t)(b))
#define min(a, b) ((a) < (b) ? (a) : (b))
static jmp_buf fail;
static void panic(const char *msg)
{
	fprintf(stderr, "expected/reported: %s", msg);
	longjmp(fail, 1);
}
static u64 get_unaligned_be64(const void *p)
{
	fdt64_t v;
	memcpy(&v, p, 8);
	return fdt64_to_cpu(v);
}
static u64 mapped_initrd_start, mapped_initrd_size;
static uintptr_t dodge_test_image_start = 0xa8000000UL;
static uintptr_t dodge_test_bss_start = 0xa8200000UL;
static void mmu_map_region(u64 start, u64 size, int cached)
{
	assert(!cached);
	mapped_initrd_start = start;
	mapped_initrd_size = size;
}
#include DODGE_HANDOFF_SOURCE
static char original[4 * 1024 * 1024], ext[4 * 1024 * 1024], internal[4096];
static void reset_ext(void)
{
	assert(!fdt_open_into(original, ext, sizeof(ext)));
}
static int invoke(void)
{
	if (setjmp(fail))
		return 1;
	dodge_import_fdt(internal, ext);
	return 0;
}
static void set_mem(u64 a, u64 n)
{
	fdt64_t r[2] = { cpu_to_fdt64(a), cpu_to_fdt64(n) };
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg", r,
			    sizeof(r)));
}
static void add_res(const char *name, u64 a, u64 n)
{
	int p = fdt_path_offset(ext, "/reserved-memory");
	p = fdt_add_subnode(ext, p, name);
	fdt64_t r[2] = { cpu_to_fdt64(a), cpu_to_fdt64(n) };
	assert(!fdt_setprop(ext, p, "reg", r, sizeof(r)));
}
static int overlaps(u64 a, u64 b, u64 c, u64 d)
{
	return a < d && c < b;
}
static void check_excluded(u64 start, u64 size)
{
	int len;
	const fdt64_t *r = fdt_getprop(
		dodge_fdt, fdt_path_offset(dodge_fdt, "/memory"), "reg", &len);
	for (int i = 0; i < len / 16; i++) {
		u64 a = fdt64_to_cpu(r[i * 2]), b = fdt64_to_cpu(r[i * 2 + 1]);
		assert(!overlaps(start, start + size, a, a + b));
	}
}
int main(int argc, char **argv)
{
	if (argc > 1) {
		FILE *f = fopen(argv[1], "rb");
		assert(f);
		assert(fread(original, 1, sizeof(original), f) > 0);
		fclose(f);
	} else {
		assert(!fdt_create_empty_tree(original, sizeof(original)));
		assert(!fdt_setprop_string(original, 0, "compatible",
					   "qcom,sm8750"));
		assert(!fdt_setprop_u32(original, 0, "#address-cells", 2));
		assert(!fdt_setprop_u32(original, 0, "#size-cells", 2));
		int p = fdt_add_subnode(original, 0, "reserved-memory");
		assert(p >= 0);
		assert(!fdt_setprop_u32(original, p, "#address-cells", 2));
		assert(!fdt_setprop_u32(original, p, "#size-cells", 2));
		p = fdt_add_subnode(original, 0, "chosen");
		assert(p >= 0);
		assert(!fdt_setprop_u64(original, p, "linux,initrd-start",
					0xb6c6e000));
		assert(!fdt_setprop_u64(original, p, "linux,initrd-end",
					0xb7ffeb38));
		p = fdt_add_subnode(original, 0, "memory");
		assert(p >= 0);
		fdt64_t r[] = { cpu_to_fdt64(0xa8000000),
				cpu_to_fdt64(0x10000000),
				cpu_to_fdt64(0x880000000),
				cpu_to_fdt64(0x580000000) };
		assert(!fdt_setprop(original, p, "reg", r, sizeof(r)));
	}
	assert(!fdt_create_empty_tree(internal, sizeof(internal)));
	assert(fdt_add_subnode(internal, 0, "memory") >= 0);
	assert(fdt_add_subnode(internal, 0, "chosen") >= 0);
	assert(fdt_add_subnode(internal, 0, "reserved-memory") >= 0);
	reset_ext();
	assert(!invoke());
	dodge_map_initrd();
	int chosen = fdt_path_offset(ext, "/chosen");
	const fdt64_t *initrd_start =
		fdt_getprop(ext, chosen, "linux,initrd-start", NULL);
	const fdt64_t *initrd_end =
		fdt_getprop(ext, chosen, "linux,initrd-end", NULL);
	assert(mapped_initrd_start == ALIGN_DOWN(fdt64_to_cpu(*initrd_start), SZ_4K));
	assert(mapped_initrd_size ==
	       ALIGN(fdt64_to_cpu(*initrd_end), SZ_4K) - mapped_initrd_start);
	int rmtfs = fdt_path_offset(dodge_fdt, "/reserved-memory/rmtfs@d7c00000");
	int rmtfs_len;
	const fdt64_t *rmtfs_reg = fdt_getprop(dodge_fdt, rmtfs, "reg", &rmtfs_len);
	assert(rmtfs_reg && rmtfs_len == 16);
	assert(fdt64_to_cpu(rmtfs_reg[0]) == 0xd7c00000);
	assert(fdt64_to_cpu(rmtfs_reg[1]) == 0x400000);
	assert(fdt_getprop(dodge_fdt, rmtfs, "no-map", NULL));
	check_excluded(0xd7c00000, 0x400000);
	int root = fdt_path_offset(ext, "/reserved-memory"), node, len;
	const fdt64_t *r;
	fdt_for_each_subnode(node, ext, root) {
		r = fdt_getprop(ext, node, "reg", &len);
		if (!r)
			continue;
		for (int i = 0; i < len / 16; i++)
			check_excluded(fdt64_to_cpu(r[i * 2]),
				       fdt64_to_cpu(r[i * 2 + 1]));
		int p = fdt_path_offset(dodge_fdt, "/reserved-memory");
		p = fdt_subnode_offset(dodge_fdt, p,
				       fdt_get_name(ext, node, NULL));
		assert(!fdt_getprop(dodge_fdt, p, "phandle", NULL));
		assert(!fdt_getprop(dodge_fdt, p, "compatible", NULL));
	}
	check_excluded(0xb6c6e000, 0xb7ffeb38 - 0xb6c6e000);
	assert(fdt_subnode_offset(dodge_fdt,
				  fdt_path_offset(dodge_fdt,
						  "/reserved-memory"),
				  "ramoops-region") == -FDT_ERR_NOTFOUND);
	int arena_len;
	const fdt64_t *arena_banks =
		fdt_getprop(dodge_fdt, fdt_path_offset(dodge_fdt, "/memory"),
			    "reg", &arena_len);
	u64 top = dodge_select_arena(arena_banks, arena_len / 16, 0xa8000000,
				     0xa8380000, 0x3000000);
	assert(top > 0x90000000 && top <= 0xf0000000);
 printf("low relocation arena top: 0x%llx (48 MiB minimum)\n", (unsigned long long)top);
	fdt64_t high[] = { cpu_to_fdt64(0x880000000),
			   cpu_to_fdt64(0x580000000) };
	assert(!dodge_select_arena(high, 1, 0xa8000000, 0xa8380000, 0x3000000));
	fdt64_t source[] = { cpu_to_fdt64(0xa8000000),
			     cpu_to_fdt64(0x4000000) };
	assert(dodge_select_arena(source, 1, 0xa8000000, 0xac000000,
				  0x3000000) == 0);
	assert(dodge_select_arena(source, 1, 0xa8000000, 0xa8380000,
				  0x3000000) == 0xac000000);
	puts("PASS contiguous low USB arena, high-only rejection, running source exclusion");

	puts("PASS runtime map, reservations, initrd and geometry-only import");
	reset_ext();
	fdt64_t with_rmtfs[] = {
		cpu_to_fdt64(0xa8000000), cpu_to_fdt64(0x10000000),
		cpu_to_fdt64(0xd5100000), cpu_to_fdt64(0x2f00000),
	};
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg",
			    with_rmtfs, sizeof(with_rmtfs)));
	assert(!invoke());
	check_excluded(0xd7c00000, 0x400000);
	const fdt64_t *carved =
		fdt_getprop(dodge_fdt, fdt_path_offset(dodge_fdt, "/memory"),
			    "reg", &len);
	int shortened = 0;
	for (int i = 0; i < len / 16; i++)
		if (fdt64_to_cpu(carved[i * 2]) == 0xd5100000 &&
		    fdt64_to_cpu(carved[i * 2 + 1]) == 0x2b00000)
			shortened++;
	assert(shortened == 1);
	chosen = fdt_path_offset(ext, "/chosen");
	assert(!fdt_setprop_u64(ext, chosen, "linux,initrd-start", 0xd7bf0000));
	assert(!fdt_setprop_u64(ext, chosen, "linux,initrd-end", 0xd7c10000));
	assert(invoke());
	reset_ext();
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg",
			    with_rmtfs, sizeof(with_rmtfs)));
	dodge_test_image_start = 0xd7b00000;
	dodge_test_bss_start = 0xd7b20000;
	assert(invoke());
	dodge_test_image_start = 0xa8000000;
	dodge_test_bss_start = 0xa8200000;
	reset_ext();
	add_res("rmtfs@d7c00000", 0xd7c00000, 0x400000);
	assert(!invoke());
	reset_ext();
	add_res("rmtfs@d7c00000", 0xd6c00000, 0x400000);
	assert(invoke());
	puts("PASS fixed RMTFS control node, exact bank subtraction, "
	     "initrd/Image collision and OEM conflict guards");

	reset_ext();
	add_res("phandle-collision", 0xa9000000, 0x1000);
	int rp = fdt_path_offset(ext, "/reserved-memory/phandle-collision");
	assert(!fdt_setprop_u32(ext, rp, "phandle", 0x364));
	assert(!fdt_setprop_u32(internal, fdt_path_offset(internal, "/chosen"),
				"phandle", 0x364));
	assert(!invoke());
	rp = fdt_path_offset(dodge_fdt, "/reserved-memory/phandle-collision");
	assert(!fdt_getprop(dodge_fdt, rp, "phandle", NULL));
	reset_ext();
	fdt64_t rr[] = { cpu_to_fdt64(0xa8000000), cpu_to_fdt64(0x10000000),
			 cpu_to_fdt64(ALIGN_DOWN((uintptr_t)ext, 0x1000UL)),
			 cpu_to_fdt64(0x800000) };
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg", rr,
			    sizeof(rr)));
	assert(!invoke());
	check_excluded((uintptr_t)ext, fdt_totalsize(ext));
	puts("PASS colliding OEM phandle excluded and source FDT reserved");
	reset_ext();
	set_mem(0xa8000000, 0x10000000);
	add_res("boundary", 0xaf000000, 0x1000);
	assert(!invoke());
	check_excluded(0xaf000000, 0x1000);
	reset_ext();
	add_res("stack-collision", 0xa8300000, 0x1000);
	assert(invoke());
	reset_ext();
	set_mem(UINT64_MAX - 0xfff, 0x2000);
	assert(invoke());
	reset_ext();
	add_res("overflow", UINT64_MAX - 0xfff, 0x2000);
	assert(invoke());
	reset_ext();
	fdt64_t bad = 0;
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg", &bad,
			    8));
	assert(invoke());
	reset_ext();
	fdt64_t many[65 * 2] = { 0 };
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg", many,
			    sizeof(many)));
	assert(invoke());
	reset_ext();
	fdt64_t ov[] = { cpu_to_fdt64(0xa8000000), cpu_to_fdt64(0x10000000),
			 cpu_to_fdt64(0xb0000000), cpu_to_fdt64(0x100000) };
	assert(!fdt_setprop(ext, fdt_path_offset(ext, "/memory"), "reg", ov,
			    sizeof(ov)));
	assert(invoke());
	reset_ext();
	assert(!fdt_add_mem_rsv(ext, 0xaa000000, 0x100000));
	assert(!invoke());
	check_excluded(0xaa000000, 0x100000);
	reset_ext();
	assert(!fdt_setprop_u32(ext, 0, "#address-cells", 1));
	assert(invoke());
	puts("PASS boundary carveout, early stack, overflows, tuple width, bank count, overlap, reserve map, cell widths");
	return 0;
}
