/* SPDX-License-Identifier: GPL-2.0-only */
/* Native sanitizer harness; no MMIO or target execution. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../tools/early-entry/fdt-guard.h"
static void run(const unsigned char *data, size_t len)
{
    unsigned char *p=malloc(len ? len : 1);
    struct eg_range bank={0x80000000,0x10000000};
    struct eg_input in={.blob=p,.mapped=len,.fdt_pa=0x81000000,
        .banks=&bank,.bank_count=1,.image={0x82000000,0x400000},
        .workspace={0x82300000,0x100000}};
    if(!p) abort();
    memcpy(p,data,len);
    int result=eg_fdt_guard(&in);
    if(result!=0 && result!=1) abort();
    free(p);
}
int main(void)
{
    unsigned char data[65536];
    size_t n=fread(data,1,sizeof(data),stdin);
    if(ferror(stdin) || n==sizeof(data)) return 1;
    for(size_t j=0;j<=n;j++) run(data,j);
    for(size_t j=0;j<n;j++) {
        for(unsigned bit=1;bit<256;bit<<=1) {
            data[j]^=bit; run(data,n); data[j]^=bit;
        }
    }
    puts("exact-allocation truncations and every-bit mutations passed");
    return 0;
}
