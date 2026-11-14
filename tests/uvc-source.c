#include <assert.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <linux/videodev2.h>
#include "video-source.h"
#include "video-buffers.h"
#include "test-source.h"
#include "v4l2.h"

static unsigned int supplied_fps = 30;

/* Simulate a capture driver adjusting VIDIOC_S_PARM without an error. */
int ioctl(int fd, unsigned long request, ...)
{
    assert(fd == -1 && request == VIDIOC_S_PARM);
    va_list args;
    va_start(args, request);
    struct v4l2_streamparm *parm = va_arg(args, struct v4l2_streamparm *);
    va_end(args);
    parm->parm.capture.timeperframe.denominator = supplied_fps;
    return 0;
}

int main(void)
{
    struct v4l2_device capture = { .fd = -1, .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
    assert(v4l2_set_frame_rate(&capture, 30) == 0);
    supplied_fps = 25;
    assert(v4l2_set_frame_rate(&capture, 30) < 0);
    struct video_source *source = test_video_source_create();
    assert(source);
    struct v4l2_pix_format format = {
        .width = 640, .height = 480, .pixelformat = V4L2_PIX_FMT_MJPEG,
    };
    assert(video_source_set_format(source, &format) < 0);
    format.pixelformat = V4L2_PIX_FMT_YUYV;
    assert(video_source_set_format(source, &format) == 0);
    assert(video_source_set_frame_rate(source, 30) == 0);
    size_t length = 640 * 480 * 2;
    unsigned char *memory = malloc(length + 64);
    assert(memory);
    memset(memory, 0x5a, length + 64);
    struct video_buffer buffer = { .mem = memory, .size = length };
    assert(video_source_stream_on(source) == 0);
    for (int frame = 0; frame < 3; frame++) {
        video_source_fill_buffer(source, &buffer);
        assert(buffer.bytesused == length);
        /* Distinct colour bars, repeated across rows, and no overrun. */
        assert(memcmp(memory, memory + 1120, 4) != 0);
        assert(memcmp(memory, memory + 1280, 1280) == 0);
        for (size_t i = length; i < length + 64; i++)
            assert(memory[i] == 0x5a);
    }
    assert(video_source_stream_off(source) == 0);
    video_source_destroy(source);
    free(memory);
    return 0;
}
