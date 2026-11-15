// SPDX-License-Identifier: GPL-2.0-only
//! Independent EFI storage authority. A context is never sufficient by itself.
use alloc::vec::Vec;
pub type Result<T> = core::result::Result<T, &'static str>;
pub trait ReadDisk {
    fn read(&mut self, lba: u64, out: &mut [u8]) -> Result<()>;
}
fn check(b: bool, e: &'static str) -> Result<()> {
    if b {
        Ok(())
    } else {
        Err(e)
    }
}
fn u32at(b: &[u8], n: usize) -> u32 {
    u32::from_le_bytes(b[n..n + 4].try_into().unwrap())
}
fn u64at(b: &[u8], n: usize) -> u64 {
    u64::from_le_bytes(b[n..n + 8].try_into().unwrap())
}
fn crc(b: &[u8], zero: core::ops::Range<usize>) -> u32 {
    let mut c = !0u32;
    for (i, v) in b.iter().enumerate() {
        c ^= if zero.contains(&i) { 0 } else { *v as u32 };
        for _ in 0..8 {
            c = (c >> 1) ^ (0xedb88320u32.wrapping_mul(c & 1));
        }
    }
    !c
}
fn buffer(n: usize) -> Result<Vec<u8>> {
    let mut b = Vec::new();
    b.try_reserve_exact(n).map_err(|_| "allocation")?;
    b.resize(n, 0);
    Ok(b)
}
pub use crate::context::{decode as context, Context};

struct Header {
    first: u64,
    last: u64,
    entries: u64,
    count: usize,
    size: usize,
    sum: u32,
    guid: [u8; 16],
}
fn header(b: &[u8], at: u64, other: u64, last: u64) -> Result<Header> {
    check(
        &b[..8] == b"EFI PART" && u32at(b, 8) == 0x10000 && u32at(b, 12) == 92 && u32at(b, 20) == 0,
        "GPT header",
    )?;
    check(
        u32at(b, 16) == crc(&b[..92], 16..20) && b[92..].iter().all(|x| *x == 0),
        "GPT header CRC/reserved",
    )?;
    check(u64at(b, 24) == at && u64at(b, 32) == other, "GPT location")?;
    let h = Header {
        first: u64at(b, 40),
        last: u64at(b, 48),
        entries: u64at(b, 72),
        count: u32at(b, 80) as usize,
        size: u32at(b, 84) as usize,
        sum: u32at(b, 88),
        guid: b[56..72].try_into().unwrap(),
    };
    check(
        h.first >= 2
            && h.first <= h.last
            && h.last < last
            && h.guid.iter().any(|x| *x != 0)
            && (1..=1024).contains(&h.count)
            && h.size == 128,
        "GPT bounds",
    )?;
    Ok(h)
}
fn table(
    d: &mut impl ReadDisk,
    h: &Header,
    block: usize,
    last: u64,
    primary: bool,
) -> Result<Vec<u8>> {
    let n = h.count * h.size;
    let bytes = n.div_ceil(block) * block;
    let end = h
        .entries
        .checked_add((bytes / block) as u64)
        .ok_or("GPT overflow")?;
    check(
        if primary {
            h.entries >= 2 && end <= h.first
        } else {
            h.entries > h.last && end <= last
        },
        "GPT table location",
    )?;
    let mut b = buffer(bytes)?;
    d.read(h.entries, &mut b)?;
    check(crc(&b[..n], 0..0) == h.sum, "GPT table CRC")?;
    b.truncate(n);
    Ok(b)
}
pub fn verify(d: &mut impl ReadDisk, b: &[u8], block: usize, last: u64) -> Result<()> {
    check(
        verify_member(d, b, block, last, &mut Vec::new())?,
        "boot names missing",
    )
}
pub trait DiskGroup {
    type Disk: ReadDisk;
    fn select(&mut self, index: usize) -> Result<(Self::Disk, usize, u64)>;
}
pub fn inspect_group(g: &mut impl DiskGroup, b: &[u8], count: usize) -> Result<Target> {
    context(b)?; // Validate intent before any transport operation.
    check((1..=8).contains(&count), "group bound")?;
    let mut identities = Vec::new();
    let mut target = None;
    for index in 0..count {
        let (mut disk, block, last) = g.select(index)?;
        if let Some(mut t) = inspect_member(&mut disk, b, block, last, &mut identities)? {
            check(target.is_none(), "ambiguous boot LUN")?;
            t.index = index;
            target = Some(t);
        }
    }
    target.ok_or("missing boot LUN")
}
fn inspect_member(
    d: &mut impl ReadDisk,
    b: &[u8],
    block: usize,
    last: u64,
    identities: &mut Vec<[u8; 16]>,
) -> Result<Option<Target>> {
    let c = context(b)?;
    check(matches!(block, 512 | 4096) && last >= 2, "disk geometry")?;
    let mut buf = buffer(block)?;
    d.read(1, &mut buf)?;
    if &buf[..8] != b"EFI PART" {
        // Ordinary UFS firmware LUNs may be raw. A surviving backup GPT
        // signature means corruption, not permission to ignore that disk.
        d.read(last, &mut buf)?;
        check(&buf[..8] != b"EFI PART", "damaged primary GPT")?;
        return Ok(None);
    }
    check(last > 128, "GPT geometry")?;
    let a = header(&buf, 1, last, last)?;
    d.read(last, &mut buf)?;
    let z = header(&buf, last, 1, last)?;
    check(
        a.first == z.first
            && a.last == z.last
            && a.guid == z.guid
            && a.count == z.count
            && a.size == z.size
            && a.sum == z.sum,
        "GPT copies",
    )?;
    check(!identities.contains(&a.guid), "duplicate disk GUID")?;
    identities
        .try_reserve(1 + a.count)
        .map_err(|_| "allocation")?;
    identities.push(a.guid);
    let entries = table(d, &a, block, last, true)?;
    check(
        entries == table(d, &z, block, last, false)?,
        "GPT table copies",
    )?;
    let mut slots = [None, None];
    let mut ranges = Vec::new();
    ranges
        .try_reserve_exact(a.count)
        .map_err(|_| "allocation")?;
    for e in entries.as_chunks::<128>().0 {
        if e[..16].iter().all(|x| *x == 0) {
            check(e.iter().all(|x| *x == 0), "unused GPT entry")?;
            continue;
        }
        let first = u64at(e, 32);
        let end = u64at(e, 40);
        check(
            first >= a.first && end <= a.last && first <= end && e[16..32].iter().any(|x| *x != 0),
            "partition bounds/GUID",
        )?;
        for (lo, hi, g) in &ranges {
            check(end < *lo || first > *hi, "overlapping partitions")?;
            check(&e[16..32] != g, "duplicate PARTUUID")?;
        }
        let guid = <[u8; 16]>::try_from(&e[16..32]).unwrap();
        check(!identities.contains(&guid), "duplicate group GUID")?;
        identities.push(guid);
        ranges.push((first, end, guid));
        let mut name = [0u16; 36];
        for (i, x) in name.iter_mut().enumerate() {
            *x = u16::from_le_bytes([e[56 + 2 * i], e[57 + 2 * i]]);
        }
        for (i, n) in [b"boot_a", b"boot_b"].iter().enumerate() {
            if name[..6].iter().copied().eq(n.iter().map(|x| *x as u16))
                && name[6..].iter().all(|x| *x == 0)
            {
                // Qualcomm swaps type GUIDs when changing slots. Only the actual
                // booted slot must carry the Android boot type; its peer must
                // still be a used, uniquely identified GPT entry.
                if i + 1 == c.slot as usize {
                    check(
                        e[..16]
                            == [
                                0x86, 0x7f, 0x11, 0x20, 0x85, 0xe9, 0x57, 0x43, 0xb9, 0xee, 0x37,
                                0x4b, 0xc1, 0xd8, 0x48, 0x7d,
                            ],
                        "boot partition type",
                    )?;
                }
                check(slots[i].is_none(), "duplicate boot name")?;
                slots[i] = Some((first, end, u64at(e, 48), guid));
            }
        }
    }
    if slots == [None, None] {
        return Ok(None);
    }
    let sa = slots[0].ok_or("boot_a missing")?;
    let sb = slots[1].ok_or("boot_b missing")?;
    let selected = if c.slot == 1 { sa } else { sb };
    let other = if c.slot == 1 { sb } else { sa };
    // Qualcomm A/B active bit (bit 50, not GPT legacy BIOS bit 2); require exactly the actual booted slot active.
    check(
        selected.2 & (1 << 50) != 0 && other.2 & (1 << 50) == 0,
        "active slot disagrees",
    )?;
    let bytes = (selected.1 - selected.0 + 1)
        .checked_mul(block as u64)
        .ok_or("partition overflow")?;
    check(
        (20480..=256 * 1024 * 1024).contains(&bytes) && bytes % 4096 == 0,
        "partition size",
    )?;
    let mut image = buffer(bytes as usize)?;
    d.read(selected.0, &mut image)?;
    // Re-read both GPT metadata regions after the expensive image verification.
    d.read(1, &mut buf)?;
    let now = header(&buf, 1, last, last)?;
    check(
        now.guid == a.guid
            && now.sum == a.sum
            && now.entries == a.entries
            && now.first == a.first
            && now.last == a.last
            && now.count == a.count,
        "media changed",
    )?;
    check(
        entries == table(d, &now, block, last, true)?,
        "media changed",
    )?;
    d.read(last, &mut buf)?;
    let now = header(&buf, last, 1, last)?;
    check(
        now.guid == z.guid
            && now.sum == z.sum
            && now.entries == z.entries
            && now.first == z.first
            && now.last == z.last
            && now.count == z.count,
        "media changed",
    )?;
    check(
        entries == table(d, &now, block, last, false)?,
        "media changed",
    )?;
    Ok(Some(Target {
        index: 0,
        block,
        lba: selected.0,
        disk_guid: a.guid,
        part_guid: selected.3,
        image,
    }))
}
pub struct Target {
    pub index: usize,
    pub block: usize,
    pub lba: u64,
    pub disk_guid: [u8; 16],
    pub part_guid: [u8; 16],
    pub image: Vec<u8>,
}
impl Target {
    pub fn verify(&self, b: &[u8]) -> Result<()> {
        let c = context(b)?;
        let v = crate::owned::Image::verify(&self.image)?;
        check(
            v.layout_flag == 3
                && v.generation == c.generation
                && v.sequence == c.sequence
                && v.mode == c.stored,
            "owned observation mismatch",
        )
    }
}
pub fn verify_group(g: &mut impl DiskGroup, b: &[u8], count: usize) -> Result<()> {
    inspect_group(g, b, count)?.verify(b)
}
pub fn verify_member(
    d: &mut impl ReadDisk,
    b: &[u8],
    block: usize,
    last: u64,
    identities: &mut Vec<[u8; 16]>,
) -> Result<bool> {
    if let Some(t) = inspect_member(d, b, block, last, identities)? {
        t.verify(b)?;
        Ok(true)
    } else {
        Ok(false)
    }
}
pub fn refreshed(b: &[u8], sequence: u64, mode: u32) -> [u8; 96] {
    let mut out = [0; 96];
    out.copy_from_slice(b);
    out[64..72].copy_from_slice(&sequence.to_le_bytes());
    out[72..76].copy_from_slice(&mode.to_le_bytes());
    out[76..80].copy_from_slice(&mode.to_le_bytes());
    out[80..84].fill(0);
    let sum = crc(&out[16..], 76..80);
    out[92..].copy_from_slice(&sum.to_le_bytes());
    out
}
#[cfg(test)]
mod tests {
    use super::*;
    fn token() -> [u8; 96] {
        let mut b = [0; 96];
        for (n, v) in [
            (0, 1u32),
            (4, 96),
            (8, 1),
            (24, 1),
            (28, 80),
            (64, 7),
            (72, 1),
            (76, 1),
            (84, 2),
            (88, 1),
        ] {
            b[n..n + 4].copy_from_slice(&v.to_le_bytes());
        }
        b[16..24].copy_from_slice(b"BCINTENT");
        b[32..64].fill(3);
        let sum = crc(&b[16..], 76..80);
        b[92..].copy_from_slice(&sum.to_le_bytes());
        b
    }
    #[test]
    fn strict_context() {
        let b = token();
        assert_eq!(context(&b).unwrap().slot, 2);
        for i in 0..96 {
            let mut x = b;
            x[i] ^= 1;
            assert!(context(&x).is_err(), "byte {i}");
        }
    }
    #[test]
    fn changes_refused_before_io() {
        struct NoIo;
        impl ReadDisk for NoIo {
            fn read(&mut self, _: u64, _: &mut [u8]) -> Result<()> {
                panic!("must not read")
            }
        }
        let mut b = token();
        b[76..80].fill(0);
        b[80..84].copy_from_slice(&2u32.to_le_bytes());
        let sum = crc(&b[16..], 76..80);
        b[92..].copy_from_slice(&sum.to_le_bytes());
        assert!(verify(&mut NoIo, &b, 512, 1000).is_err());
    }
    #[test]
    fn header_corruption() {
        let mut b = [0; 512];
        b[..8].copy_from_slice(b"EFI PART");
        assert!(header(&b, 1, 1000, 1000).is_err());
    }
}
#[cfg(test)]
mod disk_tests {
    use super::*;
    #[derive(Clone)]
    struct Mock {
        b: Vec<u8>,
        fail: bool,
    }
    impl ReadDisk for Mock {
        fn read(&mut self, lba: u64, out: &mut [u8]) -> Result<()> {
            if self.fail {
                return Err("media changed");
            }
            let at = lba as usize * 512;
            let end = at.checked_add(out.len()).ok_or("overflow")?;
            out.copy_from_slice(self.b.get(at..end).ok_or("bounds")?);
            Ok(())
        }
    }
    fn p32(b: &mut [u8], n: usize, v: u32) {
        b[n..n + 4].copy_from_slice(&v.to_le_bytes());
    }
    fn p64(b: &mut [u8], n: usize, v: u64) {
        b[n..n + 8].copy_from_slice(&v.to_le_bytes());
    }
    fn fixture(image: &[u8]) -> (Mock, [u8; 96], u64) {
        let sectors = image.len() / 512;
        let last = (2 * sectors + 255) as u64;
        let mut b = vec![0; (last as usize + 1) * 512];
        let mut e = [0u8; 512];
        for i in 0..2 {
            let e = &mut e[i * 128..(i + 1) * 128];
            e[..16].copy_from_slice(&[
                0x86, 0x7f, 0x11, 0x20, 0x85, 0xe9, 0x57, 0x43, 0xb9, 0xee, 0x37, 0x4b, 0xc1, 0xd8,
                0x48, 0x7d,
            ]);
            e[16] = i as u8 + 1;
            p64(e, 32, (64 + i * sectors) as u64);
            p64(e, 40, (63 + (i + 1) * sectors) as u64);
            p64(e, 48, if i == 1 { 1 << 50 } else { 0 });
            for (j, c) in (if i == 0 { b"boot_a" } else { b"boot_b" })
                .iter()
                .enumerate()
            {
                e[56 + 2 * j] = *c;
            }
        }
        b[1024..1536].copy_from_slice(&e);
        b[(last as usize - 1) * 512..last as usize * 512].copy_from_slice(&e);
        for (at, other, array) in [(1, last, 2), (last, 1, last - 1)] {
            let h = &mut b[at as usize * 512..(at as usize + 1) * 512];
            h[..8].copy_from_slice(b"EFI PART");
            p32(h, 8, 0x10000);
            p32(h, 12, 92);
            p64(h, 24, at);
            p64(h, 32, other);
            p64(h, 40, 64);
            p64(h, 48, last - 2);
            h[56] = 9;
            p64(h, 72, array);
            p32(h, 80, 4);
            p32(h, 84, 128);
            p32(h, 88, crc(&e, 0..0));
            p32(h, 16, crc(&h[..92], 16..20));
        }
        b[(64 + sectors) * 512..(64 + 2 * sectors) * 512].copy_from_slice(image);
        let owned = crate::owned::Image::verify(image).unwrap();
        let mut t = [0u8; 96];
        for (n, v) in [
            (0, 1),
            (4, 96),
            (8, 1),
            (24, 1),
            (28, 80),
            (72, 1),
            (76, 1),
            (84, 2),
            (88, 1),
        ] {
            p32(&mut t, n, v);
        }
        t[16..24].copy_from_slice(b"BCINTENT");
        t[32..64].copy_from_slice(&owned.generation);
        p64(&mut t, 64, owned.sequence);
        let sum = crc(&t[16..], 76..80);
        p32(&mut t, 92, sum);
        (Mock { b, fail: false }, t, last)
    }
    #[test]
    #[ignore = "optional host EFI fixture export via BOOT_CHOICE_TEST_EXPORT"]
    fn export_efi_fixture() {
        let Some(path) = std::env::var_os("BOOT_CHOICE_TEST_EXPORT") else {
            return;
        };
        let image = std::fs::read(std::env::var("BOOT_CHOICE_IMAGE").unwrap()).unwrap();
        let (d, t, _) = fixture(&image);
        let dir = std::path::Path::new(&path);
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("disk.bin"), &d.b).unwrap();
        std::fs::write(dir.join("context.bin"), t).unwrap();
        std::fs::write(dir.join("image.bin"), &image).unwrap();
    }
    fn rewrite(d: &mut Mock, last: u64, mut entries: Vec<u8>, identity: u8, names: bool) {
        for i in 0..2 {
            entries[i * 128 + 16] += identity;
            if names {
                entries[i * 128 + 56] = b'x';
            }
        }
        d.b[1024..1536].copy_from_slice(&entries);
        d.b[(last as usize - 1) * 512..last as usize * 512].copy_from_slice(&entries);
        for lba in [1, last] {
            let h = &mut d.b[lba as usize * 512..(lba as usize + 1) * 512];
            h[56] += identity;
            p32(h, 88, crc(&entries, 0..0));
            p32(h, 16, crc(&h[..92], 16..20));
        }
    }
    struct Group(Vec<(Mock, u64)>);
    impl DiskGroup for Group {
        type Disk = Mock;
        fn select(&mut self, i: usize) -> Result<(Mock, usize, u64)> {
            let (d, last) = &self.0[i];
            Ok((d.clone(), 512, *last))
        }
    }
    #[test]
    #[ignore = "optional real owned flag-3 fixture via BOOT_CHOICE_IMAGE"]
    fn sibling_lun_authority() {
        let image = std::fs::read(std::env::var("BOOT_CHOICE_IMAGE").unwrap()).unwrap();
        let (boot, t, last) = fixture(&image);
        let mut esp = boot.clone();
        let entries = esp.b[1024..1536].to_vec();
        rewrite(&mut esp, last, entries, 20, true);
        assert_eq!(
            verify_group(
                &mut Group(vec![(esp.clone(), last), (boot.clone(), last)]),
                &t,
                2
            ),
            Ok(())
        );
        assert_eq!(
            verify_group(&mut Group(vec![(boot.clone(), last)]), &t, 1),
            Ok(())
        );
        let raw = Mock {
            b: vec![0; 130 * 512],
            fail: false,
        };
        assert_eq!(
            verify_group(&mut Group(vec![(raw, 129), (boot.clone(), last)]), &t, 2),
            Ok(())
        );
        // Duplicate identities, duplicate boot names even with distinct GUIDs,
        // missing names, failed reads and stale geometry all refuse.
        assert!(verify_group(
            &mut Group(vec![(boot.clone(), last), (boot.clone(), last)]),
            &t,
            2
        )
        .is_err());
        let mut second = boot.clone();
        let entries = second.b[1024..1536].to_vec();
        rewrite(&mut second, last, entries, 30, false);
        assert!(verify_group(
            &mut Group(vec![(boot.clone(), last), (second, last)]),
            &t,
            2
        )
        .is_err());
        assert!(verify_group(&mut Group(vec![(esp.clone(), last)]), &t, 1).is_err());
        esp.fail = true;
        assert!(verify_group(&mut Group(vec![(esp, last), (boot.clone(), last)]), &t, 2).is_err());
        assert!(verify_group(&mut Group(vec![(boot, last - 1)]), &t, 1).is_err());
    }
    #[test]
    #[ignore = "optional real owned flag-3 fixture via BOOT_CHOICE_IMAGE"]
    fn real_owned_authority_and_faults() {
        let image = std::fs::read(std::env::var("BOOT_CHOICE_IMAGE").unwrap()).unwrap();
        let (mut d, t, last) = fixture(&image);
        assert_eq!(verify(&mut d, &t, 512, last), Ok(()));
        for at in [
            512 + 16,
            1024 + 16,
            (last as usize) * 512 + 16,
            (64 + image.len() / 512) * 512 + 5000,
        ] {
            d.b[at] ^= 1;
            assert!(verify(&mut d, &t, 512, last).is_err());
            d.b[at] ^= 1;
        }
        // Hash-valid GPT faults must still fail independent authority.
        let original = d.b[1024..1536].to_vec();
        for at in [16, 56 + 10, 128 + 48 + 6, 128, 128 + 32] {
            let mut entries = original.clone();
            if at == 16 {
                entries[144] = entries[16];
            } else if at == 66 {
                entries[128 + 66] = b'a';
            } else {
                entries[at] ^= if at == 182 { 4 } else { 1 };
            }
            d.b[1024..1536].copy_from_slice(&entries);
            d.b[(last as usize - 1) * 512..last as usize * 512].copy_from_slice(&entries);
            for lba in [1, last] {
                let h = &mut d.b[lba as usize * 512..(lba as usize + 1) * 512];
                p32(h, 88, crc(&entries, 0..0));
                p32(h, 16, crc(&h[..92], 16..20));
            }
            assert!(verify(&mut d, &t, 512, last).is_err(), "GPT fault {at}");
        }
        d.b[1024..1536].copy_from_slice(&original);
        d.b[(last as usize - 1) * 512..last as usize * 512].copy_from_slice(&original);
        for lba in [1, last] {
            let h = &mut d.b[lba as usize * 512..(lba as usize + 1) * 512];
            p32(h, 88, crc(&original, 0..0));
            p32(h, 16, crc(&h[..92], 16..20));
        }
        d.fail = true;
        assert!(verify(&mut d, &t, 512, last).is_err());
        d.fail = false;
        for at in [32, 64] {
            let mut stale = t;
            stale[at] ^= 1;
            let sum = crc(&stale[16..], 76..80);
            p32(&mut stale, 92, sum);
            assert!(verify(&mut d, &stale, 512, last).is_err());
        }
    }
}
