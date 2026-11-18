"""Structural checks for this project's Android ARM64 boot images.

Header v0-v2 images carry a Linux kernel or U-Boot with its DTB. Header v4
images (boot partition only) carry U-Boot and, for RAM recovery, a FIT
payload as the ramdisk. Board identity comes from the root compatible
property of each actual DTB, never the filename, an arbitrary byte
substring, or a per-device hash.
"""
import struct
import zlib


BOARDS = {
    'xiaomi,unicorn': 'unicorn',
    'xiaomi,clover': 'clover',
    'xiaomi,clover-lte': 'clover',
    'xiaomi,polaris': 'polaris',
    'xiaomi,sheng': 'sheng',
    'xiaomi,aurora': 'aurora',
    'lenovo,asphalt': 'asphalt',
    # Experimental; their fastboot identities are unverified (see mobile_device).
    'alldocube,t880': 't880',
    'xiaomi,marble': 'marble',
}

FIT_PAYLOAD = b'ram-recovery'


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


def fdt_tree(blob):
    """Parse a complete FDT into nested {'props': {}, 'nodes': {}} dicts."""
    require(len(blob) >= 40, 'Truncated FDT')
    magic, total, structure, strings, _, version, _, _, stringsize, structuresize = struct.unpack_from('>10I', blob)
    require(magic == 0xd00dfeed and total == len(blob) and version == 17, 'Invalid FDT header')
    require(40 <= structure < total and structure % 4 == 0 and
            structure + structuresize <= total and 40 <= strings < total and
            strings + stringsize <= total, 'Invalid FDT bounds')
    pos, end = structure, structure + structuresize
    root, stack = None, []
    while pos + 4 <= end:
        token, = struct.unpack_from('>I', blob, pos)
        pos += 4
        if token == 1:
            name_end = blob.find(b'\0', pos, end)
            require(name_end >= 0, 'Invalid FDT node name')
            node = {'props': {}, 'nodes': {}}
            if not stack:
                require(root is None and name_end == pos, 'Invalid FDT root')
                root = node
            else:
                name = blob[pos:name_end].decode('ascii')
                require(name not in stack[-1]['nodes'], 'Duplicate FDT node')
                stack[-1]['nodes'][name] = node
            stack.append(node)
            pos = (name_end + 4) & ~3
        elif token == 2:
            require(stack, 'Invalid FDT nesting')
            stack.pop()
        elif token == 3:
            require(stack and pos + 8 <= end, 'Invalid FDT property')
            length, name = struct.unpack_from('>II', blob, pos)
            pos += 8
            require(pos + length <= end and name < stringsize, 'Invalid FDT property bounds')
            name_end = blob.find(b'\0', strings + name, strings + stringsize)
            require(name_end >= 0, 'Invalid FDT property name')
            stack[-1]['props'][blob[strings + name:name_end].decode('ascii')] = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            require(root is not None and not stack, 'Incomplete FDT tree')
            return root
        else:
            raise ValueError('Invalid FDT token')
    raise ValueError('Missing FDT end token')


def fdt_string(node, name):
    value = node['props'].get(name)
    require(value is not None and value.endswith(b'\0') and b'\0' not in value[:-1],
            f'Missing or invalid FDT string {name}')
    return value[:-1].decode('ascii')


def fit_recovery(blob):
    """Board and kernel command line of a project RAM-recovery FIT."""
    require(len(blob) >= 40 and blob[:4] == b'\xd0\x0d\xfe\xed', 'Not a FIT payload')
    total, = struct.unpack_from('>I', blob, 4)
    require(total <= len(blob), 'Truncated FIT payload')
    fit = fdt_tree(blob[:total])
    require(fit['props'].get('android-devices,payload') == FIT_PAYLOAD + b'\0', 'Not a RAM recovery FIT')
    images = fit['nodes'].get('images')
    configurations = fit['nodes'].get('configurations')
    require(images is not None and configurations is not None, 'Incomplete FIT')
    configuration = configurations['nodes'].get(fdt_string(configurations, 'default'))
    require(configuration is not None, 'Missing FIT default configuration')
    for role, kind in (('kernel', 'kernel_noload'), ('ramdisk', 'ramdisk'), ('fdt', 'flat_dt')):
        image = images['nodes'].get(fdt_string(configuration, role))
        require(image is not None and fdt_string(image, 'type') == kind and
                fdt_string(image, 'arch') == 'arm64' and 'data' in image['props'],
                f'Invalid FIT {role} image')
    fdt = images['nodes'][fdt_string(configuration, 'fdt')]
    require(fdt_string(fdt, 'compression') == 'none', 'Compressed FIT DTB')
    tree = fdt['props']['data']
    chosen = fdt_tree(tree)['nodes'].get('chosen')
    require(chosen is not None, 'FIT DTB has no /chosen')
    return dtb_board(tree), fdt_string(chosen, 'bootargs')


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


def recovery_targets(cmdline):
    targets = [arg for arg in cmdline.split() if arg.startswith('rd.systemd.unit=')]
    require(len(targets) <= 1, 'Conflicting initrd targets')
    return targets == ['rd.systemd.unit=mobile-recovery.target']


LZ4_LEGACY_MAGIC = b'\x02\x21\x4c\x18'


def lz4_block(src, limit):
    """Decode one LZ4 block (no frame header)."""
    out = bytearray()
    pos = 0
    def length(value):
        nonlocal pos
        if value == 15:
            while True:
                require(pos < len(src), 'Truncated LZ4 length')
                extra = src[pos]
                pos += 1
                value += extra
                if extra != 255:
                    break
        return value
    while pos < len(src):
        token = src[pos]
        pos += 1
        literals = length(token >> 4)
        require(pos + literals <= len(src), 'Truncated LZ4 literals')
        out += src[pos:pos + literals]
        pos += literals
        if pos == len(src):
            break
        require(pos + 2 <= len(src), 'Truncated LZ4 offset')
        offset = src[pos] | src[pos + 1] << 8
        pos += 2
        require(0 < offset <= len(out), 'Invalid LZ4 offset')
        match = length(token & 15) + 4
        for _ in range(match):
            out.append(out[-offset])
        require(len(out) <= limit, 'Oversized LZ4 block')
    return bytes(out)


def lz4_legacy(blob, limit=256 * 1024 * 1024):
    """Decode a legacy LZ4 frame (lz4 -l), as MediaTek LK accepts for kernels."""
    require(blob.startswith(LZ4_LEGACY_MAGIC), 'Not a legacy LZ4 frame')
    out = bytearray()
    pos = 4
    while pos < len(blob):
        require(pos + 4 <= len(blob), 'Truncated LZ4 block size')
        size, = struct.unpack_from('<I', blob, pos)
        pos += 4
        if blob[pos - 4:pos] == LZ4_LEGACY_MAGIC:
            continue
        require(0 < size <= len(blob) - pos, 'Invalid LZ4 block size')
        out += lz4_block(blob[pos:pos + size], 8 * 1024 * 1024)
        require(len(out) <= limit, 'Oversized LZ4 kernel')
        pos += size
    return bytes(out)


def kernel_board(kernel):
    """Board of the DTB appended to an ARM64 kernel or U-Boot payload."""
    appended = b''
    if kernel.startswith(LZ4_LEGACY_MAGIC):
        kernel = lz4_legacy(kernel)
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
    if appended:
        return dtb_sequence(appended)
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
    return candidates[0]


def inspect_v4(blob):
    """Header v4 boot image: U-Boot kernel and an optional recovery FIT."""
    page = 4096
    require(len(blob) >= page, 'Truncated Android v4 header')
    u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
    kernel_size, ramdisk_size, header_size = u32(8), u32(12), u32(20)
    require(header_size == 1584 and not any(blob[24:40]), 'Invalid Android v4 header')
    # The ramdisk is optional: like the stock boot image, LK then takes the
    # generic ramdisk from init_boot.
    require(kernel_size > 0, 'Invalid Android payload sizes')
    align = lambda size: (size + page - 1) // page * page
    ramdisk = page + align(kernel_size)
    payload_end = ramdisk + align(ramdisk_size) + align(u32(1580))
    require(payload_end <= len(blob), 'Truncated Android payload')
    board = kernel_board(blob[page:page + kernel_size])
    cmdline = blob[44:1580].split(b'\0', 1)[0].decode('ascii')
    recovery = recovery_targets(cmdline)
    payload = blob[ramdisk:ramdisk + ramdisk_size]
    if ramdisk_size and payload[:4] == b'\xd0\x0d\xfe\xed':
        fit_board, bootargs = fit_recovery(payload)
        require(fit_board == board, 'Recovery FIT and firmware DTBs name different boards')
        recovery = recovery_targets(bootargs)
        require(recovery, 'Recovery FIT does not start the recovery target')
    return board, recovery


def inspect_image(blob):
    require(len(blob) >= 1632 and blob[:8] == b'ANDROID!', 'Not an Android boot image')
    u32 = lambda offset: struct.unpack_from('<I', blob, offset)[0]
    if u32(40) == 4:
        return inspect_v4(blob)
    kernel_size, ramdisk_size, second_size = u32(8), u32(16), u32(24)
    page, version = u32(36), u32(40)
    require(version in (0, 1, 2), 'Only Android boot headers v0-v2 and v4 are supported')
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
    payload = blob[ramdisk:ramdisk + ramdisk_size]
    if payload[:4] == b'\xd0\x0d\xfe\xed':
        # u-boot-fit: the board's U-Boot image with a RAM recovery FIT ramdisk.
        require(not targets, 'U-Boot image header must not select an initrd target')
        fit_board, bootargs = fit_recovery(payload)
        require(fit_board == board, 'Recovery FIT and firmware DTBs name different boards')
        require(recovery_targets(bootargs), 'Recovery FIT does not start the recovery target')
        return board, True
    return board, targets == ['rd.systemd.unit=mobile-recovery.target']
