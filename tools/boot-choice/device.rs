// SPDX-License-Identifier: GPL-2.0-only
//! Linux backend for a future daemon operation, deliberately not a CLI command.
//! Policy paths and authority must come from trusted installer configuration.
use crate::{check, hash, hex, transact_with_gate, Owned, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::{
        fd::AsRawFd,
        unix::fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt},
    },
    path::{Path, PathBuf},
};

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub name: String,
    pub path: PathBuf,
    pub offset: u64,
    pub length: usize,
    pub sha256: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Binding {
    pub partuuid: String,
    pub rdev: u64,
    pub size: u64,
    pub board_path: PathBuf,
    pub board: String,
    /// Kernel-provided cmdline or bootconfig, not a user-maintained slot claim.
    pub boot_state_path: PathBuf,
    pub slot: String,
    pub rom_metadata_path: PathBuf,
    pub rom_metadata_sha256: String,
    pub battery_capacity_path: PathBuf,
    pub battery_status_path: PathBuf,
    pub minimum_capacity: u8,
    pub snapshots: Vec<Snapshot>,
}
#[derive(Serialize)]
pub struct Authority {
    schema: u32,
    owned: Owned,
    source_sha256: [String; 4],
    binding: Binding,
}
// Only the root-origin Authority loader may reconstruct private Owned fields.
// Owned itself deliberately has no public deserializer/bypass of from_sources.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OwnedWire {
    size: usize,
    body: usize,
    pages: usize,
    generation: [u8; 32],
    immutable: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AuthorityWire {
    schema: u32,
    owned: OwnedWire,
    source_sha256: [String; 4],
    binding: Binding,
}
impl<'de> Deserialize<'de> for Authority {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        let w = AuthorityWire::deserialize(d)?;
        let a = Self {
            schema: w.schema,
            owned: Owned {
                size: w.owned.size,
                body: w.owned.body,
                pages: w.owned.pages,
                generation: w.owned.generation,
                immutable: w.owned.immutable,
            },
            source_sha256: w.source_sha256,
            binding: w.binding,
        };
        a.validate().map_err(serde::de::Error::custom)?;
        Ok(a)
    }
}

fn digest(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}
impl Authority {
    /// Installer-only: exact source validation plus whole installed image verification.
    /// This does NOT install anything or establish firmware acceptance.
    pub fn from_verified_install(
        c: &serde_json::Value,
        original: &[u8],
        raw: &[u8],
        elf: &[u8],
        config: &[u8],
        installed: &[u8],
        binding: Binding,
    ) -> Result<Self> {
        let owned = Owned::from_sources(c, original, raw, elf, config)?;
        owned.verify(installed)?;
        let a = Self {
            schema: 1,
            owned,
            source_sha256: [original, raw, elf, config].map(|bytes| hex(&hash(bytes))),
            binding,
        };
        a.validate()?;
        Ok(a)
    }
    fn validate(&self) -> Result<()> {
        let o = &self.owned;
        let b = &self.binding;
        check(
            self.schema == 1
                && self.source_sha256.iter().all(|s| digest(s))
                && digest(&o.immutable),
            "authority schema/hash",
        )?;
        check(
            o.size <= crate::LIMIT
                && o.size >= 16384
                && o.size.is_multiple_of(4096)
                && o.body.is_multiple_of(4096)
                && o.body >= 12288
                && o.body.checked_add(8192).is_some_and(|v| v <= o.size)
                && o.pages >= 8192
                && o.pages.is_multiple_of(4096)
                && o.pages.checked_add(8192).is_some_and(|v| v < o.body),
            "authority bounds",
        )?;
        check(
            b.size == o.size as u64
                && b.rdev != 0
                && !b.board.is_empty()
                && ["_a", "_b"].contains(&b.slot.as_str())
                && b.minimum_capacity >= 20
                && b.minimum_capacity <= 100
                && digest(&b.rom_metadata_sha256),
            "install binding",
        )?;
        check(
            b.partuuid.len() == 36
                && b.partuuid.bytes().enumerate().all(|(i, c)| {
                    if [8, 13, 18, 23].contains(&i) {
                        c == b'-'
                    } else {
                        c.is_ascii_digit() || (b'a'..=b'f').contains(&c)
                    }
                }),
            "PARTUUID syntax",
        )?;
        check(
            b.snapshots.len() == 2
                && ["gpt", "bcb"]
                    .iter()
                    .all(|name| b.snapshots.iter().filter(|s| s.name == *name).count() == 1),
            "GPT/BCB gates required",
        )?;
        for path in [
            &b.board_path,
            &b.boot_state_path,
            &b.rom_metadata_path,
            &b.battery_capacity_path,
            &b.battery_status_path,
        ]
        .into_iter()
        .chain(b.snapshots.iter().map(|s| &s.path))
        {
            check(
                path.is_absolute()
                    && !path.components().any(|c| {
                        matches!(
                            c,
                            std::path::Component::ParentDir | std::path::Component::CurDir
                        )
                    }),
                "absolute metadata path required",
            )?;
        }
        for s in &b.snapshots {
            check(
                s.length > 0
                    && s.length <= 1024 * 1024
                    && s.offset.checked_add(s.length as u64).is_some()
                    && digest(&s.sha256),
                "snapshot bounds/hash",
            )?;
        }
        Ok(())
    }
    /// New directory only. Root-owned ancestry, no existing authority overwrite.
    pub fn persist_new(&self, directory: &Path) -> Result<()> {
        self.validate()?;
        check(unsafe { libc::geteuid() } == 0, "root installer required")?;
        trusted(directory.parent().ok_or("authority parent")?)?;
        fs::DirBuilder::new()
            .mode(0o700)
            .create(directory)
            .map_err(err)?;
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(directory.join("authority.new"))
            .map_err(err)?;
        f.write_all(&serde_json::to_vec(self).map_err(err)?)
            .and_then(|_| f.sync_all())
            .map_err(err)?;
        fs::rename(
            directory.join("authority.new"),
            directory.join("authority.json"),
        )
        .map_err(err)?;
        File::open(directory)
            .and_then(|f| f.sync_all())
            .map_err(err)?;
        File::open(directory.parent().unwrap())
            .and_then(|f| f.sync_all())
            .map_err(err)
    }
    pub fn load(path: &Path) -> Result<Self> {
        trusted(path)?;
        let mut f = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW)
            .open(path)
            .map_err(err)?;
        let m = f.metadata().map_err(err)?;
        check(
            m.is_file() && m.uid() == 0 && m.mode() & 0o022 == 0 && m.len() <= 65536,
            "root-protected regular authority",
        )?;
        let mut bytes = Vec::new();
        Read::by_ref(&mut f)
            .take(65537)
            .read_to_end(&mut bytes)
            .map_err(err)?;
        check(bytes.len() <= 65536, "authority bound")?;
        let a: Self = serde_json::from_slice(&bytes).map_err(err)?;
        a.validate()?;
        Ok(a)
    }
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn trusted(path: &Path) -> Result<()> {
    check(
        path.is_absolute()
            && !path.components().any(|c| {
                matches!(
                    c,
                    std::path::Component::ParentDir | std::path::Component::CurDir
                )
            }),
        "normalized absolute trusted path required",
    )?;
    for p in path.ancestors() {
        let m = fs::symlink_metadata(p).map_err(err)?;
        check(
            !m.file_type().is_symlink() && m.uid() == 0 && m.mode() & 0o022 == 0,
            "untrusted authority ancestry",
        )?;
    }
    Ok(())
}
fn bounded(path: &Path) -> Result<Vec<u8>> {
    let mut b = Vec::new();
    File::open(path)
        .map_err(err)?
        .take(1024 * 1024 + 1)
        .read_to_end(&mut b)
        .map_err(err)?;
    check(b.len() <= 1024 * 1024, "metadata bound")?;
    Ok(b)
}
fn text(path: &Path) -> Result<String> {
    String::from_utf8(bounded(path)?).map_err(err)
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Observation {
    board: String,
    slot: String,
    rom: String,
    capacity: u8,
    charging: bool,
    snapshots: Vec<String>,
    mounted: bool,
    holders: bool,
    rdev: u64,
    size: u64,
}
fn validate_observation(b: &Binding, o: &Observation) -> Result<()> {
    check(
        o.board == b.board && o.slot == b.slot && o.rom == b.rom_metadata_sha256,
        "board/slot/ROM mismatch",
    )?;
    check(
        o.rdev == b.rdev && o.size == b.size && !o.mounted && !o.holders,
        "target identity/in use",
    )?;
    check(
        o.capacity >= b.minimum_capacity && o.capacity <= 100 && o.charging,
        "power gate: charging/full and sufficient battery required",
    )?;
    check(
        o.snapshots
            == b.snapshots
                .iter()
                .map(|s| s.sha256.clone())
                .collect::<Vec<_>>(),
        "GPT/BCB changed",
    )
}
fn slot(state: &str) -> Result<String> {
    let mut values = Vec::new();
    // bootconfig permits spaces around '=' and quoted values; cmdline does not.
    for line in state.lines() {
        if let Some((key, value)) = line.split_once('=') {
            if key.trim() == "androidboot.slot_suffix" && !value.trim().contains(' ') {
                values.push(value.trim().trim_matches('"').to_owned());
                continue;
            }
        }
        for word in line.split_whitespace() {
            if let Some(value) = word.strip_prefix("androidboot.slot_suffix=") {
                values.push(value.trim_matches('"').to_owned());
            }
        }
    }
    check(
        values.len() == 1 && ["_a", "_b"].contains(&values[0].as_str()),
        "unambiguous current kernel slot required",
    )?;
    Ok(values.remove(0))
}
fn exclusive(file: &File) -> Result<()> {
    check(
        unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0,
        "target locked",
    )
}
fn snapshot(s: &Snapshot) -> Result<String> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(crate::media::FLAGS)
        .open(&s.path)
        .map_err(err)?;
    let mut data = vec![0; s.length];
    crate::media::read_at(&f, &mut data, s.offset).map_err(err)?;
    Ok(hex(&hash(&data)))
}
fn uuid_identity(expected: u64, actual: u64, is_block: bool) -> Result<()> {
    check(
        is_block && expected == actual,
        "PARTUUID descriptor mismatch",
    )
}

fn observe(b: &Binding, f: &File) -> Result<Observation> {
    let m = f.metadata().map_err(err)?;
    check(m.file_type().is_block_device(), "block device required")?;
    let mut size = 0u64;
    // Linux BLKGETSIZE64; inspect the held descriptor, not stat size or a pathname.
    check(
        unsafe { libc::ioctl(f.as_raw_fd(), 0x80081272u32 as _, &mut size) } == 0,
        "BLKGETSIZE64",
    )?;
    let major = libc::major(m.rdev());
    let minor = libc::minor(m.rdev());
    let id = format!("{major}:{minor}");
    let mounted = text(Path::new("/proc/self/mountinfo"))?
        .lines()
        .any(|l| l.split_whitespace().nth(2) == Some(id.as_str()));
    let holders = fs::read_dir(format!("/sys/dev/block/{id}/holders"))
        .map_err(err)?
        .next()
        .is_some();
    let uuid = fs::metadata(format!("/dev/disk/by-partuuid/{}", b.partuuid)).map_err(err)?;
    uuid_identity(m.rdev(), uuid.rdev(), uuid.file_type().is_block_device())?;
    let mut snapshots = Vec::new();
    for s in &b.snapshots {
        snapshots.push(snapshot(s)?);
    }
    Ok(Observation {
        board: text(&b.board_path)?
            .trim_end_matches(['\0', '\n'])
            .to_owned(),
        slot: slot(&text(&b.boot_state_path)?)?,
        rom: hex(&hash(&bounded(&b.rom_metadata_path)?)),
        capacity: text(&b.battery_capacity_path)?
            .trim()
            .parse()
            .map_err(err)?,
        charging: matches!(text(&b.battery_status_path)?.trim(), "Charging" | "Full"),
        snapshots,
        mounted,
        holders,
        rdev: m.rdev(),
        size,
    })
}
/// Backend object holds the exclusive descriptor lock until drop. No slot switch,
/// reboot, automatic install, or standalone/uninitialized target conversion.
pub struct Device {
    file: File,
    authority: Authority,
}
impl Device {
    pub fn acquire(authority_path: &Path) -> Result<Self> {
        check(
            unsafe { libc::geteuid() } == 0,
            "root operation owner required",
        )?;
        let authority = Authority::load(authority_path)?;
        let path = format!("/dev/disk/by-partuuid/{}", authority.binding.partuuid);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_EXCL | libc::O_CLOEXEC | crate::media::FLAGS)
            .open(path)
            .map_err(err)?;
        exclusive(&file)?;
        validate_observation(&authority.binding, &observe(&authority.binding, &file)?)?;
        Ok(Self { file, authority })
    }
    /// Must be called only by the operation owner after explicit user consent.
    /// Journal directory is NEW and retained on all outcomes. No reboot on error.
    pub fn request(
        &mut self,
        mode: u32,
        execute: bool,
        acknowledge_inplace_powerloss_risk: bool,
        journal_directory: &Path,
    ) -> Result<()> {
        check(
            execute && acknowledge_inplace_powerloss_risk && mode <= 1,
            "explicit execution/risk acknowledgement and NUM mode required",
        )?;
        validate_observation(
            &self.authority.binding,
            &observe(&self.authority.binding, &self.file)?,
        )?;
        trusted(journal_directory.parent().ok_or("journal parent")?)?;
        fs::DirBuilder::new()
            .mode(0o700)
            .create(journal_directory)
            .map_err(err)?;
        let mut journal = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(journal_directory.join("before.img"))
            .map_err(err)?;
        File::open(journal_directory)
            .and_then(|f| f.sync_all())
            .map_err(err)?;
        File::open(journal_directory.parent().unwrap())
            .and_then(|f| f.sync_all())
            .map_err(err)?;
        self.manifest(journal_directory, mode, "prepared", None)?;
        // Acquire live identity/power/snapshot state again immediately before core I/O.
        let result = (|| {
            validate_observation(
                &self.authority.binding,
                &observe(&self.authority.binding, &self.file)?,
            )?;
            {
                let descriptor = self.file.try_clone().map_err(err)?;
                transact_with_gate(
                    &mut crate::media::Storage(&mut self.file),
                    &mut journal,
                    &self.authority.owned,
                    mode,
                    || {
                        validate_observation(
                            &self.authority.binding,
                            &observe(&self.authority.binding, &descriptor)?,
                        )
                    },
                )
            }
        })();
        self.manifest(
            journal_directory,
            mode,
            if result.is_ok() { "verified" } else { "failed" },
            result.as_ref().err(),
        )?;
        result
    }
    fn manifest(&self, dir: &Path, mode: u32, state: &str, error: Option<&String>) -> Result<()> {
        let identity = serde_json::to_vec(&self.authority).map_err(err)?;
        let data = serde_json::json!({"schema":1,"state":state,"mode":mode,"unix_seconds":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_secs(),"authority_sha256":hex(&hash(&identity)),"partition_identity_sha256":hex(&hash(&serde_json::to_vec(&serde_json::json!([self.authority.binding.partuuid, self.authority.binding.rdev, self.authority.binding.size])).map_err(err)?)),"partuuid":self.authority.binding.partuuid,"rdev":self.authority.binding.rdev,"size":self.authority.binding.size,"error":error});
        let tmp = dir.join("manifest.new");
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&tmp)
            .map_err(err)?;
        f.write_all(&serde_json::to_vec(&data).map_err(err)?)
            .and_then(|_| f.sync_all())
            .map_err(err)?;
        fs::rename(tmp, dir.join("manifest.json")).map_err(err)?;
        File::open(dir).and_then(|f| f.sync_all()).map_err(err)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    impl crate::Storage for std::io::Cursor<Vec<u8>> {
        fn sync(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    fn binding() -> Binding {
        Binding {
            partuuid: "00000000-0000-0000-0000-000000000001".into(),
            rdev: 2049,
            size: 32768,
            board_path: "/sys/firmware/devicetree/base/model".into(),
            board: "test board".into(),
            boot_state_path: "/proc/bootconfig".into(),
            slot: "_a".into(),
            rom_metadata_path: "/rom/build.prop".into(),
            rom_metadata_sha256: hex(&hash(b"rom")),
            battery_capacity_path: "/sys/fake/capacity".into(),
            battery_status_path: "/sys/fake/status".into(),
            minimum_capacity: 50,
            snapshots: ["gpt", "bcb"]
                .map(|name| Snapshot {
                    name: name.into(),
                    path: "/unused".into(),
                    offset: 0,
                    length: 64,
                    sha256: hex(&hash(name.as_bytes())),
                })
                .into(),
        }
    }
    fn observation(b: &Binding) -> Observation {
        Observation {
            board: b.board.clone(),
            slot: b.slot.clone(),
            rom: b.rom_metadata_sha256.clone(),
            capacity: 80,
            charging: true,
            snapshots: b.snapshots.iter().map(|s| s.sha256.clone()).collect(),
            mounted: false,
            holders: false,
            rdev: b.rdev,
            size: b.size,
        }
    }
    #[test]
    fn identity_power_and_snapshot_refusals() {
        let b = binding();
        let good = observation(&b);
        validate_observation(&b, &good).unwrap();
        let mutations: Vec<(&str, Observation)> = vec![
            (
                "board",
                Observation {
                    board: "other".into(),
                    ..good.clone()
                },
            ),
            (
                "standalone current B",
                Observation {
                    slot: "_b".into(),
                    ..good.clone()
                },
            ),
            (
                "ROM",
                Observation {
                    rom: hex(&hash(b"other")),
                    ..good.clone()
                },
            ),
            (
                "dev_t",
                Observation {
                    rdev: 2050,
                    ..good.clone()
                },
            ),
            (
                "size",
                Observation {
                    size: 65536,
                    ..good.clone()
                },
            ),
            (
                "mounted",
                Observation {
                    mounted: true,
                    ..good.clone()
                },
            ),
            (
                "holders",
                Observation {
                    holders: true,
                    ..good.clone()
                },
            ),
            (
                "low battery",
                Observation {
                    capacity: 49,
                    ..good.clone()
                },
            ),
            (
                "invalid battery",
                Observation {
                    capacity: 101,
                    ..good.clone()
                },
            ),
            (
                "unpowered",
                Observation {
                    charging: false,
                    ..good.clone()
                },
            ),
            (
                "BCB",
                Observation {
                    snapshots: vec![good.snapshots[0].clone(), hex(&hash(b"changed"))],
                    ..good.clone()
                },
            ),
            (
                "GPT",
                Observation {
                    snapshots: vec![hex(&hash(b"changed")), good.snapshots[1].clone()],
                    ..good.clone()
                },
            ),
        ];
        for (name, bad) in mutations {
            assert!(validate_observation(&b, &bad).is_err(), "{name}");
        }
        uuid_identity(2049, 2049, true).unwrap();
        assert!(uuid_identity(2049, 2050, true).is_err());
        assert!(uuid_identity(2049, 2049, false).is_err());
    }
    #[test]
    fn strict_schema_and_stale_install() {
        let (owned, image) = crate::tests::fixture();
        let a = Authority {
            schema: 1,
            owned,
            source_sha256: std::array::from_fn(|_| hex(&hash(b"source"))),
            binding: binding(),
        };
        a.validate().unwrap();
        a.owned.verify(&image).unwrap();
        let value = serde_json::to_value(&a).unwrap();
        let parsed: Authority = serde_json::from_value(value.clone()).unwrap();
        parsed.owned.verify(&image).unwrap();
        for (key, value) in [
            ("schema", serde_json::json!(2)),
            ("unexpected", serde_json::json!(true)),
        ] {
            let mut bad = serde_json::to_value(&a).unwrap();
            bad[key] = value;
            assert!(serde_json::from_value::<Authority>(bad)
                .and_then(|a| a.validate().map_err(serde::de::Error::custom))
                .is_err());
        }
        for (key, value) in [("pages", usize::MAX), ("body", 0), ("size", usize::MAX)] {
            let mut bad = serde_json::to_value(&a).unwrap();
            bad["owned"][key] = serde_json::json!(value);
            assert!(serde_json::from_value::<Authority>(bad).is_err());
        }
        let mut stale: Authority = serde_json::from_value(value.clone()).unwrap();
        stale.owned.generation[0] ^= 1;
        assert!(stale.owned.verify(&image).is_err());
        let mut stale: Authority = serde_json::from_value(value).unwrap();
        stale.owned.immutable = hex(&hash(b"stale"));
        assert!(stale.owned.verify(&image).is_err());
        let mut original = image.clone();
        original[8192..16384].fill(0);
        let unowned = crate::seal(&original[..24576], 32768).unwrap();
        assert!(a.owned.verify(&unowned).is_err());
        assert!(a.owned.verify(&vec![0; 32768]).is_err());
    }
    #[test]
    fn live_gate_failure_after_journal_does_not_write() {
        let (owned, image) = crate::tests::fixture();
        let mut target = std::io::Cursor::new(image.clone());
        let mut journal = std::io::Cursor::new(Vec::new());
        let result = transact_with_gate(&mut target, &mut journal, &owned, 0, || {
            Err("power changed".into())
        });
        assert_eq!(result.unwrap_err(), "power changed");
        assert_eq!(target.into_inner(), image);
        assert_eq!(journal.into_inner(), image);
    }
    #[test]
    fn kernel_slot_formats() {
        assert_eq!(
            slot("console=x androidboot.slot_suffix=_a other=y").unwrap(),
            "_a"
        );
        assert_eq!(
            slot("androidboot.slot_suffix = \"_a\"\nother = 1").unwrap(),
            "_a"
        );
        for s in [
            "",
            "androidboot.slot_suffix=_a androidboot.slot_suffix=_b",
            "androidboot.slot_suffix=_c",
        ] {
            assert!(slot(s).is_err());
        }
    }
    #[test]
    fn host_descriptor_lock_and_snapshot() {
        // Host ordinary-file descriptors only, never /dev or live sysfs.
        let dir =
            std::env::temp_dir().join(format!("boot-choice-adapter-test-{}", std::process::id()));
        fs::create_dir(&dir).unwrap();
        let path = dir.join("snapshot");
        fs::write(&path, b"0123456789").unwrap();
        let first = File::open(&path).unwrap();
        let second = File::open(&path).unwrap();
        exclusive(&first).unwrap();
        assert!(exclusive(&second).is_err());
        drop(first);
        exclusive(&second).unwrap();
        let s = Snapshot {
            name: "bcb".into(),
            path: path.clone(),
            offset: 2,
            length: 4,
            sha256: hex(&hash(b"2345")),
        };
        assert_eq!(snapshot(&s).unwrap(), s.sha256);
        fs::write(&path, b"01xxxx6789").unwrap();
        assert_ne!(snapshot(&s).unwrap(), s.sha256);
        fs::write(&path, b"01").unwrap();
        assert!(snapshot(&s).is_err());
        assert!(trusted(&dir).is_err()); // /tmp is not trusted root-only authority ancestry.
        drop(second);
        fs::remove_dir_all(dir).unwrap();
    }
}
