/* Deterministic V4L2 responses for the real patched FFmpeg drain functions. */
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <poll.h>
#include <linux/videodev2.h>
#define AVERROR(e) (-(e))
#define AVERROR_EOF (-12345)
#define AV_LOG_ERROR 1
#define AV_LOG_WARNING 2
#define AV_LOG_DEBUG 3
#define av_log(...) ((void)0)
#define av_err2str(e) "error"
#define logger(c) NULL
#define V4L2BUF_AVAILABLE 0
#define V4L2BUF_IN_DRIVER 1

typedef struct { int unused; } AVFrame;
typedef struct { int size, index; } AVPacket;
typedef struct { int status; struct v4l2_buffer buf; struct v4l2_plane planes[VIDEO_MAX_PLANES]; } V4L2Buffer;
typedef struct {
    unsigned type; int done, streamon, num_buffers, width, height, sample_aspect_ratio;
    const char *name; struct v4l2_format format; V4L2Buffer *buffers;
} V4L2Context;
typedef struct {
    int fd, draining, encoder_drain, encoder_drain_error, reinit;
    void *avctx; V4L2Context capture, output;
} V4L2m2mContext;
static V4L2m2mContext state;
static V4L2Buffer buffers[4];
static V4L2m2mContext *ctx_to_m2mctx(V4L2Context *ctx) { (void)ctx; return &state; }
static int v4l2_resolution_changed(V4L2Context *c, struct v4l2_format *f) { (void)c; (void)f; return 0; }
static int v4l2_get_height(struct v4l2_format *f) { (void)f; return 720; }
static int v4l2_get_width(struct v4l2_format *f) { (void)f; return 1280; }
static int v4l2_get_sar(V4L2Context *c) { (void)c; return 1; }
static int v4l2_start_decode(V4L2Context *c) { (void)c; return 0; }
static int ff_set_dimensions(void *c, int w, int h) { (void)c; (void)w; (void)h; return 0; }
static int ff_v4l2_m2m_codec_reinit(V4L2m2mContext *s) { (void)s; return 0; }
static V4L2Buffer *v4l2_getfree_v4l2buf(V4L2Context *c) { (void)c; return NULL; }
static int ff_v4l2_buffer_avframe_to_buf(const AVFrame *f, V4L2Buffer *b) { (void)f; (void)b; return 0; }
static int ff_v4l2_buffer_enqueue(V4L2Buffer *b) { (void)b; assert(!"unexpected requeue"); return 0; }
static int ff_v4l2_buffer_buf_to_avpkt(AVPacket *p, V4L2Buffer *b) {
    p->size = V4L2_TYPE_IS_MULTIPLANAR(b->buf.type) ? b->planes[0].bytesused : b->buf.bytesused;
    p->index = b->buf.index; return 0;
}

enum { STEP_EVENT, STEP_BUFFER, STEP_DQERR, STEP_POLLERR, STEP_POLLFAIL, STEP_EVENTERR };
struct step { int kind, revents, index, bytes, flags, err; };
static struct step steps[10];
static int step_count, step_pos, poll_calls, stop_error, streamoff_count;
static int fake_poll(struct pollfd *p, unsigned long n, int timeout) {
    (void)timeout; assert(n == 1); assert(++poll_calls < 20); assert(step_pos < step_count);
    p->revents = steps[step_pos].revents;
    if (steps[step_pos].kind == STEP_POLLFAIL) { errno = steps[step_pos++].err; return -1; }
    if (steps[step_pos].kind == STEP_POLLERR) step_pos++;
    return 1;
}
static int fake_ioctl(int fd, unsigned long request, void *arg) {
    (void)fd;
    if (request == VIDIOC_ENCODER_CMD) { if (stop_error) { errno = stop_error; return -1; } return 0; }
    if (request == VIDIOC_STREAMOFF) { streamoff_count++; return 0; }
    if (request == VIDIOC_STREAMON) return 0;
    assert(step_pos < step_count);
    struct step *s = &steps[step_pos++];
    if (request == VIDIOC_DQEVENT) {
        if (s->kind == STEP_EVENTERR) { errno = s->err; return -1; }
        assert(s->kind == STEP_EVENT); ((struct v4l2_event *)arg)->type = V4L2_EVENT_EOS; return 0;
    }
    assert(request == VIDIOC_DQBUF);
    if (s->kind == STEP_DQERR) { errno = s->err; return -1; }
    assert(s->kind == STEP_BUFFER);
    struct v4l2_buffer *b = arg;
    b->index = s->index; b->flags = s->flags;
    if (V4L2_TYPE_IS_MULTIPLANAR(b->type)) b->m.planes[0].bytesused = s->bytes;
    else b->bytesused = s->bytes;
    return 0;
}
#define poll fake_poll
#define ioctl fake_ioctl
#include "ffmpeg-drain-functions.inc"

static void reset(int modern) {
    memset(&state, 0, sizeof(state)); memset(buffers, 0, sizeof(buffers));
    state.draining = 1; state.encoder_drain = modern;
    state.capture.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    state.output.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    state.capture.buffers = buffers; state.capture.num_buffers = 4;
    for (int i = 0; i < 4; i++) buffers[i].status = V4L2BUF_IN_DRIVER;
    step_count = step_pos = poll_calls = stop_error = streamoff_count = 0;
}
static void add(int kind, int revents, int index, int bytes, int flags, int err) {
    assert(step_count < 10); steps[step_count++] = (struct step){kind,revents,index,bytes,flags,err};
}
static void buffer(int index, int bytes, int flags) { add(STEP_BUFFER,POLLIN,index,bytes,flags,0); }
static int receive(AVPacket *p) { return ff_v4l2_context_dequeue_packet(&state.capture,p); }
int main(void) {
    AVPacket packet;
    for (int mode = 0; mode < 3; mode++) {
        reset(1);
        if (mode) add(STEP_EVENT,POLLPRI | (mode == 2 ? POLLIN : 0),0,0,0,0);
        buffer(1,0,V4L2_BUF_FLAG_ERROR); buffer(0,18272,0); buffer(2,0,V4L2_BUF_FLAG_LAST);
        assert(receive(&packet) == 0 && packet.size == 18272 && packet.index == 0);
        assert(!state.capture.done && buffers[1].status == V4L2BUF_AVAILABLE);
        assert(receive(&packet) == AVERROR_EOF); assert(step_pos == step_count);
    }
    reset(1); buffer(0,99,V4L2_BUF_FLAG_LAST);
    assert(receive(&packet) == 0 && packet.size == 99);
    assert(receive(&packet) == AVERROR_EOF && poll_calls == 1);
    reset(1); add(STEP_DQERR,POLLIN,0,0,0,EAGAIN); buffer(0,55,0);
    assert(receive(&packet) == 0 && packet.size == 55);
    reset(1); add(STEP_DQERR,POLLIN,0,0,0,EPIPE); assert(receive(&packet) == AVERROR_EOF);
    reset(1); add(STEP_DQERR,POLLIN,0,0,0,EIO); assert(receive(&packet) == AVERROR(EIO));
    reset(1); add(STEP_POLLERR,POLLERR,0,0,0,0); assert(receive(&packet) == AVERROR(EIO));
    reset(1); add(STEP_POLLFAIL,0,0,0,0,EBADF); assert(receive(&packet) == AVERROR(EBADF));
    reset(1); add(STEP_EVENTERR,POLLPRI,0,0,0,EIO); assert(receive(&packet) == AVERROR(EIO));
    reset(1); add(STEP_EVENTERR,POLLPRI,0,0,0,EAGAIN); buffer(0,77,0);
    assert(receive(&packet) == 0 && packet.size == 77);
    reset(0); buffer(0,0,0); assert(receive(&packet) == AVERROR_EOF);
    reset(0); add(STEP_EVENT,POLLPRI,0,0,0,0); assert(receive(&packet) == AVERROR_EOF);
    reset(0); state.draining=0;
    assert(ff_v4l2_context_enqueue_frame(&state.output,NULL) == 0 && state.encoder_drain && state.draining);
    reset(0); state.draining=0; stop_error=ENOTTY;
    assert(ff_v4l2_context_enqueue_frame(&state.output,NULL) == 0 && !state.encoder_drain && streamoff_count == 1);
    reset(0); state.draining=0; stop_error=EIO;
    assert(ff_v4l2_context_enqueue_frame(&state.output,NULL) == AVERROR(EIO) && !state.draining);
    reset(1); state.capture.done=1; state.encoder_drain_error=AVERROR(EIO);
    assert(ff_v4l2_context_set_status(&state.capture,VIDIOC_STREAMON) == 0);
    assert(!state.encoder_drain && !state.encoder_drain_error && !state.capture.done);
    reset(1); state.capture.type=V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buffer(0,27,V4L2_BUF_FLAG_LAST); assert(receive(&packet) == 0 && packet.size == 27);
    assert(receive(&packet) == AVERROR_EOF);
    puts("V4L2 encoder drain: response sequences passed");
}
