#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <mqueue.h>
#include <stdio.h>
#include <string.h>

extern mqd_t get_message_queue(int create);

int main(void)
{
    /* Run in an isolated IPC namespace with the normal Linux limit of ten. */
    struct mq_attr excessive = {.mq_maxmsg = 20, .mq_msgsize = 128};
    mqd_t bad = mq_open("/umtp-limit-probe", O_RDWR | O_CREAT | O_EXCL,
                        0600, &excessive);
    if (bad != (mqd_t)-1) {
        mq_close(bad);
        mq_unlink("/umtp-limit-probe");
        fputs("test requires unprivileged default msg_max=10\n", stderr);
        return 1;
    }
    assert(errno == EINVAL);
    assert(get_message_queue(0) == (mqd_t)-1 && errno == ENOENT);
    mqd_t queue = get_message_queue(1);
    assert(queue != (mqd_t)-1);
    struct mq_attr attr;
    assert(mq_getattr(queue, &attr) == 0);
    assert(attr.mq_maxmsg == 10 && attr.mq_msgsize == 128);
    const char payload[] = "mount:USB Share 1";
    assert(mq_send(queue, payload, sizeof(payload), 3) == 0);
    char buffer[128];
    unsigned priority;
    assert(mq_receive(queue, buffer, sizeof(buffer), &priority) == sizeof(payload));
    assert(priority == 3 && memcmp(buffer, payload, sizeof(payload)) == 0);
    assert(mq_close(queue) == 0);
    assert(mq_unlink("/umtprd") == 0);
    assert(get_message_queue(0) == (mqd_t)-1 && errno == ENOENT);
    puts("uMTP non-root queue creation, round trip and cleanup: passed");
    return 0;
}
