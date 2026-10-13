/* Exercise the real decoder with guard pages and malformed DSP frames. */
#include <assert.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include "listener_buf.h"

int main(void) {
  size_t page = sysconf(_SC_PAGESIZE);
  unsigned char *mem = mmap(NULL, page * 2, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  assert(mem != MAP_FAILED);
  assert(mprotect(mem + page, page, PROT_NONE) == 0);
  unsigned char *frame = mem + page - 32;
  struct sbuf buf;
  remote_arg args[3] = {0};
  uint32_t len;
  /* A valid, aligned payload followed by a zero-length input and output. */
  memset(frame, 0, 32);
  len = 4; memcpy(frame, &len, 4); memcpy(frame + 8, "test", 4);
  sbuf_init(&buf, 0, frame, 20);
  assert(unpack_in_bufs(&buf, args, 2) == AEE_SUCCESS);
  assert(args[0].buf.nLen == 4 && !memcmp(args[0].buf.pv, "test", 4));
  assert(args[1].buf.nLen == 0 && args[1].buf.pv == NULL);
  assert(unpack_out_lens(&buf, args + 2, 1) == AEE_SUCCESS);
  /* Every truncated prefix must fail, even if allocation capacity is larger. */
  for (int n = 0; n < 20; n++) {
    sbuf_init(&buf, 0, frame, n);
    int rc = unpack_in_bufs(&buf, args, 2);
    if (!rc) rc = unpack_out_lens(&buf, args + 2, 1);
    assert(rc != AEE_SUCCESS);
  }
  uint32_t bad[] = {0x722f7372, 0x6e65764f, INT_MAX, 0x80000000U, UINT32_MAX};
  for (unsigned i = 0; i < sizeof(bad)/sizeof(bad[0]); i++) {
    memcpy(frame, &bad[i], 4);
    sbuf_init(&buf, 0, frame, 32);
    assert(unpack_in_bufs(&buf, args, 2) != AEE_SUCCESS);
    sbuf_init(&buf, 0, frame, 4);
    assert(unpack_out_lens(&buf, args, 1) != AEE_SUCCESS);
  }
  /* A length word ending directly at the guard page cannot authorize data. */
  len = 1; memcpy(mem + page - 4, &len, 4);
  sbuf_init(&buf, 0, mem + page - 4, 4);
  assert(unpack_in_bufs(&buf, args, 1) != AEE_SUCCESS);
  munmap(mem, page * 2);
  return 0;
}
