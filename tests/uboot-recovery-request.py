#!/usr/bin/env python3
"""Compile the actual recovery-request callback and check both request sources."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
source = (root / 'board/mediatek/mediatek-mobile/mediatek-mobile.c').read_text()
start = source.index('static int do_recoveryrequest(')
end = source.index('\nU_BOOT_CMD(recoveryrequest', start)
fixture = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define CMD_RET_SUCCESS 0
#define CMD_RET_FAILURE 1
#define CMD_RET_USAGE 2
#define MTK_BOOT_MODE_RECOVERY 2
struct cmd_tbl { int unused; };
static int mode, request, calls;
static int mtk_lk_boot_mode(void) { return mode; }
static int mtk_misc_requests_recovery(const char *name) {
    assert(!strcmp(name, "misc")); ++calls; return request;
}
'''
main = r'''
int main(void) {
    char *args[] = {"recoveryrequest", "misc"};
    assert(do_recoveryrequest(NULL, 0, 1, args) == CMD_RET_USAGE);
    for (mode = -1; mode <= 3; ++mode)
        for (request = 0; request <= 1; ++request) {
            calls = 0;
            assert(do_recoveryrequest(NULL, 0, 2, args) ==
                   ((mode == 2 || request) ? CMD_RET_SUCCESS : CMD_RET_FAILURE));
            assert(calls == (mode == 2 ? 0 : 1));
        }
    return 0;
}
'''
with tempfile.TemporaryDirectory() as directory:
    c = pathlib.Path(directory) / 'test.c'
    exe = pathlib.Path(directory) / 'test'
    c.write_text(fixture + source[start:end] + main)
    subprocess.run(['cc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror', '-o', str(exe), str(c)], check=True)
    subprocess.run([str(exe)], check=True)
print('LK and read-only misc recovery request dispatch: PASS')
