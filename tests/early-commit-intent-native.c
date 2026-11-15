/* SPDX-License-Identifier: GPL-2.0-only */
/* Native ASan/UBSan bounded parser mutations; input is an ordinary host file. */
#include "../tools/early-entry/commit-intent.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CAP (2U*1024U*1024U)
int main(int argc,char **argv)
{
    assert(argc==2);
    FILE *f=fopen(argv[1],"rb");assert(f);
    unsigned char *src=malloc(CAP),*mut=malloc(CAP),*out=malloc(CAP+32);
    assert(src && mut && out);
    size_t n=fread(src,1,CAP,f);assert(n>=40 && !ferror(f));assert(fgetc(f)==EOF);fclose(f);
    unsigned char g[32]={1},token[EG_INTENT_BYTES];
    struct eg_choice_observation o={.sequence=7,.mode=1};
    assert(eg_intent_encode(token,g,&o,0));
    memset(out,0xa5,CAP+32);
    assert(eg_fdt_copy_intent(src,n,out+16,CAP,token));
    unsigned state=1;
    for(unsigned trial=0;trial<2000;trial++) {
        memcpy(mut,src,n);state=state*1664525U+1013904223U;
        size_t at=state%n;mut[at]^=(unsigned char)(1U<<(state%8));
        size_t mapped=trial%3?n:(state%n),capacity=trial%4?CAP:(state%CAP);
        memset(out,0xa5,CAP+32);
        size_t size=eg_fdt_copy_intent(mut,mapped,out+16,capacity,token);
        for(unsigned i=0;i<16;i++)assert(out[i]==0xa5);
        for(size_t i=16+size;i<CAP+32;i++)assert(out[i]==0xa5);
        if(size)assert(size<=capacity && size%8==0);
    }
    free(src);free(mut);free(out);
    puts("2000 bounded FDT mutations + canaries passed");
    return 0;
}
