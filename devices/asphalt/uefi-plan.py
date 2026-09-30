#!/usr/bin/env python3
"""Plan outer-GPT Y700 EFI storage from matching read-only sfdisk snapshots.

No block devices are opened. Output JSON includes a complete sfdisk script.
Applying a plan, formatting and installation are separate recovery operations.
"""
import argparse
import copy
import hashlib
import json
import re
import sys
import uuid

SECTOR = 4096
GIB = 1024 ** 3 // SECTOR
ALIGN = 1024 ** 2 // SECTOR
ESP = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
LINUX = '0FC63DAF-8483-4772-8E79-3D69D8477DE4'
USERDATA = '1B81E7E6-F50D-419B-A739-2AEEF8DA3335'
PREFIX = ['ssd', 'persist', 'lenovolock', 'oemowninfo', 'lenovocust',
          'lenovoraw', 'misc', 'keystore', 'frp', 'super', 'vbmeta_system_a',
          'vbmeta_system_b', 'metadata', 'rawdump', 'userdata']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalized_uuid(value):
    require(isinstance(value, str) and re.fullmatch(
        r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', value), 'Invalid UUID')
    require(uuid.UUID(value).int != 0, 'Zero UUID is invalid')
    return value.upper()


def integer(value):
    require(type(value) is int, 'Expected an integer sector count')
    return value


def check_dump(table, dump):
    """Reject stale/mixed snapshots; retain every non-target line verbatim."""
    headers, entries = {}, {}
    for line in dump.splitlines():
        if not line.strip():
            continue
        require(':' in line, 'Malformed sfdisk dump')
        key, value = map(str.strip, line.split(':', 1))
        if key.startswith('/dev/'):
            require(key not in entries, 'Duplicate partition in dump')
            fields = {}
            for field in re.split(r',\s*(?=[a-z-]+\s*=|bootable\b)', value):
                if field == 'bootable':
                    fields['bootable'] = True
                    continue
                name, val = map(str.strip, field.split('=', 1))
                require(name not in fields, 'Duplicate dump field')
                fields[name] = val.strip('"')
            entries[key] = fields
        else:
            require(key not in headers, 'Duplicate GPT dump header')
            headers[key] = value
    expected = {'label': 'gpt', 'label-id': table['id'], 'device': table['device'],
                'unit': 'sectors', 'first-lba': str(table['firstlba']),
                'last-lba': str(table['lastlba']), 'sector-size': str(SECTOR),
                'table-length': str(table['table-length'])}
    require({k: v.lower() for k, v in headers.items()} ==
            {k: v.lower() for k, v in expected.items()}, 'GPT dump headers differ from JSON')
    require(set(entries) == {p['node'] for p in table['partitions']}, 'GPT dump partition set differs')
    for part in table['partitions']:
        fields = entries[part['node']]
        want = {k: str(v) for k, v in part.items() if k != 'node'}
        for k in ['type', 'uuid']:
            fields[k] = normalized_uuid(fields[k])
            want[k] = normalized_uuid(want[k])
        if part.get('bootable'):
            want['bootable'] = True
        require(fields == want, 'GPT dump partition differs from JSON: ' + part['node'])


def make_plan(snapshot, dump, size, esp_uuid, root_uuid, esp_bytes=1024**3,
              minimum_root_bytes=16*1024**3):
    require(type(esp_bytes) is int and esp_bytes >= 0 and esp_bytes % (ALIGN * SECTOR) == 0,
            'ESP size must be zero (automatic) or a positive whole MiB')
    require(type(minimum_root_bytes) is int and minimum_root_bytes > 0,
            'Invalid minimum root size')
    esp_sectors = (esp_bytes or 1024**3) // SECTOR
    minimum_root = (minimum_root_bytes + SECTOR - 1) // SECTOR
    table = snapshot['partitiontable']
    require(table['label'] == 'gpt' and table['unit'] == 'sectors' and
            table['sectorsize'] == SECTOR, 'Require GPT with 4096-byte logical sectors')
    require(re.fullmatch(r'/dev/sd[a-z]+', table['device']), 'Expected a UFS SCSI disk')
    # util-linux emits table-length as a JSON string on some releases.
    require(re.fullmatch(r'[0-9]+', str(table['table-length'])) and
            int(table['table-length']) >= 17, 'GPT lacks 17 entry slots')
    first, last = integer(table['firstlba']), integer(table['lastlba'])
    require(0 < first < last, 'Invalid usable GPT range')
    parts = table['partitions']
    require(len(parts) in [15, 17], 'Unknown or partial partition layout')
    require([p['name'] for p in parts[:15]] == PREFIX, 'Unrecognized Android GPT prefix')
    identities = [normalized_uuid(table['id'])]
    end = first
    for number, part in enumerate(parts, 1):
        require(part['node'] == table['device'] + str(number), 'Non-contiguous GPT indices')
        start, length = integer(part['start']), integer(part['size'])
        require(start >= end and length > 0 and start + length - 1 <= last,
                'Overlapping or out-of-range GPT entry')
        identities.append(normalized_uuid(part['uuid']))
        normalized_uuid(part['type'])
        end = start + length
    require(len(set(identities)) == len(identities), 'Duplicate GPT UUID')
    require(end == last + 1, 'Last partition does not end at last usable sector')
    userdata = parts[14]
    require(userdata['type'].upper() == USERDATA, 'Unexpected userdata GPT type')
    check_dump(table, dump)
    before_hash = hashlib.sha256(dump.encode()).hexdigest()
    esp_uuid, root_uuid = map(normalized_uuid, [esp_uuid, root_uuid])
    require(esp_uuid != root_uuid and esp_uuid not in identities and root_uuid not in identities,
            'New UUIDs must be distinct from existing identities')
    state = {15: 'stock', 17: 'uefi'}[len(parts)]
    if state == 'uefi':
        boot, root = parts[15:]
        require(boot['name'] == 'linux-boot' and boot['type'].upper() == ESP and
                root['name'] == 'linux' and root['type'].upper() == LINUX and
                (esp_bytes == 0 or boot['size'] == esp_sectors) and root['size'] >= minimum_root and
                boot['start'] % ALIGN == 0 and root['start'] == boot['start'] + boot['size'] and
                0 <= boot['start'] - (userdata['start'] + userdata['size']) < ALIGN,
                'Unknown or incomplete EFI layout')
        require(size == 'existing', 'Matching EFI layout accepts only existing')
        return {'state': state, 'action': 'none', 'before_sha256': before_hash,
                'esp_bytes': boot['size'] * SECTOR, 'generations': 10, 'sfdisk': dump,
                'partitions': copy.deepcopy(parts), 'erases': []}
    match = re.fullmatch(r'([1-9][0-9]*)(GiB|%)', size)
    require(match, 'Use total ESP + root size, e.g. 128GiB or 50%')
    number = int(match[1])
    require(number <= 4096 and (match[2] != '%' or number < 100), 'Size out of range')
    requested = number * GIB if match[2] == 'GiB' else userdata['size'] * number // 100
    # Round the total allocation up by less than 1 MiB, so 17 GiB really
    # leaves at least 16 GiB after the fixed ESP, including at a GPT tail.
    boot_start = (last + 1 - requested) // ALIGN * ALIGN
    android_size = (boot_start - userdata['start']) // ALIGN * ALIGN
    require(android_size >= 32 * GIB, 'Android userdata would have less than 32 GiB')
    erases = ['userdata']
    root_start = boot_start + esp_sectors
    root_size = last + 1 - root_start
    require(root_size >= minimum_root, 'Allocation is smaller than the configured ESP + minimum root')
    require(boot_start >= userdata['start'] + android_size, 'Target partitions overlap userdata')
    new_parts = copy.deepcopy(parts[:15])
    new_parts[14]['size'] = android_size
    new_parts += [dict(node=table['device']+'16', name='linux-boot', start=boot_start,
                       size=esp_sectors, type=ESP, uuid=esp_uuid),
                  dict(node=table['device']+'17', name='linux', start=root_start,
                       size=root_size, type=LINUX, uuid=root_uuid)]
    lines = []
    for line in dump.splitlines():
        node = line.split(':', 1)[0].strip()
        if node == userdata['node']:
            line = re.sub(r'\bsize\s*=\s*\d+', 'size= '+str(android_size), line)
        lines.append(line)
    for p in new_parts[15:]:
        lines.append(f'{p["node"]} : start= {p["start"]}, size= {p["size"]}, '
                     f'type={p["type"]}, uuid={p["uuid"]}, name="{p["name"]}"')
    return {'state': state, 'action': 'repartition', 'before_sha256': before_hash,
            'esp_bytes': esp_sectors * SECTOR, 'generations': 10, 'erases': erases,
            'partitions': new_parts, 'sfdisk': '\n'.join(lines)+'\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('json_snapshot')
    parser.add_argument('sfdisk_snapshot')
    parser.add_argument('total_size', help='total ESP + ext4 quota, or existing for a completed GPT')
    parser.add_argument('esp_uuid')
    parser.add_argument('root_uuid')
    parser.add_argument('--esp-bytes', type=int, default=1024**3,
                        help='ESP size; 0 accepts an existing size and plans 1 GiB for new layouts')
    parser.add_argument('--minimum-root-bytes', type=int, default=16*1024**3)
    args = parser.parse_args()
    try:
        with open(args.json_snapshot) as f:
            table = json.load(f)
        with open(args.sfdisk_snapshot) as f:
            dump = f.read()
        result = make_plan(table, dump, args.total_size, args.esp_uuid, args.root_uuid,
                           args.esp_bytes, args.minimum_root_bytes)
        print(json.dumps(result, indent=2))
    except (ValueError, KeyError, TypeError) as error:
        sys.exit('Asphalt EFI plan rejected: '+str(error))


if __name__ == '__main__':
    main()
