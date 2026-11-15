// SPDX-License-Identifier: GPL-2.0-only
use super::*;
use std::io::Cursor;
struct Fake {
    bytes: Cursor<Vec<u8>>,
    steps: usize,
    fail: usize,
    persistent: bool,
    partial: bool,
    corrupt_read: usize,
}
impl Fake {
    fn new(b: Vec<u8>) -> Self {
        Self {
            bytes: Cursor::new(b),
            steps: 0,
            fail: usize::MAX,
            persistent: false,
            partial: false,
            corrupt_read: usize::MAX,
        }
    }
    fn step(&mut self) -> io::Result<()> {
        self.steps += 1;
        if self.steps == self.fail || (self.persistent && self.steps >= self.fail) {
            Err(io::Error::other("injected"))
        } else {
            Ok(())
        }
    }
}
impl Read for Fake {
    fn read(&mut self, b: &mut [u8]) -> io::Result<usize> {
        self.step()?;
        let n = self.bytes.read(b)?;
        if self.steps == self.corrupt_read && n > 0 {
            b[0] ^= 1;
        }
        Ok(n)
    }
}
impl Write for Fake {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        if self.partial && self.steps + 1 == self.fail {
            self.bytes.write_all(&b[..b.len() / 2])?;
        }
        self.step()?;
        self.bytes.write(b)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.step()
    }
}
impl Seek for Fake {
    fn seek(&mut self, p: SeekFrom) -> io::Result<u64> {
        self.step()?;
        self.bytes.seek(p)
    }
}
impl Storage for Fake {
    fn sync(&mut self) -> io::Result<()> {
        self.step()
    }
}
pub(crate) fn fixture() -> (Owned, Vec<u8>) {
    let mut body = vec![0; 24576];
    body[..8].copy_from_slice(b"ANDROID!");
    body[8..12].copy_from_slice(&20480u32.to_le_bytes());
    body[20..24].copy_from_slice(&1584u32.to_le_bytes());
    body[40..44].copy_from_slice(&4u32.to_le_bytes());
    body[4096..4098].copy_from_slice(b"MZ");
    body[4152..4156].copy_from_slice(b"ARM\x64");
    body[4112..4120].copy_from_slice(&20480u64.to_le_bytes());
    body[4120..4128].copy_from_slice(&10u64.to_le_bytes());
    let pages = 8192;
    body[4100..4104]
        .copy_from_slice(&(0x14000000u32 | ((pages + 8192 - 4096 - 4) / 4) as u32).to_le_bytes());
    let mut o = Owned {
        size: 32768,
        body: body.len(),
        pages,
        generation: [7; 32],
        immutable: hex(&hash(&body)),
    };
    // Ownership digest normalizes the pages, but includes every other byte.
    let mut normalized = body.clone();
    normalized[pages..pages + 8192].fill(0);
    o.immutable = hex(&hash(&normalized));
    body[pages..pages + 4096].copy_from_slice(&format::record(&o.generation, 1, 1));
    (o, seal(&body, 32768).unwrap())
}
#[test]
fn canonical_and_corruptions() {
    let (o, b) = fixture();
    o.verify(&b).unwrap();
    for at in [
        0,
        8,
        24,
        40,
        1580,
        4096,
        4100,
        4112,
        4152,
        20000,
        24576,
        24576 + 128,
        24576 + 392,
        32767,
    ] {
        let mut corrupt = b.clone();
        corrupt[at] ^= 1;
        assert!(o.verify(&corrupt).is_err(), "offset {at}");
    }
    let mut invalid = b.clone();
    invalid[o.pages + 60] ^= 1;
    assert!(o.prepare(&invalid, 0).is_err()); // do not repair an invalid AVB hash
    let mut short = b.clone();
    short.pop();
    assert!(o.verify(&short).is_err());
    let a = o.prepare(&b, 0).unwrap();
    let u = o.prepare(&a, 1).unwrap();
    assert_eq!(
        format::parse(&a[o.pages + 4096..o.pages + 8192], &o.generation),
        Some((2, 0))
    );
    assert_eq!(
        format::parse(&u[o.pages..o.pages + 4096], &o.generation),
        Some((3, 1))
    );
}
#[test]
fn every_target_fault_and_partial_write() {
    let (o, b) = fixture();
    let mut s = Fake::new(b.clone());
    let mut j = Fake::new(vec![]);
    transact(&mut s, &mut j, &o, 0).unwrap();
    let steps = s.steps;
    assert_eq!(s.bytes.into_inner(), o.prepare(&b, 0).unwrap());
    for fail in 1..=steps {
        for partial in [false, true] {
            let mut s = Fake::new(b.clone());
            s.fail = fail;
            s.partial = partial;
            let mut j = Fake::new(vec![]);
            let e = transact(&mut s, &mut j, &o, 0).unwrap_err();
            assert_eq!(s.bytes.into_inner(), b, "{fail} {partial} {e}");
        }
    }
    // Silent corruption in final whole-image readback must also roll back.
    let mut s = Fake::new(b.clone());
    s.corrupt_read = steps;
    let mut j = Fake::new(vec![]);
    assert!(transact(&mut s, &mut j, &o, 0)
        .unwrap_err()
        .contains("original restored"));
    assert_eq!(s.bytes.into_inner(), b);
    // An unrecoverable device is not reported as restored.
    let mut s = Fake::new(b.clone());
    s.fail = 11;
    s.persistent = true;
    let mut j = Fake::new(vec![]);
    assert!(transact(&mut s, &mut j, &o, 0)
        .unwrap_err()
        .contains("UNRECOVERED"));
    assert_eq!(j.bytes.into_inner(), b);
}
#[test]
fn every_journal_fault_precedes_target_writes() {
    let (o, b) = fixture();
    let mut s = Fake::new(b.clone());
    let mut j = Fake::new(vec![]);
    transact(&mut s, &mut j, &o, 0).unwrap();
    let steps = j.steps;
    for fail in 1..=steps {
        let mut s = Fake::new(b.clone());
        let mut j = Fake::new(vec![]);
        j.fail = fail;
        assert!(transact(&mut s, &mut j, &o, 0).is_err());
        assert_eq!(s.bytes.into_inner(), b);
    }
    let mut s = Fake::new(b.clone());
    let mut j = Fake::new(vec![1]);
    assert!(transact(&mut s, &mut j, &o, 0).is_err());
    assert_eq!(s.bytes.into_inner(), b);
}
#[test]
#[ignore = "requires exact host bundles; set BOOT_CHOICE_FIXTURES to the evidence directory"]
fn actual_host_bundles() {
    let root = std::path::PathBuf::from(std::env::var_os("BOOT_CHOICE_FIXTURES").unwrap());
    let read = |p: &str| std::fs::read(root.join(p)).unwrap();
    let c: Value = serde_json::from_slice(&read("persistent-boot4-v2/catalog.json")).unwrap();
    let original = read("persistent-boot4-v2/original.img");
    let raw = read("uboot-abi/u-boot.bin");
    let elf = read("uboot-abi/u-boot");
    let config = read("uboot-abi/.config");
    let o = Owned::from_sources(&c, &original, &raw, &elf, &config).unwrap();
    let b = read("persistent-boot4-v2/experiment.img");
    o.verify(&b).unwrap();
    let a = read("persistent-android-v2/experiment.img");
    let u = read("persistent-uboot-v2/experiment.img");
    assert_eq!(o.prepare(&b, 0).unwrap(), a);
    assert_eq!(o.prepare(&a, 1).unwrap(), u);
    assert!(o.verify(&original).is_err());
    assert!(o.verify(&read("carrier/u-boot.img")).is_err());
    let mut changed = raw.clone();
    changed[0] ^= 1;
    assert!(Owned::from_sources(&c, &original, &changed, &elf, &config).is_err());
    let mut changed = c.clone();
    changed["selector_manifest"]["binding"]["request_generation"] = Value::String("00".repeat(32));
    assert!(Owned::from_sources(&changed, &original, &raw, &elf, &config).is_err());
}

#[test]
fn changed_target_before_first_write_is_refused() {
    let (o, b) = fixture();
    let mut s = Fake::new(b.clone());
    s.corrupt_read = 6; // second whole-target read, after journal verification
    let mut j = Fake::new(vec![]);
    assert_eq!(
        transact(&mut s, &mut j, &o, 0).unwrap_err(),
        "target changed"
    );
    assert_eq!(s.bytes.into_inner(), b);
    assert_eq!(j.bytes.into_inner(), b);
}
