"""GPT geometry, snapshot consistency and refusal tests; no block devices."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest
import uuid

spec = importlib.util.spec_from_file_location('uefi_plan', Path(__file__).resolve().parents[1] / 'devices/asphalt/uefi-plan.py')
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)
ESP_UUID = '11111111-2222-4333-8444-555555555555'
ROOT_UUID = '11111111-2222-4333-8444-666666666666'


def dump(t):
    headers = [('label', 'label'), ('label-id', 'id'), ('device', 'device'),
               ('unit', 'unit'), ('first-lba', 'firstlba'), ('last-lba', 'lastlba'),
               ('sector-size', 'sectorsize'), ('table-length', 'table-length')]
    lines = [f'{name}: {t[key]}' for name, key in headers] + ['']
    lines += [f'{p["node"]} : start= {p["start"]}, size= {p["size"]}, '
              f'type={p["type"]}, uuid={p["uuid"]}, name="{p["name"]}"' for p in t['partitions']]
    return '\n'.join(lines)+'\n'


def table(capacity=512, device='/dev/sda'):
    parts = [dict(node=device+str(i+1), name=name, start=6+i*1024, size=1024,
                  type=planner.LINUX, uuid=str(uuid.UUID(int=i+1)))
             for i, name in enumerate(planner.PREFIX)]
    parts[-1].update(start=3272616, size=capacity*planner.GIB-32-3272616+1,
                     type=planner.USERDATA)
    return dict(label='gpt', id=str(uuid.UUID(int=100)), device=device, unit='sectors',
                firstlba=6, lastlba=capacity*planner.GIB-32, sectorsize=4096,
                **{'table-length': 32}, partitions=parts)


def plan(t, size, text=None):
    return planner.make_plan({'partitiontable': t}, dump(t) if text is None else text,
                             size, ESP_UUID, ROOT_UUID)


class PlanTests(unittest.TestCase):
    def test_sfdisk_string_table_length_and_attributes(self):
        t = table()
        t['table-length'] = '32'
        t['partitions'][3]['attrs'] = 'GUID:60'
        text = dump(t).replace('name="oemowninfo"', 'name="oemowninfo", attrs="GUID:60"')
        p = plan(t, '128GiB', text)
        self.assertEqual(p['partitions'][3], t['partitions'][3])

    def test_stock_quota_is_esp_plus_root_and_preserves_android_prefix(self):
        for capacity, size, device in [(256, '128GiB', '/dev/sda'), (512, '50%', '/dev/sdb')]:
            with self.subTest(capacity=capacity):
                t = table(capacity, device)
                p = plan(t, size)
                self.assertEqual(p['state'], 'stock')
                self.assertEqual(p['erases'], ['userdata'])
                self.assertEqual(p['partitions'][:14], t['partitions'][:14])
                boot, root = p['partitions'][15:]
                self.assertEqual(boot['size']*4096, 1024**3)
                self.assertEqual(boot['start'] % 256, 0)
                self.assertEqual(root['start'], boot['start']+boot['size'])
                self.assertEqual(root['start']+root['size'], t['lastlba']+1)
                self.assertEqual(p['before_sha256'], hashlib.sha256(dump(t).encode()).hexdigest())
                changed = copy.deepcopy(t)
                changed['partitions'] = p['partitions']
                planner.check_dump(changed, p['sfdisk'])

    def test_configured_esp_and_minimum_root(self):
        t = table()
        result = planner.make_plan({'partitiontable': t}, dump(t), '10GiB',
                                   ESP_UUID, ROOT_UUID, 512 * 1024**2, 8 * 1024**3)
        self.assertEqual(result['esp_bytes'], 512 * 1024**2)
        self.assertGreaterEqual(result['partitions'][-1]['size'] * 4096, 8 * 1024**3)

    def test_unsupported_partial_layout_is_refused(self):
        t = table()
        start = 3272616 + 96*planner.GIB
        start = (start+255)//256*256
        t['partitions'][14]['size'] = start-t['partitions'][14]['start']
        t['partitions'].append(dict(node='/dev/sda16', name='linux', start=start,
                                   size=t['lastlba']+1-start, type=planner.LINUX,
                                   uuid=str(uuid.UUID(int=16))))
        with self.assertRaises(ValueError):
            plan(t, 'existing')

    def test_minimum_total_quota_includes_alignment(self):
        t = table()
        p = plan(t, '17GiB')
        self.assertGreaterEqual(p['partitions'][16]['size'], 16 * planner.GIB)
        total = sum(part['size'] for part in p['partitions'][15:])
        self.assertGreaterEqual(total, 17 * planner.GIB)
        self.assertLess(total, 17 * planner.GIB + planner.ALIGN)

    def test_completed_layout_is_noop_and_partial_layout_refused(self):
        t = table()
        p = plan(t, '128GiB')
        t['partitions'] = p['partitions']
        # Generated UUIDs are ignored for a no-op, but must still be fresh.
        def retry():
            return planner.make_plan({'partitiontable': t}, dump(t), 'existing',
                                     str(uuid.UUID(int=101)), str(uuid.UUID(int=102)))
        self.assertEqual(retry()['action'], 'none')
        self.assertEqual(retry()['sfdisk'], dump(t))
        t['partitions'].pop()
        with self.assertRaises(ValueError):
            retry()

    def test_rejects_modified_snapshot_unsafe_geometry_and_identity(self):
        for mutate in [lambda t: t.update(sectorsize=512),
                       lambda t: t['partitions'][9].update(name='other'),
                       lambda t: t['partitions'][3].update(start=6),
                       lambda t: t['partitions'][14].update(size=1),
                       lambda t: t['partitions'][1].update(uuid=t['partitions'][0]['uuid'])]:
            t = table()
            mutate(t)
            with self.assertRaises(ValueError):
                plan(t, '128GiB')
        t = table()
        for text in [dump(t).replace('name="super"', 'name="wrong"'),
                     dump(t).replace('start= 6,', 'start= 7,'),
                     dump(t).replace('table-length: 32', 'table-length: 16')]:
            with self.assertRaises(ValueError):
                plan(t, '128GiB', text)
        for size in ['16GiB', '500GiB', '100%', '0%', 'existing']:
            with self.assertRaises(ValueError):
                plan(t, size)


if __name__ == '__main__':
    unittest.main()
