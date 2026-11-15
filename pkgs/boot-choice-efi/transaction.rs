// SPDX-License-Identifier: GPL-2.0-only
//! Two bounded boot regions, with an ESP undo journal. This cannot close the
//! OEM AVB rejection window before EFI gets control after interrupted writes.
use crate::{
    authority::{self, Result, Target},
    owned,
};
use alloc::vec::Vec;
use sha2::{Digest, Sha256};
const PAGE: usize = 4096;
pub const JOURNAL_SIZE: usize = 8448;
fn hash(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}
fn check(b: bool, e: &'static str) -> Result<()> {
    if b {
        Ok(())
    } else {
        Err(e)
    }
}
fn put(b: &mut [u8], at: usize, n: u64) {
    b[at..at + 8].copy_from_slice(&n.to_le_bytes());
}
fn num(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
pub trait Io {
    /// Both positively identified media must accept real synchronization before
    /// journal creation, let alone the first boot write.
    fn probe(&mut self) -> Result<()>;
    fn journal_read(&mut self) -> Result<Option<Vec<u8>>>;
    fn journal_create(&mut self, bytes: &[u8]) -> Result<()>;
    fn journal_remove(&mut self) -> Result<()>;
    fn read(&mut self, lba: u64, bytes: &mut [u8]) -> Result<()>;
    fn write(&mut self, lba: u64, bytes: &[u8]) -> Result<()>;
    fn flush(&mut self) -> Result<()>;
}
struct Plan {
    new: Vec<u8>,
    offsets: [usize; 2],
}
fn plan(old: &[u8], mode: u32) -> Result<Plan> {
    let v = owned::Image::verify(old)?;
    let new = owned::Image::request(old, &v.generation, v.sequence, mode)?;
    let mut offsets = [usize::MAX, v.body.div_ceil(PAGE) * PAGE];
    for at in [v.pages, v.pages + PAGE] {
        if old[at..at + PAGE] != new[at..at + PAGE] {
            check(offsets[0] == usize::MAX, "multiple request pages")?;
            offsets[0] = at;
        }
    }
    check(
        offsets[0] != usize::MAX && offsets[1] + PAGE <= old.len(),
        "changed regions",
    )?;
    for at in (0..old.len()).step_by(PAGE) {
        check(
            offsets.contains(&at) || old[at..at + PAGE] == new[at..at + PAGE],
            "unexpected image difference",
        )?;
    }
    check(
        old[offsets[1]..offsets[1] + PAGE] != new[offsets[1]..offsets[1] + PAGE],
        "AVB region unchanged",
    )?;
    Ok(Plan { new, offsets })
}
fn journal(t: &Target, p: &Plan) -> Result<Vec<u8>> {
    let v = owned::Image::verify(&t.image)?;
    let n = owned::Image::verify(&p.new)?;
    let mut b = alloc::vec![0;JOURNAL_SIZE];
    b[..8].copy_from_slice(b"BCUNDO01");
    b[8..12].copy_from_slice(&1u32.to_le_bytes());
    b[12..16].copy_from_slice(&(JOURNAL_SIZE as u32).to_le_bytes());
    b[16..32].copy_from_slice(&t.disk_guid);
    b[32..48].copy_from_slice(&t.part_guid);
    put(&mut b, 48, t.lba);
    put(&mut b, 56, t.image.len() as u64);
    put(&mut b, 64, t.block as u64);
    b[72..104].copy_from_slice(&v.generation);
    put(&mut b, 104, v.sequence);
    put(&mut b, 112, n.sequence);
    for (i, at) in p.offsets.iter().enumerate() {
        put(&mut b, 120 + i * 8, *at as u64);
        b[224 + i * PAGE..224 + (i + 1) * PAGE].copy_from_slice(&t.image[*at..*at + PAGE]);
    }
    b[136..168].copy_from_slice(&hash(&t.image));
    b[168..200].copy_from_slice(&hash(&p.new));
    b[200..204].copy_from_slice(&n.mode.to_le_bytes());
    b[204..208].copy_from_slice(&v.mode.to_le_bytes());
    let sum = hash(&b[..JOURNAL_SIZE - 32]);
    b[JOURNAL_SIZE - 32..].copy_from_slice(&sum);
    Ok(b)
}
fn readback(io: &mut impl Io, t: &Target, expected: &[u8]) -> Result<()> {
    let mut b = alloc::vec![0;expected.len()];
    io.read(t.lba, &mut b)?;
    check(hash(&b) == hash(expected), "boot readback mismatch")?;
    owned::Image::verify(&b)?;
    Ok(())
}
fn pages(io: &mut impl Io, t: &Target, image: &[u8], offsets: [usize; 2]) -> Result<()> {
    for at in offsets {
        check(
            at.is_multiple_of(t.block) && PAGE.is_multiple_of(t.block),
            "write alignment",
        )?;
        io.write(t.lba + (at / t.block) as u64, &image[at..at + PAGE])?;
        io.flush()?;
    }
    readback(io, t, image)
}
/// Recover only the exact bound transaction. Foreign/stale/invalid evidence is
/// never deleted. A verified completed new choice is never rolled back.
fn recover(io: &mut impl Io, t: &mut Target, ctx: &mut [u8; 96], b: &[u8]) -> Result<()> {
    check(b.len() == JOURNAL_SIZE, "journal size")?;
    check(
        &b[..8] == b"BCUNDO01"
            && b[8..12] == 1u32.to_le_bytes()
            && b[12..16] == (JOURNAL_SIZE as u32).to_le_bytes()
            && b[208..224].iter().all(|x| *x == 0)
            && b[JOURNAL_SIZE - 32..] == hash(&b[..JOURNAL_SIZE - 32]),
        "journal integrity",
    )?;
    let c = authority::context(ctx)?;
    check(
        b[16..32] == t.disk_guid
            && b[32..48] == t.part_guid
            && num(b, 48) == t.lba
            && num(b, 56) == t.image.len() as u64
            && num(b, 64) == t.block as u64
            && b[72..104] == c.generation,
        "journal target",
    )?;
    let mut old = t.image.clone();
    let offsets = [
        usize::try_from(num(b, 120)).map_err(|_| "journal offset")?,
        usize::try_from(num(b, 128)).map_err(|_| "journal offset")?,
    ];
    for (i, at) in offsets.iter().copied().enumerate() {
        check(
            at.is_multiple_of(PAGE) && at <= old.len() - PAGE,
            "journal offset",
        )?;
        old[at..at + PAGE].copy_from_slice(&b[224 + i * PAGE..224 + (i + 1) * PAGE]);
    }
    check(hash(&old) == b[136..168], "journal old image")?;
    let v = owned::Image::verify(&old)?;
    let mode = u32::from_le_bytes(b[200..204].try_into().unwrap());
    let p = plan(&old, mode)?;
    let n = owned::Image::verify(&p.new)?;
    check(
        p.offsets == offsets
            && hash(&p.new) == b[168..200]
            && v.sequence == num(b, 104)
            && n.sequence == num(b, 112)
            && v.generation == c.generation
            && b[204..208] == v.mode.to_le_bytes()
            && ((c.sequence == v.sequence && c.stored == v.mode)
                || (c.sequence == n.sequence && c.stored == n.mode)),
        "stale journal/context",
    )?;
    io.probe()?;
    if hash(&t.image) == hash(&p.new) {
        t.image = p.new;
        *ctx = authority::refreshed(ctx, n.sequence, n.mode);
    } else {
        // A torn region may be arbitrary, but all other bytes must match the
        // canonical old image (proved by reconstruction and full digest above).
        if hash(&t.image) != hash(&old) {
            pages(io, t, &old, offsets)?;
        }
        t.image = old;
        *ctx = authority::refreshed(ctx, v.sequence, v.mode);
    }
    io.journal_remove()
}
/// Native full-image operations must settle an interrupted preference without
/// issuing a new selection that could reverse a previously committed choice.
pub fn recover_pending(io: &mut impl Io, t: &mut Target, ctx: &mut [u8; 96]) -> Result<()> {
    if let Some(bytes) = io.journal_read()? { recover(io, t, ctx, &bytes)?; }
    Ok(())
}
/// Returns the desired mode. The adapter publishes ctx before any chainload.
/// Reset is a later effect: a returning ResetSystem must not undo this commit.
pub fn execute(
    io: &mut impl Io,
    t: &mut Target,
    ctx: &mut [u8; 96],
    manual_android: bool,
) -> Result<u32> {
    let observation = authority::context(ctx)?;
    if observation.read_only && !manual_android {
        // Early menu overrides only this boot. Do not recover, probe, sync,
        // retire a journal or turn selected!=stored into a preference write.
        check(io.journal_read()?.is_none(), "pending journal blocks read-only boot")?;
        t.verify(ctx)?;
        return Ok(1);
    }
    let requested = if manual_android {
        0
    } else {
        authority::context(ctx)?.selected
    };
    if let Some(b) = io.journal_read()? {
        recover(io, t, ctx, &b)?;
    }
    t.verify(ctx)?;
    let v = owned::Image::verify(&t.image)?;
    if v.mode == requested {
        return Ok(requested);
    }
    let p = plan(&t.image, requested)?;
    let b = journal(t, &p)?;
    io.probe()?;
    io.journal_create(&b)?;
    check(
        io.journal_read()?.as_deref() == Some(b.as_slice()),
        "journal readback",
    )?;
    if pages(io, t, &p.new, p.offsets).is_err() {
        if pages(io, t, &t.image, p.offsets).is_err() {
            return Err("rollback failed; journal retained");
        }
        io.journal_remove()?;
        return Err("boot write failed; rolled back");
    }
    let n = owned::Image::verify(&p.new)?;
    // Successful new bytes stay committed even if journal retirement fails.
    *ctx = authority::refreshed(ctx, n.sequence, n.mode);
    t.image = p.new;
    io.journal_remove()?;
    Ok(requested)
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Memory {
        disk: Vec<u8>,
        journal: Option<Vec<u8>>,
        log: Vec<&'static str>,
        fail: Option<usize>,
        corrupt: bool,
        rollback_fail: bool,
        block: usize,
    }
    impl Memory {
        fn op(&mut self, s: &'static str) -> Result<()> {
            self.log.push(s);
            if self.fail == Some(self.log.len()) {
                Err("injected")
            } else {
                Ok(())
            }
        }
    }
    impl Io for Memory {
        fn probe(&mut self) -> Result<()> {
            self.op("probe")
        }
        fn journal_read(&mut self) -> Result<Option<Vec<u8>>> {
            self.op("journal_read")?;
            Ok(self.journal.clone())
        }
        fn journal_create(&mut self, b: &[u8]) -> Result<()> {
            self.op("journal_create")?;
            self.journal = Some(b.to_vec());
            Ok(())
        }
        fn journal_remove(&mut self) -> Result<()> {
            self.op("journal_remove")?;
            self.journal = None;
            Ok(())
        }
        fn read(&mut self, _: u64, b: &mut [u8]) -> Result<()> {
            self.op("readback")?;
            b.copy_from_slice(&self.disk);
            Ok(())
        }
        fn write(&mut self, lba: u64, b: &[u8]) -> Result<()> {
            self.op("write")?;
            if self.rollback_fail && self.log.iter().filter(|x| **x == "write").count() > 2 {
                return Err("rollback write");
            }
            let at = (lba - 100) as usize * self.block;
            self.disk[at..at + b.len()].copy_from_slice(b);
            if self.corrupt {
                self.disk[at] ^= 1;
            }
            Ok(())
        }
        fn flush(&mut self) -> Result<()> {
            self.op("flush")
        }
    }
    fn fixture() -> (Target, [u8; 96], Memory) {
        let image = std::fs::read(std::env::var("BOOT_CHOICE_IMAGE").unwrap()).unwrap();
        let v = owned::Image::verify(&image).unwrap();
        let mut c = [0u8; 96];
        for (at, n) in [
            (0, 1u32),
            (4, 96),
            (8, 1),
            (24, 1),
            (28, 80),
            (84, 1),
            (88, 1),
        ] {
            c[at..at + 4].copy_from_slice(&n.to_le_bytes());
        }
        c[16..24].copy_from_slice(b"BCINTENT");
        c[32..64].copy_from_slice(&v.generation);
        c = authority::refreshed(&c, v.sequence, v.mode);
        let t = Target {
            index: 0,
            block: 512,
            lba: 100,
            disk_guid: [1; 16],
            part_guid: [2; 16],
            image: image.clone(),
        };
        let io = Memory {
            disk: image,
            journal: None,
            log: Vec::new(),
            fail: None,
            corrupt: false,
            rollback_fail: false,
            block: 512,
        };
        (t, c, io)
    }
    #[test]
    #[ignore = "real flag-3 image via BOOT_CHOICE_IMAGE"]
    fn readonly_early_override_never_mutates() {
        for stored in [0,1] {
            let (mut t, mut c, mut io) = fixture();
            if stored == 0 {
                let current = owned::Image::verify(&t.image).unwrap();
                t.image = owned::Image::request(&t.image, &current.generation, current.sequence, 0).unwrap();
                io.disk = t.image.clone();
            }
            let v = owned::Image::verify(&t.image).unwrap();
            c = authority::refreshed(&c, v.sequence, v.mode);
            c[76..80].copy_from_slice(&1u32.to_le_bytes());
            c[80..84].copy_from_slice(&2u32.to_le_bytes());
            let sum=crc_for_test(&c[16..]);c[92..].copy_from_slice(&sum.to_le_bytes());
            let before=c;let image=t.image.clone();
            assert_eq!(execute(&mut io,&mut t,&mut c,false),Ok(1));
            assert_eq!(io.log,vec!["journal_read"]);
            assert_eq!(c,before);assert_eq!(t.image,image);assert_eq!(io.disk,image);
            io.log.clear();io.journal=Some(vec![1]);
            assert!(execute(&mut io,&mut t,&mut c,false).is_err());
            assert_eq!(io.log,vec!["journal_read"]);assert_eq!(io.journal,Some(vec![1]));
            io.journal=None;io.log.clear();
            // Deliberate systemd-boot Android action remains a separate writer.
            assert_eq!(execute(&mut io,&mut t,&mut c,true),Ok(0));
            assert_eq!(owned::Image::verify(&t.image).unwrap().mode,0);
        }
    }
    #[test]
    #[ignore = "real flag-3 image via BOOT_CHOICE_IMAGE"]
    fn transaction_fault_matrix_and_context_refresh() {
        let (mut t, mut c, mut io) = fixture();
        let original = c;
        let v = owned::Image::verify(&t.image).unwrap();
        assert_eq!(v.mode, 1);
        assert_eq!(execute(&mut io, &mut t, &mut c, false), Ok(1));
        assert_eq!(io.log, vec!["journal_read"]);
        io.log.clear();
        assert_eq!(execute(&mut io, &mut t, &mut c, true), Ok(0));
        assert!(io.journal.is_none());
        assert_eq!(io.log.iter().filter(|x| **x == "write").count(), 2);
        assert!(t.verify(&original).is_err());
        assert!(t.verify(&c).is_ok());
        // Changed Up -> fresh context -> manual Android is a legitimate next
        // transaction; replay of either earlier token does not gain authority.
        let android = c;
        c[76..80].copy_from_slice(&1u32.to_le_bytes());
        c[80..84].copy_from_slice(&1u32.to_le_bytes());
        // Recalculate using a refresh followed by intent's own CRC helper.
        let sum = crc_for_test(&c[16..]);
        c[92..96].copy_from_slice(&sum.to_le_bytes());
        assert_eq!(execute(&mut io, &mut t, &mut c, false), Ok(1));
        assert_eq!(authority::context(&c).unwrap().sequence, v.sequence + 2);
        assert!(t.verify(&android).is_err());
        assert_eq!(execute(&mut io, &mut t, &mut c, true), Ok(0));
        assert_eq!(authority::context(&c).unwrap().sequence, v.sequence + 3);
        let (t, c, _) = fixture();
        let p = plan(&t.image, 0).unwrap();
        let j = journal(&t, &p).unwrap();
        // One injected error at each actual adapter operation of the success path.
        for step in 1..=10 {
            eprintln!("transaction fault {step}/10");
            let (mut target, mut ctx, mut mem) = fixture();
            mem.fail = Some(step);
            assert!(
                execute(&mut mem, &mut target, &mut ctx, true).is_err(),
                "step {step}"
            );
            assert!(
                mem.disk == t.image || mem.disk == p.new,
                "not canonical after recoverable failure {step}"
            );
            if step <= 4 {
                assert!(!mem.log.contains(&"write"));
            }
        }
        // Interrupted before either, between regions, and after commit.
        for done in 0..=2 {
            eprintln!("journal recovery {done}/2");
            let (mut target, mut ctx, mut mem) = fixture();
            mem.journal = Some(j.clone());
            for at in p.offsets.iter().take(done) {
                mem.disk[*at..*at + PAGE].copy_from_slice(&p.new[*at..*at + PAGE]);
            }
            target.image = mem.disk.clone();
            assert_eq!(execute(&mut mem, &mut target, &mut ctx, false), Ok(1));
            assert!(mem.journal.is_none());
            target.verify(&ctx).unwrap();
        }
        // Foreign evidence, silent corruption and persistent rollback failures.
        let (mut target, mut ctx, mut mem) = fixture();
        let mut bad = j.clone();
        bad[16] ^= 1;
        mem.journal = Some(bad);
        assert!(execute(&mut mem, &mut target, &mut ctx, true).is_err());
        assert!(!mem.log.contains(&"write"));
        assert!(mem.journal.is_some());
        let (mut target, mut ctx, mut mem) = fixture();
        mem.corrupt = true;
        assert_eq!(
            execute(&mut mem, &mut target, &mut ctx, true),
            Err("rollback failed; journal retained")
        );
        assert!(mem.journal.is_some());
        let (mut target, mut ctx, mut mem) = fixture();
        mem.fail = Some(8);
        mem.rollback_fail = true;
        assert!(execute(&mut mem, &mut target, &mut ctx, true).is_err());
        assert!(mem.journal.is_some());
        // The same two pages work with a native 4 KiB BlockIO medium.
        let (mut target, mut ctx, mut mem) = fixture();
        target.block = 4096;
        mem.block = 4096;
        assert_eq!(execute(&mut mem, &mut target, &mut ctx, true), Ok(0));
        assert_eq!(mem.log.iter().filter(|x| **x == "write").count(), 2);
        // A no-op at exhausted sequence is still a no-op, not an overflow.
        let (mut target, mut ctx, mut mem) = fixture();
        let v = owned::Image::verify(&target.image).unwrap();
        let mut body = target.image[..v.body].to_vec();
        body[v.pages..v.pages + PAGE].copy_from_slice(&crate::format::record(
            &v.generation,
            u64::MAX,
            1,
        ));
        body[v.pages + PAGE..v.pages + 2 * PAGE].fill(0);
        target.image = crate::avb::seal(&body, target.image.len()).unwrap();
        mem.disk = target.image.clone();
        ctx = authority::refreshed(&ctx, u64::MAX, 1);
        assert_eq!(execute(&mut mem, &mut target, &mut ctx, false), Ok(1));
        assert_eq!(mem.log, vec!["journal_read"]);
        assert!(execute(&mut mem, &mut target, &mut ctx, true).is_err());
        assert!(!mem.log.contains(&"write"));
        let _ = c;
    }
    fn crc_for_test(t: &[u8]) -> u32 {
        let mut c = !0u32;
        for (i, b) in t.iter().enumerate() {
            c ^= if i >= 76 { 0 } else { *b as u32 };
            for _ in 0..8 {
                c = (c >> 1) ^ 0xedb88320u32.wrapping_mul(c & 1);
            }
        }
        !c
    }
}
