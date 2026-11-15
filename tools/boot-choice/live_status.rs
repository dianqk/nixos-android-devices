// SPDX-License-Identifier: GPL-2.0-only
//! Read-only live inspection. The returned report is NOT serializable write
//! authority. No block-path override, mount, preference write or reset exists.
use crate::{authority, context, hash, hex, owned::Image, provenance, Result};
use serde::Serialize;
use std::{
    fs::{self, File, OpenOptions},
    io::Read,
    os::{
        fd::AsRawFd,
        unix::fs::{FileExt, FileTypeExt, MetadataExt, OpenOptionsExt},
    },
    path::{Path, PathBuf},
};
fn check(b: bool, e: &str) -> Result<()> {
    if b {
        Ok(())
    } else {
        Err(e.into())
    }
}
fn small(path: &Path, cap: usize) -> Result<Vec<u8>> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    check(
        f.metadata().map_err(|e| e.to_string())?.is_file(),
        "metadata is not regular",
    )?;
    let mut b = Vec::new();
    f.take(cap as u64 + 1)
        .read_to_end(&mut b)
        .map_err(|e| e.to_string())?;
    check(b.len() <= cap, "metadata bound")?;
    Ok(b)
}
#[derive(Debug, PartialEq, Eq)]
struct Board {
    model: Vec<u8>,
    compatible: Option<Vec<u8>>,
}
impl Board {
    fn validate(linux: bool, model: &[u8], compatible: Option<&[u8]>) -> Result<()> {
        let valid = if linux {
            model == b"OnePlus 13\0"
                && compatible == Some(b"oneplus,dodge\0qcom,sm8750\0".as_slice())
        } else {
            model == b"Qualcomm Technologies, Inc. Sun MTP,dodge\0" && compatible.is_none()
        };
        check(valid, "unsupported device model/compatible for booted OS")
    }
    fn read(linux: bool) -> Result<Self> {
        let board = Self {
            model: small(Path::new("/sys/firmware/devicetree/base/model"), 256)?,
            compatible: if linux {
                Some(small(Path::new("/sys/firmware/devicetree/base/compatible"), 4096)?)
            } else {
                None
            },
        };
        Self::validate(linux, &board.model, board.compatible.as_deref())?;
        Ok(board)
    }
}
fn text(path: &Path) -> Result<String> {
    String::from_utf8(small(path, 1024 * 1024)?).map_err(|e| e.to_string())
}
fn geometry(file: &File) -> Result<(usize, u64)> {
    let mut size = 0u64;
    let mut sector = 0i32;
    check(
        file.metadata()
            .map_err(|e| e.to_string())?
            .file_type()
            .is_block_device(),
        "block descriptor required",
    )?;
    check(
        unsafe { libc::ioctl(file.as_raw_fd(), 0x80081272u32 as _, &mut size) } == 0
            && unsafe { libc::ioctl(file.as_raw_fd(), 0x1268u32 as _, &mut sector) } == 0,
        "block geometry ioctl",
    )?;
    check(
        matches!(sector, 512 | 4096) && size >= 4096 && size % (sector as u64) == 0,
        "block geometry",
    )?;
    Ok((sector as usize, size))
}
fn block_node_root(linux: bool) -> &'static str {
    // udev's /dev/block also exists on Linux, but contains major:minor links,
    // not Android's named nodes. Final opens still require O_NOFOLLOW+rdev.
    if linux { "/dev" } else { "/dev/block" }
}
fn open_block(name: &str, expected: u64) -> Result<File> {
    check(
        !name.is_empty() && name.bytes().all(|b| b.is_ascii_alphanumeric()),
        "kernel block name",
    )?;
    let base = block_node_root(Path::new("/sys/firmware/efi").is_dir());
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK | crate::media::FLAGS)
        .open(Path::new(base).join(name))
        .map_err(|e| e.to_string())?;
    check(
        file.metadata().map_err(|e| e.to_string())?.rdev() == expected,
        "kernel block descriptor identity",
    )?;
    geometry(&file)?;
    Ok(file)
}
fn dev(path: &Path) -> Result<u64> {
    let s = text(&path.join("dev"))?;
    let (a, b) = s.trim().split_once(':').ok_or("sysfs dev syntax")?;
    let major: u32 = a.parse().map_err(|_| "major")?;
    let minor: u32 = b.parse().map_err(|_| "minor")?;
    Ok(libc::makedev(major, minor))
}
fn controller(path: &Path) -> Result<Option<(PathBuf, u32)>> {
    let device = fs::canonicalize(path.join("device")).map_err(|e| e.to_string())?;
    let leaf = device
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or("SCSI identity")?;
    let fields: Vec<_> = leaf.split(':').collect();
    if fields.len() != 4 {
        return Ok(None);
    }
    let ids: Vec<u32> = fields
        .iter()
        .map(|s| s.parse().map_err(|_| "SCSI address"))
        .collect::<std::result::Result<_, _>>()?;
    for ancestor in device.ancestors() {
        let compatible = ancestor.join("of_node/compatible");
        if let Ok(bytes) = small(&compatible, 4096) {
            if bytes.split(|b| *b == 0).any(|s| s == b"qcom,ufshc") {
                check(
                    ids[1] == 0 && ids[2] == 0 && ids[3] < 8,
                    "unsupported UFS target/LUN",
                )?;
                return Ok(Some((ancestor.to_path_buf(), ids[3])));
            }
        }
    }
    Ok(None)
}
struct Disk {
    file: File,
    block: usize,
    last: u64,
}
impl authority::ReadDisk for Disk {
    fn read(&mut self, lba: u64, out: &mut [u8]) -> authority::Result<()> {
        let at = lba
            .checked_mul(self.block as u64)
            .ok_or("read offset overflow")?;
        if !out.len().is_multiple_of(self.block)
            || lba > self.last
            || out.len() as u64 > ((self.last + 1) * self.block as u64) - at
        {
            return Err("disk read bound");
        }
        crate::media::read_at(&self.file, out, at).map_err(|e| {
            eprintln!("fresh block read at {at}, {} bytes: {e}", out.len());
            "fresh block read"
        })
    }
}
struct Member {
    sys: PathBuf,
    file: File,
    block: usize,
    size: u64,
    rdev: u64,
    lun: u32,
}
struct Group {
    members: Vec<Member>,
    controller: PathBuf,
}
impl authority::DiskGroup for Group {
    type Disk = Disk;
    fn select(&mut self, index: usize) -> authority::Result<(Disk, usize, u64)> {
        let m = self.members.get(index).ok_or("member index")?;
        let (block, size) = geometry(&m.file).map_err(|_| "member geometry")?;
        if block != m.block
            || size != m.size
            || m.file.metadata().map_err(|_| "member stat")?.rdev() != m.rdev
        {
            return Err("member changed");
        }
        let last = size / block as u64 - 1;
        Ok((
            Disk {
                file: m.file.try_clone().map_err(|_| "member clone")?,
                block,
                last,
            },
            block,
            last,
        ))
    }
}
impl Group {
    fn acquire() -> Result<Self> {
        let mut members = Vec::new();
        let mut owner = None;
        let mut mask = 0u32;
        for entry in fs::read_dir("/sys/class/block").map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let sys = entry.path();
            if sys.join("partition").exists() || !sys.join("device").exists() {
                continue;
            }
            let Some((parent, lun)) = controller(&sys)? else {
                continue;
            };
            if let Some(old) = &owner {
                check(old == &parent, "ambiguous UFS controller")?
            } else {
                owner = Some(parent)
            }
            check(mask & (1 << lun) == 0, "duplicate UFS LUN")?;
            mask |= 1 << lun;
            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| "block name encoding")?;
            let rdev = dev(&sys)?;
            let file = open_block(&name, rdev)?;
            let (block, size) = geometry(&file)?;
            members.push(Member {
                sys,
                file,
                block,
                size,
                rdev,
                lun,
            });
        }
        check(
            (1..=8).contains(&members.len()),
            "missing/bounded UFS group",
        )?;
        members.sort_by_key(|m| m.lun);
        Ok(Self {
            members,
            controller: owner.ok_or("missing UFS controller")?,
        })
    }
    fn recheck(&self) -> Result<()> {
        for m in &self.members {
            check(
                controller(&m.sys)? == Some((self.controller.clone(), m.lun))
                    && dev(&m.sys)? == m.rdev
                    && geometry(&m.file)? == (m.block, m.size),
                "UFS media/controller changed",
            )?;
        }
        Ok(())
    }
}
fn le32(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
}
fn le64(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn context_for(slot: u32, generation: &[u8; 32], sequence: u64, mode: u32) -> [u8; 96] {
    let mut b = [0; 96];
    for (at, n) in [
        (0, 1u32),
        (4, 96),
        (8, 1),
        (24, 1),
        (28, 80),
        (84, slot),
        (88, 1),
    ] {
        b[at..at + 4].copy_from_slice(&n.to_le_bytes())
    }
    b[16..24].copy_from_slice(b"BCINTENT");
    b[32..64].copy_from_slice(generation);
    authority::refreshed(&b, sequence, mode)
}
fn android_slot(b: &[u8]) -> Result<u32> {
    let s = std::str::from_utf8(b).map_err(|_| "bootconfig encoding")?;
    let mut found = Vec::new();
    for line in s.lines() {
        if let Some((key, value)) = line.split_once('=') {
            if key.trim() == "androidboot.slot_suffix" {
                let value = value.trim();
                let v = if value.starts_with('"') && value.ends_with('"') && value.len() >= 2 {
                    &value[1..value.len() - 1]
                } else {
                    value
                };
                found.push(match v {
                    "_a" => 1,
                    "_b" => 2,
                    _ => return Err("invalid actual boot slot".into()),
                })
            }
        }
    }
    check(found.len() == 1, "unique actual bootconfig slot required")?;
    Ok(found[0])
}
fn guid(b: &[u8]) -> String {
    format!(
        "{:08x}-{:04x}-{:04x}-{}-{}",
        u32::from_le_bytes(b[..4].try_into().unwrap()),
        u16::from_le_bytes(b[4..6].try_into().unwrap()),
        u16::from_le_bytes(b[6..8].try_into().unwrap()),
        hex(&b[8..10]),
        hex(&b[10..16])
    )
}
fn loader_uuid(b: &[u8]) -> Result<String> {
    check(
        b.len() == 78 && le32(b, 0) == 6,
        "LoaderDevicePartUUID attributes/size",
    )?;
    let values: Vec<u16> = b[4..]
        .chunks_exact(2)
        .map(|v| u16::from_le_bytes(v.try_into().unwrap()))
        .collect();
    check(
        values[36] == 0 && values[..36].iter().all(|v| *v != 0),
        "loader UUID framing",
    )?;
    let uuid = String::from_utf16(&values[..36]).map_err(|_| "loader UUID encoding")?;
    check(
        uuid.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        }),
        "loader UUID syntax",
    )?;
    Ok(uuid.to_ascii_lowercase())
}
#[derive(PartialEq, Eq)]
struct Esp {
    member: usize,
    first: u64,
    last: u64,
    uuid: String,
}
fn esp(group: &mut Group) -> Result<Esp> {
    use authority::{DiskGroup, ReadDisk};
    const TYPE: [u8; 16] = [
        0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11, 0xba, 0x4b, 0, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b,
    ];
    let mut found = None;
    for index in 0..group.members.len() {
        let (mut d, block, last) = group.select(index).map_err(str::to_owned)?;
        let mut header = vec![0; block];
        d.read(1, &mut header).map_err(str::to_owned)?;
        if &header[..8] != b"EFI PART" {
            continue;
        }
        // The production group inspector has already checked both GPTs, CRCs,
        // GUID uniqueness and all extents. Bound this second lookup as well.
        let count = le32(&header, 80) as usize;
        check(
            (1..=1024).contains(&count) && le32(&header, 84) == 128,
            "ESP table geometry",
        )?;
        let mut entries = vec![0; (count * 128).div_ceil(block) * block];
        d.read(le64(&header, 72), &mut entries)
            .map_err(str::to_owned)?;
        for e in entries[..count * 128].chunks_exact(128) {
            if e[..16] == TYPE {
                check(
                    le64(e, 32) > 1
                        && le64(e, 32) <= le64(e, 40)
                        && le64(e, 40) < last
                        && e[16..32].iter().any(|v| *v != 0),
                    "ESP extent/GUID",
                )?;
                check(found.is_none(), "unique ESP required")?;
                found = Some(Esp {
                    member: index,
                    first: le64(e, 32),
                    last: le64(e, 40),
                    uuid: guid(&e[16..32]),
                })
            }
        }
    }
    found.ok_or_else(|| "missing same-controller ESP".into())
}
fn esp_mount(group: &Group, esp: &Esp) -> Result<Option<String>> {
    let m = &group.members[esp.member];
    let mut found = None;
    for entry in fs::read_dir(&m.sys).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let p = entry.path();
        if !p.join("partition").exists() {
            continue;
        }
        let start: u64 = text(&p.join("start"))?
            .trim()
            .parse()
            .map_err(|_| "partition start")?;
        let sectors: u64 = text(&p.join("size"))?
            .trim()
            .parse()
            .map_err(|_| "partition size")?;
        if start.checked_mul(512) == esp.first.checked_mul(m.block as u64)
            && sectors.checked_mul(512) == (esp.last - esp.first + 1).checked_mul(m.block as u64)
        {
            check(found.is_none(), "ambiguous ESP kernel partition")?;
            let expected = dev(&p)?;
            let name = entry.file_name().into_string().map_err(|_| "ESP name")?;
            let fd = open_block(&name, expected)?;
            check(
                geometry(&fd)?.1 == (esp.last - esp.first + 1) * m.block as u64,
                "ESP partition descriptor extent",
            )?;
            let id = format!("{}:{}", libc::major(expected), libc::minor(expected));
            let mounts = text(Path::new("/proc/self/mountinfo"))?;
            let mut matches = Vec::new();
            for line in mounts.lines() {
                let v: Vec<_> = line.split_whitespace().collect();
                if v.get(2) == Some(&id.as_str()) {
                    let sep = v
                        .iter()
                        .position(|s| *s == "-")
                        .ok_or("mountinfo separator")?;
                    check(
                        v.get(3) == Some(&"/")
                            && v.get(sep + 1) == Some(&"vfat")
                            && v.get(4).is_some_and(|s| !s.contains('\\')),
                        "actual ESP FAT root mount required",
                    )?;
                    matches.push(v[4].to_string())
                }
            }
            check(matches.len() <= 1, "ambiguous ESP mounts")?;
            found = Some(matches.pop());
        }
    }
    found.ok_or_else(|| "missing exact ESP kernel partition".into())
}
#[derive(Serialize)]
pub struct Status {
    pub source: String,
    pub slot: u32,
    pub controller: String,
    pub boot_lun: u32,
    pub target_partuuid: String,
    pub generation: String,
    pub sequence: u64,
    pub preference: String,
    pub esp_partuuid: String,
    pub esp_mount: Option<String>,
    pub image_sha256: String,
    pub write_authority: bool,
    pub journal_checked: bool,
}
pub fn inspect() -> Result<Status> {
    check(
        unsafe { libc::geteuid() } == 0,
        "root status inspection required",
    )?;
    let efi = Path::new("/sys/firmware/efi").is_dir();
    let board = Board::read(efi)?;
    let source_path = if efi {
        PathBuf::from(format!(
            "/sys/firmware/efi/efivars/{}-{}",
            provenance::NAME,
            provenance::GUID
        ))
    } else {
        PathBuf::from("/proc/bootconfig")
    };
    let source = small(&source_path, 1024 * 1024)?;
    let (mut ctx, loader) = if efi {
        provenance::decode(&source)?;
        let p = PathBuf::from(
            "/sys/firmware/efi/efivars/LoaderDevicePartUUID-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f",
        );
        let bytes = small(&p, 256)?;
        (
            <[u8; 96]>::try_from(&source[4..]).map_err(|_| "context length")?,
            Some((p, bytes)),
        )
    } else {
        let init = small(Path::new("/proc/1/cmdline"), 4096)?;
        check(
            matches!(
                init.split(|b| *b == 0).next(),
                Some(b"/init" | b"/system/bin/init")
            ),
            "missing Android init identity; no Linux fallback",
        )?;
        (context_for(android_slot(&source)?, &[1; 32], 1, 1), None)
    };
    let mut group = Group::acquire()?;
    let count = group.members.len();
    let target = authority::inspect_group(&mut group, &ctx, count).map_err(str::to_owned)?;
    let image = Image::verify(&target.image).map_err(str::to_owned)?;
    check(
        image.layout_flag == 3,
        "live status requires runnable owned image",
    )?;
    if !efi {
        ctx = context_for(
            context::decode(&ctx).map_err(str::to_owned)?.slot,
            &image.generation,
            image.sequence,
            image.mode,
        )
    }
    target.verify(&ctx).map_err(str::to_owned)?;
    let selected = esp(&mut group)?;
    let mount = esp_mount(&group, &selected)?;
    if let Some((p, b)) = &loader {
        check(
            loader_uuid(b)? == selected.uuid && mount.is_some(),
            "actual loaded ESP disagrees/missing mount",
        )?;
        check(small(p, 256)? == *b, "loader ESP changed")?
    }
    check(
        small(&source_path, 1024 * 1024)? == source && Board::read(efi)? == board,
        "booted source changed",
    )?;
    group.recheck()?;
    let again = authority::inspect_group(&mut group, &ctx, count).map_err(str::to_owned)?;
    check(
        again.index == target.index
            && again.lba == target.lba
            && again.part_guid == target.part_guid
            && again.disk_guid == target.disk_guid
            && hash(&again.image) == hash(&target.image)
            && esp(&mut group)? == selected,
        "target/GPT/ESP changed during inspection",
    )?;
    Ok(Status {
        source: if efi {
            "volatile-efi"
        } else {
            "android-bootconfig"
        }
        .into(),
        slot: context::decode(&ctx).map_err(str::to_owned)?.slot,
        controller: group.controller.display().to_string(),
        boot_lun: group.members[target.index].lun,
        target_partuuid: guid(&target.part_guid),
        generation: hex(&image.generation),
        sequence: image.sequence,
        preference: if image.mode == 1 { "nixos" } else { "android" }.into(),
        esp_partuuid: selected.uuid,
        esp_mount: mount,
        image_sha256: hex(&hash(&target.image)),
        write_authority: false,
        journal_checked: false,
    })
}
#[cfg(test)]
mod tests {
    #[test]
    fn board_identity_is_os_specific_and_exact() {
        use super::{Board, block_node_root};
        assert_eq!(block_node_root(true), "/dev");
        assert_eq!(block_node_root(false), "/dev/block");
        let android = b"Qualcomm Technologies, Inc. Sun MTP,dodge\0";
        let linux = b"OnePlus 13\0";
        let compatible = b"oneplus,dodge\0qcom,sm8750\0";
        assert!(Board::validate(false, android, None).is_ok());
        assert!(Board::validate(true, linux, Some(compatible)).is_ok());
        assert!(Board::validate(false, linux, None).is_err());
        assert!(Board::validate(true, android, Some(compatible)).is_err());
        assert!(Board::validate(true, linux, None).is_err());
        for bad in [b"oneplus,dodge\0".as_slice(), b"qcom,sm8750\0",
                    b"oneplus,other\0qcom,sm8750\0", b"qcom,sm8750\0oneplus,dodge\0",
                    b"oneplus,dodge\0qcom,sm8750", b"oneplus,dodge\0qcom,sm8750\0extra\0"] {
            assert!(Board::validate(true, linux, Some(bad)).is_err());
        }
        assert!(Board::validate(true, b"OnePlus 13", Some(compatible)).is_err());
        assert!(Board::validate(false, android, Some(compatible)).is_err());
    }
    use super::*;
    #[test]
    fn strict_sources() {
        for (s, slot) in [
            ("androidboot.slot_suffix = \"_a\"\n", 1),
            ("androidboot.slot_suffix=_b\n", 2),
        ] {
            assert_eq!(android_slot(s.as_bytes()).unwrap(), slot)
        }
        for s in [
            "",
            "androidboot.slot_suffix=_c",
            "androidboot.slot_suffix=_a\nandroidboot.slot_suffix=\"_a\"",
            "androidboot.slot_suffix=\"_a",
            "alias.androidboot.slot_suffix=_a",
        ] {
            assert!(android_slot(s.as_bytes()).is_err())
        }
        let b = context_for(2, &[3; 32], 17, 0);
        let c = context::decode(&b).unwrap();
        assert_eq!((c.slot, c.sequence, c.stored, c.selected), (2, 17, 0, 0));
        let uuid = "00112233-4455-6677-8899-aabbccddeeff";
        let mut b = 6u32.to_le_bytes().to_vec();
        for c in uuid.encode_utf16().chain([0]) {
            b.extend_from_slice(&c.to_le_bytes())
        }
        assert_eq!(loader_uuid(&b).unwrap(), uuid);
        let mut upper=b.clone();
        for pair in upper[4..76].chunks_exact_mut(2) { pair[0]=pair[0].to_ascii_uppercase(); }
        assert_eq!(loader_uuid(&upper).unwrap(), uuid);
        b[0] = 7;
        assert!(loader_uuid(&b).is_err());
        b[0] = 6;
        b.pop();
        assert!(loader_uuid(&b).is_err());
    }
}

#[path = "live_owner.rs"]
pub mod owner;

#[cfg(test)]
mod direct_alias_tests {
    use super::*;
    use authority::ReadDisk;
    use std::process::Command;
    #[test]
    #[ignore = "root-only isolated loop parent/partition cache alias regression"]
    fn parent_partition_alias_uses_fresh_authority_and_offsets() {
        assert_eq!(unsafe { libc::geteuid() }, 0);
        let (_, old) = crate::install_transaction::tests::fixture();
        let v = Image::verify(&old).unwrap();
        let mut body = old[..v.body].to_vec();
        let pages = 32768;
        let payload = pages + 8192 + 65536;
        let meta = v.body - 4096;
        body[v.pages..v.pages + 8192].fill(0);
        body[pages..pages + 8192].fill(0);
        body[pages..pages + 4096].copy_from_slice(&crate::format::record(&[8; 32], 2, 1));
        body[4100..4104].copy_from_slice(
            &(0x14000000u32 | ((pages + 8192 - 4096 - 4) / 4) as u32).to_le_bytes(),
        );
        for (at, n) in [
            (40, pages),
            (48, pages + 8192),
            (56, payload),
            (64, payload),
            (72, payload + 4096),
            (80, payload + 4096),
        ] {
            body[meta + at..meta + at + 8].copy_from_slice(&(n as u64).to_le_bytes());
        }
        body[meta + 128..meta + 160].copy_from_slice(&[8; 32]);
        body[meta + 192..meta + 224].fill(0);
        let mut norm = body.clone();
        norm[pages..pages + 8192].fill(0);
        body[meta + 192..meta + 224].copy_from_slice(&hash(&norm));
        let new = crate::avb::seal(&body, old.len()).unwrap();
        let next = Image::verify(&new).unwrap();
        assert_eq!(next.pages, pages);
        let path = std::env::temp_dir().join(format!("bc-loop-alias-{}.img", std::process::id()));
        let offset = 1024 * 1024usize;
        let mut bytes = vec![0; offset + old.len()];
        bytes[offset..].copy_from_slice(&old);
        bytes[446 + 4] = 0x83;
        bytes[446 + 8..446 + 12].copy_from_slice(&2048u32.to_le_bytes());
        bytes[446 + 12..446 + 16].copy_from_slice(&((old.len() / 512) as u32).to_le_bytes());
        bytes[510..512].copy_from_slice(&[0x55, 0xaa]);
        let mut backing = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
            .unwrap();
        std::io::Write::write_all(&mut backing, &bytes).unwrap();
        backing.sync_all().unwrap();
        let output = Command::new("losetup")
            .args(["--find", "--show", "--partscan"])
            .arg(&path)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let device = String::from_utf8(output.stdout).unwrap().trim().to_owned();
        assert!(device.starts_with("/dev/loop"));
        struct Loop {
            device: String,
            path: PathBuf,
        }
        impl Drop for Loop {
            fn drop(&mut self) {
                let _ = Command::new("losetup")
                    .args(["--detach", &self.device])
                    .status();
                let _ = fs::remove_file(&self.path);
            }
        }
        let _guard = Loop {
            device: device.clone(),
            path,
        };
        let leaf = format!("{device}p1");
        for _ in 0..40 {
            if Path::new(&leaf).exists() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        let cached = File::open(&device).unwrap();
        let mut before = vec![0; old.len()];
        cached.read_exact_at(&mut before, offset as u64).unwrap();
        assert_eq!(before, old);
        // Historical writer updated a partition mapping. Cache alias repro.
        let writer = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&leaf)
            .unwrap();
        writer.write_all_at(&new, 0).unwrap();
        writer.sync_all().unwrap();
        let mut stale = vec![0; old.len()];
        cached.read_exact_at(&mut stale, offset as u64).unwrap();
        assert_eq!(stale, old, "kernel did not reproduce alias");
        let context = context_for(1, &[7; 32], 1, 1);
        let mut target = authority::Target {
            index: 0,
            block: 512,
            lba: 2048,
            disk_guid: [1; 16],
            part_guid: [2; 16],
            image: stale,
        };
        target.verify(&context).unwrap(); // Negative control accepts stale state.
        let direct = OpenOptions::new()
            .read(true)
            .custom_flags(crate::media::FLAGS)
            .open(&device)
            .unwrap();
        let mut disk = Disk {
            file: direct,
            block: 512,
            last: ((offset + new.len()) / 512 - 1) as u64,
        };
        disk.read(2048, &mut target.image).unwrap();
        assert_eq!(target.image, new);
        assert!(
            target.verify(&context).is_err(),
            "stale Linux runtime must refuse before mutation"
        );
        target.verify(&context_for(1, &[8; 32], 2, 1)).unwrap();
        let planned = Image::request(&target.image, &[8; 32], 2, 0).unwrap();
        let p = Image::verify(&planned).unwrap();
        assert_eq!((p.pages, p.sequence, p.mode), (pages, 3, 0));
        // Reverse alias: prime leaf, write parent using the production direct
        // transport; fresh leaf read MUST also see new physical bytes.
        let leaf_buffered = File::open(&leaf).unwrap();
        let mut prime = vec![0; new.len()];
        leaf_buffered.read_exact_at(&mut prime, 0).unwrap();
        let parent = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(crate::media::FLAGS)
            .open(&device)
            .unwrap();
        assert_eq!(
            crate::media::write_at(&parent, &old, offset as u64).unwrap(),
            old.len()
        );
        parent.sync_all().unwrap();
        let mut stale_leaf = vec![0; new.len()];
        leaf_buffered.read_exact_at(&mut stale_leaf, 0).unwrap();
        assert_eq!(stale_leaf, new, "reverse cache alias did not reproduce");
        let leaf_direct = OpenOptions::new()
            .read(true)
            .custom_flags(crate::media::FLAGS)
            .open(&leaf)
            .unwrap();
        crate::media::read_at(&leaf_direct, &mut prime, 0).unwrap();
        assert_eq!(prime, old);
        let mut observed = new.clone();
        let mut wrote = false;
        assert!(owner::checked_page(
            &leaf_direct,
            &mut observed,
            pages,
            &old[pages..pages + 4096],
            |_, _, _| {
                wrote = true;
                Ok(4096)
            }
        )
        .is_err());
        assert!(!wrote,"fresh production pre-write check must reject an external parent update before mutation");

        println!("actual loop cached-parent/updated-leaf reproduced; production direct authority sees generation8/new offsets; stale generation7 refuses; reverse alias fresh too");
    }
}
