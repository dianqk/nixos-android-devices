"""Compile the actual FFmpeg drain functions against deterministic V4L2 mocks."""
from pathlib import Path
import sys
import re

source = Path(sys.argv[1]).read_text()
names = [
    'ff_v4l2_context_set_status', 'v4l2_stop_encode', 'v4l2_handle_event',
    'v4l2_dequeue_v4l2buf', 'ff_v4l2_context_enqueue_frame',
    'ff_v4l2_context_dequeue_packet',
]
parts = []
for name in names:
    # Calls can precede definitions; require the name on a definition line.
    match = re.search(r'^(?:static )?\w+[ *]+' + name + r'\([^;]*?\)\n\{', source, re.M)
    if not match:
        raise ValueError('Missing function definition: ' + name)
    start = match.start()
    end = source.index('\n}', match.end()) + 2
    parts.append(source[start:end])
Path(sys.argv[2]).write_text('\n\n'.join(parts) + '\n')
