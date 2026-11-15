// SPDX-License-Identifier: GPL-2.0-only
use super::*;
use crate::transaction::Io;
use std::collections::BTreeMap;
struct Memory {
    image: Vec<u8>,
    journal: Option<Vec<u8>>,
    ops: Vec<&'static str>,
    fail: Option<usize>,
    short: bool,
    rollback_fail: bool,
    writes: usize,
}
impl Memory {
    fn op(&mut self, s: &'static str) -> authority::Result<()> {
        self.ops.push(s);
        if self.fail == Some(self.ops.len()) {
            self.fail = None;
            return Err("injected");
        };
        Ok(())
    }
}
impl Io for Memory {
    fn probe(&mut self) -> authority::Result<()> {
        self.op("mount/probe/sync")
    }
    fn journal_read(&mut self) -> authority::Result<Option<Vec<u8>>> {
        self.op("journal-open")?;
        Ok(self.journal.clone())
    }
    fn journal_create(&mut self, b: &[u8]) -> authority::Result<()> {
        for s in [
            "allocation",
            "create",
            "write-journal",
            "sync-journal",
            "close-journal",
            "sync-dir",
            "sync-esp",
            "reopen-journal",
        ] {
            self.op(s)?
        }
        self.journal = Some(b.to_vec());
        Ok(())
    }
    fn journal_remove(&mut self) -> authority::Result<()> {
        self.op("remove-journal")?;
        self.journal = None;
        Ok(())
    }
    fn read(&mut self, _: u64, b: &mut [u8]) -> authority::Result<()> {
        self.op("readback")?;
        b.copy_from_slice(&self.image);
        Ok(())
    }
    fn write(&mut self, lba: u64, b: &[u8]) -> authority::Result<()> {
        self.writes += 1;
        if self.rollback_fail && self.writes > 1 {
            return Err("rollback failed");
        };
        self.op("boot-write")?;
        let at = ((lba - 100) * 512) as usize;
        assert_eq!(b.len(), 4096);
        let v = Image::verify(&preference_basis(&self.image, self.journal.as_deref()).unwrap())
            .unwrap();
        assert!([v.pages, v.pages + 4096, v.body.div_ceil(4096) * 4096].contains(&at));
        if self.short {
            self.image[at..at + 8].copy_from_slice(&b[..8]);
            self.short = false;
            return Err("short boot write");
        };
        self.image[at..at + 4096].copy_from_slice(b);
        Ok(())
    }
    fn flush(&mut self) -> authority::Result<()> {
        self.op("block-flush")
    }
}
fn fixture() -> (authority::Target, [u8; 96], Memory) {
    let (_, b) = crate::install_transaction::tests::fixture();
    let v = Image::verify(&b).unwrap();
    let c = context_for(2, &v.generation, v.sequence, v.mode);
    let t = authority::Target {
        index: 0,
        block: 512,
        lba: 100,
        disk_guid: [1; 16],
        part_guid: [2; 16],
        image: b.clone(),
    };
    (
        t,
        c,
        Memory {
            image: b,
            journal: None,
            ops: Vec::new(),
            fail: None,
            short: false,
            rollback_fail: false,
            writes: 0,
        },
    )
}
#[test]
fn preference_faults_noop_pending_and_foreign() {
    let (mut t, mut c, mut io) = fixture();
    transaction::execute(&mut io, &mut t, &mut c, false).unwrap();
    assert_eq!(io.ops, vec!["journal-open"]);
    assert_eq!(io.writes, 0);
    let (mut t, mut c, mut io) = fixture();
    transaction::execute(&mut io, &mut t, &mut c, true).unwrap();
    let count = io.ops.len();
    let new = io.image.clone();
    assert_eq!(io.writes, 2);
    for step in 1..=count {
        let (mut t, mut c, mut io) = fixture();
        let old = io.image.clone();
        io.fail = Some(step);
        assert!(
            transaction::execute(&mut io, &mut t, &mut c, true).is_err(),
            "step {step}"
        );
        assert!(io.image == old || io.image == new || io.journal.is_some());
        if io.journal.is_some() {
            t.image = io.image.clone();
            transaction::recover_pending(&mut io, &mut t, &mut c).unwrap();
            assert!(io.image == old || io.image == new);
            assert!(io.journal.is_none())
        }
    }
    let (mut t, mut c, mut io) = fixture();
    let old = io.image.clone();
    io.short = true;
    assert!(transaction::execute(&mut io, &mut t, &mut c, true).is_err());
    assert_eq!(io.image, old);
    let (mut t, mut c, mut io) = fixture();
    io.short = true;
    io.rollback_fail = true;
    assert!(transaction::execute(&mut io, &mut t, &mut c, true)
        .unwrap_err()
        .contains("rollback failed"));
    let retained = io.journal.clone();
    t.image = io.image.clone();
    let old_guid = t.part_guid;
    t.part_guid = [8; 16];
    assert!(transaction::recover_pending(&mut io, &mut t, &mut c).is_err());
    assert_eq!(io.journal, retained);
    t.part_guid = old_guid;
    io.rollback_fail = false;
    transaction::recover_pending(&mut io, &mut t, &mut c).unwrap();
    // Committed transaction with failed retirement: recover-only MUST NOT issue
    // the old context's preference and reverse the already committed Android.
    let (mut t, mut c, mut io) = fixture();
    let original = c;
    io.fail = Some(count);
    assert!(transaction::execute(&mut io, &mut t, &mut c, true).is_err());
    assert_eq!(io.image, new);
    t.image = io.image.clone();
    c = original;
    transaction::recover_pending(&mut io, &mut t, &mut c).unwrap();
    assert_eq!(Image::verify(&io.image).unwrap().mode, 0);
    let saved = io.image.clone();
    let mut called = false;
    let result = reset_after_verified(true, true, |linux| {
        assert!(linux);
        called = true;
        Err("mock reset rejected".into())
    });
    assert!(called && result.unwrap_err().contains("VERIFIED/COMMITTED"));
    assert_eq!(io.image, saved);
    reset_after_verified(false, true, |_| panic!("no reset requested")).unwrap();
    if let Some(p) = std::env::var_os("BOOT_CHOICE_SMALL_EXPORT") {
        std::fs::write(p, fixture().0.image).unwrap()
    }
}
#[test]
fn receipt_preserves_prior_helper_and_refuses_foreign_changes() {
    let (old, new) = crate::install_transaction::tests::fixture();
    let mut files: BTreeMap<String, Vec<u8>> = BTreeMap::new();
    files.insert(
        HELPER.into(),
        b"prior-helper-not-owned-by-this-install".to_vec(),
    );
    files.insert(MENU.into(), b"prior menu".to_vec());
    let plan = file_plan(
        |n| Ok(files.get(n).cloned()),
        &old,
        &new,
        Some(b"matched-new-helper"),
        false,
    )
    .unwrap();
    for f in &plan {
        if let Some(b) = &f.after {
            files.insert(f.name.clone(), b.clone());
        } else {
            files.remove(&f.name);
        }
    }
    let again = file_plan(
        |n| Ok(files.get(n).cloned()),
        &new,
        &new,
        Some(b"matched-new-helper"),
        false,
    )
    .unwrap();
    assert!(again.iter().all(|f| f.before == f.after));
    let restore = file_plan(|n| Ok(files.get(n).cloned()), &new, &old, None, true).unwrap();
    assert_eq!(
        restore
            .iter()
            .find(|f| f.name == HELPER)
            .unwrap()
            .after
            .as_deref(),
        Some(b"prior-helper-not-owned-by-this-install".as_slice())
    );
    files.insert(HELPER.into(), b"foreign replacement".to_vec());
    assert!(file_plan(|n| Ok(files.get(n).cloned()), &new, &old, None, true).is_err());
    let empty = BTreeMap::<String, Vec<u8>>::new();
    assert!(
        file_plan(|n| Ok(empty.get(n).cloned()), &new, &old, None, true)
            .unwrap()
            .is_empty()
    );
    let mut absent = BTreeMap::<String, Vec<u8>>::new();
    for f in file_plan(
        |n| Ok(absent.get(n).cloned()),
        &old,
        &new,
        Some(b"helper"),
        false,
    )
    .unwrap()
    {
        if let Some(bytes) = f.after {
            absent.insert(f.name, bytes);
        }
    }
    let removal = file_plan(|n| Ok(absent.get(n).cloned()), &new, &old, None, true).unwrap();
    assert_eq!(removal.len(), 3);
    assert!(removal.iter().all(|f| f.after.is_none()));
}
#[test]
fn actual_page_transport_partial_error_and_changed_region() {
    use std::io::Write;
    let path = std::env::temp_dir().join(format!("boot-choice-pages-{}", std::process::id()));
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&path)
        .unwrap();
    file.write_all(&vec![1; 8192]).unwrap();
    let mut observed = vec![1; 8192];
    let new = [2u8; 4096];
    assert!(checked_page(&file, &mut observed, 0, &new, |f, b, at| {
        f.write_at(&b[..8], at)?;
        Err(io::Error::from_raw_os_error(libc::EIO))
    })
    .is_err());
    assert_eq!(&observed[..8], &[2; 8]);
    checked_page(&file, &mut observed, 0, &[1; 4096], |f, b, at| {
        f.write_at(b, at)
    })
    .unwrap();
    assert_eq!(observed, vec![1; 8192]);
    file.write_at(&[9], 4096).unwrap();
    assert!(checked_page(&file, &mut observed, 4096, &new, |f, b, at| f
        .write_at(b, at))
    .is_err());
    let mut actual = vec![0; 8192];
    file.read_exact_at(&mut actual, 0).unwrap();
    assert_eq!(actual[4096], 9);
    std::fs::remove_file(path).unwrap();
}
#[test]
fn unlock_metadata_positive_only() {
    assert!(android_unlocked(b"androidboot.verifiedbootstate = \"orange\"\n").is_ok());
    assert!(android_unlocked(
        b"androidboot.vbmeta.device_state = unlocked\nandroidboot.flash.locked = 0\n"
    )
    .is_ok());
    for b in [
        b"".as_slice(),
        b"androidboot.verifiedbootstate = green\n",
        b"androidboot.verifiedbootstate = orange\nandroidboot.flash.locked = 1\n",
        b"androidboot.verifiedbootstate = orange\nandroidboot.verifiedbootstate = orange\n",
    ] {
        assert!(android_unlocked(b).is_err())
    }
}

#[test]
fn android_reset_is_standard_os_tool_without_nix_or_emergency_flags() {
    let (path, args) = android_reset_command();
    assert_eq!(path, Path::new("/system/bin/reboot"));
    assert!(args.is_empty());
}

#[test]
fn receipt_bounds_reject_before_mutation_and_roundtrip() {
    let (old, new) = crate::install_transaction::tests::fixture();
    let mut files = BTreeMap::from([
        (HELPER.into(), vec![0; RECEIPT_ORIGINAL_MAX + 1]),
        (MENU.into(), b"original menu".to_vec()),
    ]);
    let unchanged = files.clone();
    // Planning is the production pre-execute boundary: no journal or writes
    // can occur until a complete valid file plan has been returned.
    assert!(file_plan(
        |n| Ok(files.get(n).cloned()),
        &old,
        &new,
        Some(b"helper"),
        false
    )
    .err()
    .unwrap()
    .contains("original file exceeds"));
    assert_eq!(files, unchanged);
    assert!(!files.contains_key(RECEIPT));
    files.insert(HELPER.into(), vec![0; RECEIPT_ORIGINAL_MAX]);
    let originals = files.clone();
    let plan = file_plan(
        |n| Ok(files.get(n).cloned()),
        &old,
        &new,
        Some(b"helper"),
        false,
    )
    .unwrap();
    for f in plan {
        if let Some(b) = f.after {
            files.insert(f.name, b);
        } else {
            files.remove(&f.name);
        }
    }
    let mut bad: Receipt = serde_json::from_slice(&files[RECEIPT]).unwrap();
    bad.originals
        .iter_mut()
        .find(|f| f.name == HELPER)
        .unwrap()
        .before = Some(vec![0; RECEIPT_ORIGINAL_MAX + 1]);
    let good_receipt = files[RECEIPT].clone();
    files.insert(RECEIPT.into(), serde_json::to_vec(&bad).unwrap());
    let corrupt = files.clone();
    assert!(file_plan(|n| Ok(files.get(n).cloned()), &new, &old, None, true).is_err());
    assert_eq!(files, corrupt);
    files.insert(RECEIPT.into(), vec![0; RECEIPT_MAX + 1]);
    assert!(
        file_plan(|n| Ok(files.get(n).cloned()), &new, &old, None, true)
            .err()
            .unwrap()
            .contains("receipt size")
    );
    files.insert(RECEIPT.into(), good_receipt);
    for f in file_plan(|n| Ok(files.get(n).cloned()), &new, &old, None, true).unwrap() {
        if let Some(b) = f.after {
            files.insert(f.name, b);
        } else {
            files.remove(&f.name);
        }
    }
    assert_eq!(files, originals);
}

#[test]
fn native_receipt_survives_real_bootstrap_updates_rollbacks_and_disable() {
    use std::os::unix::fs::PermissionsExt;
    let (old, new) = crate::install_transaction::tests::fixture();
    let root = std::env::temp_dir().join(format!("bc-bootstrap-{}", std::process::id()));
    std::fs::create_dir(&root).unwrap();
    std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
    let source = root.join("source-helper");
    let menu = root.join("source-menu");
    std::fs::write(&source, b"Nix helper A").unwrap();
    std::fs::write(&menu, MENU_BYTES).unwrap();
    let deploy = || {
        let out = Command::new("python3")
            .args([
                "-c",
                include_str!("../../modules/mobile/install-boot-choice.py"),
            ])
            .arg(&root)
            .arg(&source)
            .arg(&menu)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
    };
    deploy(); // No receipt: ordinary bootstrap works.
    let read = |name: &str| match std::fs::read(root.join(name)) {
        Ok(b) => Ok(Some(b)),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    };
    let apply = |plan: Vec<full::FileChange>| {
        for f in plan {
            let p = root.join(f.name);
            if let Some(b) = f.after {
                std::fs::create_dir_all(p.parent().unwrap()).unwrap();
                std::fs::write(p, b).unwrap();
            } else {
                std::fs::remove_file(p).unwrap();
            }
        }
    };
    apply(file_plan(read, &old, &new, Some(b"native B"), false).unwrap());
    let receipt = std::fs::read(root.join(RECEIPT)).unwrap();
    // Native controller session and Nix bootstrap also serialize on held ESP FD.
    let lock = File::open(&root).unwrap();
    assert_eq!(
        unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
        0
    );
    let out = Command::new("python3")
        .args([
            "-c",
            include_str!("../../modules/mobile/install-boot-choice.py"),
        ])
        .arg(&root)
        .arg(&source)
        .arg(&menu)
        .output()
        .unwrap();
    assert!(!out.status.success());
    drop(lock);
    for helper in [b"new Nix generation A2".as_slice(), b"rollback Nix A"] {
        std::fs::write(&source, helper).unwrap();
        deploy();
        assert_eq!(std::fs::read(root.join(HELPER)).unwrap(), b"native B");
        assert_eq!(std::fs::read(root.join(MENU)).unwrap(), MENU_BYTES);
        assert_eq!(std::fs::read(root.join(RECEIPT)).unwrap(), receipt);
    }
    // Disable makes no bootstrap call; no extra-files marker owns the pair.
    assert!(!root.join("EFI/nixos/.extra-files").join(HELPER).exists());
    apply(file_plan(read, &new, &new, Some(b"native C"), false).unwrap());
    assert_eq!(std::fs::read(root.join(HELPER)).unwrap(), b"native C");
    apply(file_plan(read, &new, &old, None, true).unwrap());
    assert_eq!(std::fs::read(root.join(HELPER)).unwrap(), b"Nix helper A");
    assert_eq!(std::fs::read(root.join(MENU)).unwrap(), MENU_BYTES);
    assert!(!root.join(RECEIPT).exists());
    // Pending/corrupt evidence is retained and blocks bootstrap, not authority.
    std::fs::write(root.join(RECEIPT), b"corrupt").unwrap();
    deploy();
    assert_eq!(std::fs::read(root.join(HELPER)).unwrap(), b"Nix helper A");
    assert_eq!(std::fs::read(root.join(RECEIPT)).unwrap(), b"corrupt");
    std::fs::remove_file(root.join(RECEIPT)).unwrap();
    for evidence in [FULL, PREF] {
        std::fs::write(root.join(evidence), b"undo").unwrap();
        deploy();
        assert_eq!(std::fs::read(root.join(HELPER)).unwrap(), b"Nix helper A");
        std::fs::remove_file(root.join(evidence)).unwrap();
    }
    std::fs::remove_dir_all(root).unwrap();
}
