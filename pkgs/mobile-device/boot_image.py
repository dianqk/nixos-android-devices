"""Structural checks for this project's Android v0-v2 ARM64 boot images.

Board identity comes from the root compatible property of each actual DTB,
never the filename, an arbitrary byte substring, or a per-device hash.
"""
import struct
import zlib


BOARDS = {
    'xiaomi,clover': 'clover',
    'xiaomi,clover-lte': 'clover',
    'xiaomi,polaris': 'polaris',
    'xiaomi,sheng': 'sheng',
    'lenovo,asphalt': 'asphalt',
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def dtb_board(blob):
    require(len(blob) >= 40, 'Truncated DTB')
    magic, total, structure, strings, reserve, version, compat, cpu, stringsize, structuresize = struct.unpack_from('>10I', blob)
    require(magic == 0xd00dfeed and total == len(blob) and version == 17,
            'Invalid DTB header')
    require(40 <= structure < total and structure % 4 == 0 and
            structure + structuresize <= total and 40 <= strings < total and
            strings + stringsize <= total, 'Invalid DTB bounds')
    pos, end, depth = structure, structure + structuresize, 0
    compatibles = []
    root_seen = False
    while pos + 4 <= end:
        token, = struct.unpack_from('>I', blob, pos)
        pos += 4
        if token == 1:  # FDT_BEGIN_NODE
            name_end = blob.find(b'\0', pos, end)
            require(name_end >= 0, 'Invalid DTB node name')
            if depth == 0:
                require(not root_seen and name_end == pos, 'Invalid DTB root')
                root_seen = True
            depth += 1
            pos = (name_end + 4) & ~3
        elif token == 2:
            depth -= 1
            require(depth >= 0, 'Invalid DTB nesting')
        elif token == 3:
            require(depth > 0 and pos + 8 <= end, 'Invalid DTB property')
            length, name = struct.unpack_from('>II', blob, pos)
            pos += 8
            require(pos + length <= end and name < stringsize, 'Invalid DTB property bounds')
            name_end = blob.find(b'\0', strings + name, strings + stringsize)
            require(name_end >= 0, 'Invalid DTB property name')
            if depth == 1 and blob[strings + name:name_end] == b'compatible':
                require(not compatibles and length > 0 and blob[pos + length - 1] == 0,
                        'Invalid root compatible')
                compatibles = blob[pos:pos + length - 1].decode('ascii').split('\0')
            pos = (pos + length + 3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            require(root_seen and depth == 0, 'Incomplete DTB tree')
            boards = {BOARDS[c] for c in compatibles if c in BOARDS}
            require(len(boards) == 1, 'DTB has no unique supported board identity')
            return boards.pop()
        else:
            raise ValueError('Invalid DTB token')
    raise ValueError('Missing DTB end token')


def dtb_sequence(blob):
    boards = set()
    while blob:
        require(len(blob) >= 40 and blob[:4] == b'\xd0\x0d\xfe\xed', 'Missing appended DTB')
        total, = struct.unpack_from('>I', blob, 4)
        require(40 <= total <= len(blob), 'Truncated appended DTB')
        boards.add(dtb_board(blob[:total]))
        blob = blob[total:]
    require(len(boards) == 1, 'Missing or conflicting image board identities')
    return boards.pop()


def inspect_image(blob):
    require(len(blob) >= 1632 and blob[:8] == b'ANDROID!', 'Not an Android boot image')
    u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
    kernel_size, ramdisk_size, second_size = u32(8), u32(16), u32(24)
    page, version = u32(36), u32(40)
    require(version in (0, 1, 2), 'Only Android boot headers v0-v2 with a board DTB are supported')
    require(page in (2048, 4096, 8192, 16384) and len(blob) >= page,
            'Invalid Android page size/header')
    require(kernel_size > 0 and ramdisk_size > 0 and second_size == 0,
            'Invalid Android payload sizes or unsupported second stage')
    align = lambda size: (size + page - 1) // page * page
    ramdisk = page + align(kernel_size)
    payload_end = ramdisk + align(ramdisk_size)
    require(payload_end <= len(blob), 'Truncated Android payload')
    cmdline = (blob[64:576].split(b'\0', 1)[0] + blob[608:1632].split(b'\0', 1)[0]).decode('ascii')
    kernel = blob[page:page + kernel_size]
    appended = b''
    if kernel.startswith(b'\x1f\x8b'):
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            raw = decoder.decompress(kernel, 256 * 1024 * 1024)
        except zlib.error as error:
            raise ValueError('Invalid gzip kernel') from error
        require(decoder.eof, 'Truncated or oversized gzip kernel')
        appended = decoder.unused_data
    else:
        raw = kernel
    require(raw[56:60] == b'ARM\x64', 'Kernel is not an ARM64 Image')
    if version >= 1:
        require(u32(1644) == (1648 if version == 1 else 1660), 'Invalid Android extended header size')
        require(u32(1632) == 0, 'Recovery DTBO payload is not supported')
    if version == 2:
        size = u32(1648)
        require(size > 0 and payload_end + size <= len(blob), 'Missing or truncated boot-image DTB')
        board = dtb_sequence(blob[payload_end:payload_end + size])
        require(not appended, 'Conflicting appended and boot-image DTBs')
    elif appended:
        board = dtb_sequence(appended)
    else:
        # Uncompressed Image + DTB: require a complete DTB sequence at the end.
        candidates = []
        embedded_boards = set()
        pos = kernel.find(b'\xd0\x0d\xfe\xed', 64)
        while pos >= 0:
            try:
                total, = struct.unpack_from('>I', kernel, pos + 4)
                embedded_boards.add(dtb_board(kernel[pos:pos + total]))
                candidates.append(dtb_sequence(kernel[pos:]))
            except (ValueError, struct.error):
                pass
            pos = kernel.find(b'\xd0\x0d\xfe\xed', pos + 4)
        require(len(set(candidates)) == 1 and len(embedded_boards) == 1, 'Missing or ambiguous appended board DTB')
        board = candidates[0]
    targets = [arg for arg in cmdline.split() if arg.startswith('rd.systemd.unit=')]
    require(len(targets) <= 1, 'Conflicting initrd targets')
    return board, targets == ['rd.systemd.unit=mobile-recovery.target']
