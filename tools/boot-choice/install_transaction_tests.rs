// SPDX-License-Identifier: GPL-2.0-only
use super::*;
use std::collections::BTreeMap;
pub(crate) fn fixture() -> (Vec<u8>, Vec<u8>) {
    fn put(b: &mut [u8], at: usize, n: usize) {
        b[at..at + 8].copy_from_slice(&(n as u64).to_le_bytes())
    }
    let mut o = vec![0; 3 * 1024 * 1024];
    o[..8].copy_from_slice(b"ANDROID!");
    o[8..12].copy_from_slice(&8192u32.to_le_bytes());
    o[20..24].copy_from_slice(&1584u32.to_le_bytes());
    o[40..44].copy_from_slice(&4u32.to_le_bytes());
    o[4096..4098].copy_from_slice(b"MZ");
    o[4100..4104].copy_from_slice(&0x1400000fu32.to_le_bytes());
    put(&mut o, 4112, 8192);
    put(&mut o, 4120, 10);
    o[4152..4156].copy_from_slice(b"ARM\x64");
    o[5000] = 42;
    let fdt: usize = 131072;
    let archive = fdt + 2 * 1024 * 1024;
    let len = 16 + 4160;
    let meta = (archive + len).div_ceil(PAGE) * PAGE;
    let body = meta + PAGE;
    let pages = 16384;
    let payload = pages + 8192 + 65536;
    let mut b = vec![0; body];
    b[..12288].copy_from_slice(&o[..12288]);
    b[8..12].copy_from_slice(&((body - PAGE) as u32).to_le_bytes());
    put(&mut b, 4112, body - PAGE);
    b[4100..4104]
        .copy_from_slice(&(0x14000000u32 | ((pages + 8192 - PAGE - 4) / 4) as u32).to_le_bytes());
    b[pages..pages + PAGE].copy_from_slice(&crate::format::record(&[7; 32], 1, 1));
    put(&mut b, archive, 0);
    put(&mut b, archive + 8, 4160);
    b[archive + 16..archive + len].copy_from_slice(&o[..4160]);
    let m = &mut b[meta..];
    m[..8].copy_from_slice(b"OWNBOOT1");
    m[8..12].copy_from_slice(&1u32.to_le_bytes());
    m[12..16].copy_from_slice(&3u32.to_le_bytes());
    for (at, n) in [
        (16, o.len()),
        (24, body),
        (32, archive),
        (40, pages),
        (48, pages + 8192),
        (56, payload),
        (64, payload),
        (72, payload + PAGE),
        (80, payload + PAGE),
        (88, body),
        (96, archive),
        (104, len),
        (112, 12288),
        (120, 1),
        (224, fdt),
        (232, 2 * 1024 * 1024),
        (240, 1),
    ] {
        put(m, at, n)
    }
    m[128..160].copy_from_slice(&[7; 32]);
    m[160..192].copy_from_slice(&hash(&o));
    let mut norm = b.clone();
    norm[pages..pages + 8192].fill(0);
    b[meta + 192..meta + 224].copy_from_slice(&hash(&norm));
    let b = crate::avb::seal(&b, o.len()).unwrap();
    Image::verify(&b).unwrap();
    assert_eq!(Image::restore(&b).unwrap(), o);
    (o, b)
}
#[derive(Clone)]
struct Memory {
    image: Vec<u8>,
    journal: Option<Vec<u8>>,
    files: BTreeMap<String, Vec<u8>>,
    log: Vec<String>,
    fail: Option<usize>,
    writes: usize,
    rollback_fail: bool,
    short: bool,
}
impl Memory {
    fn new(image: Vec<u8>) -> Self {
        Self {
            image,
            journal: None,
            files: BTreeMap::new(),
            log: Vec::new(),
            fail: None,
            writes: 0,
            rollback_fail: false,
            short: false,
        }
    }
    fn op(&mut self, n: &str) -> Result<()> {
        self.log.push(n.into());
        if self.fail == Some(self.log.len()) {
            self.fail = None;
            return Err(format!("injected {n}"));
        }
        Ok(())
    }
}
impl Io for Memory {
    fn probe(&mut self) -> Result<()> {
        self.op("mount/probe/flush")
    }
    fn read(&mut self) -> Result<Vec<u8>> {
        self.op("readback")?;
        Ok(self.image.clone())
    }
    fn write(&mut self, at: usize, b: &[u8]) -> Result<()> {
        self.writes += 1;
        if self.rollback_fail && self.writes > 1 {
            return Err("rollback failure".into());
        }
        self.op("write")?;
        if self.short {
            self.image[at..at + 8].copy_from_slice(&b[..8]);
            self.short = false;
            return Err("short write".into());
        }
        self.image[at..at + b.len()].copy_from_slice(b);
        Ok(())
    }
    fn flush(&mut self) -> Result<()> {
        self.op("block-flush")
    }
    fn journal_read(&mut self) -> Result<Option<Vec<u8>>> {
        self.op("open-journal")?;
        Ok(self.journal.clone())
    }
    fn journal_create(&mut self, b: &[u8]) -> Result<()> {
        for p in [
            "journal-allocation",
            "journal-create",
            "journal-write",
            "journal-fsync",
            "journal-close",
            "journal-dir-sync",
            "journal-block-sync",
            "journal-reopen",
        ] {
            self.op(p)?;
        }
        self.journal = Some(b.to_vec());
        Ok(())
    }
    fn journal_remove(&mut self) -> Result<()> {
        self.op("journal-remove")?;
        self.journal = None;
        Ok(())
    }
    fn file_read(&mut self, n: &str) -> Result<Option<Vec<u8>>> {
        self.op("file-read")?;
        Ok(self.files.get(n).cloned())
    }
    fn file_replace(&mut self, n: &str, b: Option<&[u8]>, _: &str) -> Result<()> {
        self.op("file-stage")?;
        if let Some(b) = b {
            self.files.insert(n.into(), b.to_vec());
        } else {
            self.files.remove(n);
        }
        Ok(())
    }
    fn scratch_read(&mut self, _: &str, _: &str) -> Result<Option<Vec<u8>>> {
        self.op("scratch-read")?;
        Ok(None)
    }
    fn scratch_remove(&mut self, _: &str, _: &str) -> Result<()> {
        self.op("scratch-remove")
    }
}
fn identity(n: usize) -> Identity {
    Identity {
        disk: [1; 16],
        part: [2; 16],
        esp: "esp".into(),
        controller: "actual group".into(),
        lba: 100,
        block: 512,
        size: n,
        slot: 2,
    }
}
#[test]
fn full_image_faults_recovery_and_noop() {
    let (old, new) = fixture();
    let id = identity(old.len());
    let files = vec![FileChange {
        name: crate::live_fs::HELPER.into(),
        before: None,
        after: Some(b"new helper".to_vec()),
    }];
    let mut good = Memory::new(old.clone());
    execute(&mut good, &id, None, "install", &old, &new, files.clone()).unwrap();
    assert_eq!(good.image, new);
    assert!(good.journal.is_none());
    let count = good.log.len();
    for failure in 1..=count {
        let mut io = Memory::new(old.clone());
        io.fail = Some(failure);
        let result = execute(&mut io, &id, None, "install", &old, &new, files.clone());
        assert!(result.is_err(), "step {failure}");
        assert!(
            io.image == old || io.image == new || io.journal.is_some(),
            "lost undo {failure}"
        );
        if io.journal.is_some() {
            recover(&mut io, &id, None).unwrap();
            assert!(io.image == old || io.image == new);
            assert!(io.journal.is_none())
        }
    }
    let mut io = Memory::new(new.clone());
    execute(
        &mut io,
        &id,
        state(&new).as_ref(),
        "update",
        &new,
        &new,
        vec![],
    )
    .unwrap();
    assert_eq!(io.writes, 0);
    assert!(!io
        .log
        .iter()
        .any(|s| s.contains("sync") || s.contains("probe") || s == "write" || s == "block-flush"));
    let mut io = Memory::new(old.clone());
    io.short = true;
    assert!(execute(&mut io, &id, None, "install", &old, &new, files.clone()).is_err());
    assert_eq!(io.image, old);
    assert!(io.journal.is_none());
    let mut io = Memory::new(old.clone());
    io.short = true;
    io.rollback_fail = true;
    assert!(
        execute(&mut io, &id, None, "install", &old, &new, files.clone())
            .unwrap_err()
            .contains("ROLLBACK FAILED")
    );
    assert!(io.journal.is_some());
    let evidence = io.journal.clone();
    let mut foreign = id.clone();
    foreign.controller = "other".into();
    assert!(recover(&mut io, &foreign, None).is_err());
    assert_eq!(io.journal, evidence);
    io.rollback_fail = false;
    recover(&mut io, &id, None).unwrap();
    assert_eq!(io.image, old);
    // Complete image and staged files, but failed retirement: recovery preserves
    // commit rather than undoing it. Stale Linux context/foreign media still fail.
    let mut io = Memory::new(old.clone());
    io.fail = Some(count);
    assert!(execute(&mut io, &id, None, "install", &old, &new, files).is_err());
    assert_eq!(io.image, new);
    let mut stale = state(&new).unwrap();
    stale.sequence += 1;
    assert!(recover(&mut io, &id, Some(&stale)).is_err());
    recover(&mut io, &id, None).unwrap();
    assert_eq!(io.image, new);
    let before = io.files.clone();
    execute(
        &mut io,
        &id,
        state(&new).as_ref(),
        "restore",
        &new,
        &old,
        vec![],
    )
    .unwrap();
    assert_eq!(io.image, old);
    assert_eq!(io.files, before);
}
