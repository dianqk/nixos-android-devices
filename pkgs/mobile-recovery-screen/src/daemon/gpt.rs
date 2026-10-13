//! Strict GPT support. A/B planning and writes use 4 KiB sectors only; read-only
//! resolution also accepts 512-byte eMMC sectors. Preserve OEM placement,
//! padding and unrelated entries.
use anyhow::{ensure, Context, Result};
use serde::{Deserialize, Serialize};
use std::{fs::File, os::unix::fs::FileExt};

pub const SECTOR: u64 = 4096;
/// Logical sector sizes accepted by read-only single-slot resolution.
pub const READ_SECTORS: [u64; 2] = [512, 4096];
fn default_sector() -> u64 {
    SECTOR
}
pub const LINUX: &str = "0fc63daf-8483-4772-8e79-3d69d8477de4";
pub const ESP: &str = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
pub const ANDROID: &str = "1b81e7e6-f50d-419b-a739-2aeef8da3335";

fn u32_at(b: &[u8], n: usize) -> u32 {
    u32::from_le_bytes(b[n..n + 4].try_into().unwrap())
}
fn u64_at(b: &[u8], n: usize) -> u64 {
    u64::from_le_bytes(b[n..n + 8].try_into().unwrap())
}
fn crc(b: &[u8]) -> u32 {
    let mut v = !0u32;
    for byte in b {
        v ^= u32::from(*byte);
        for _ in 0..8 {
            v = (v >> 1) ^ (0xedb88320u32 & (0u32.wrapping_sub(v & 1)));
        }
    }
    !v
}
fn read_at(f: &File, off: u64, size: usize) -> Result<Vec<u8>> {
    let mut b = vec![0; size];
    f.read_exact_at(&mut b, off).context("short disk read")?;
    Ok(b)
}
fn guid(b: &[u8]) -> String {
    format!(
        "{:08x}-{:04x}-{:04x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        u32_at(b, 0),
        u16::from_le_bytes([b[4], b[5]]),
        u16::from_le_bytes([b[6], b[7]]),
        b[8],
        b[9],
        b[10],
        b[11],
        b[12],
        b[13],
        b[14],
        b[15]
    )
}
fn guid_bytes(s: &str) -> Result<[u8; 16]> {
    ensure!(
        s.len() == 36 && [8, 13, 18, 23].iter().all(|i| s.as_bytes()[*i] == b'-'),
        "invalid GUID"
    );
    let hex: String = s.chars().filter(|c| *c != '-').collect();
    ensure!(hex.len() == 32 && hex.is_ascii(), "invalid GUID");
    let mut b = [0; 16];
    for i in 0..16 {
        b[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16)?;
    }
    b[..4].reverse();
    b[4..6].reverse();
    b[6..8].reverse();
    Ok(b)
}
fn new_guid() -> Result<String> {
    let mut b = [0u8; 16];
    let mut off = 0;
    while off < b.len() {
        let n = unsafe { libc::getrandom(b[off..].as_mut_ptr().cast(), b.len() - off, 0) };
        if n < 0 {
            return Err(std::io::Error::last_os_error().into());
        }
        ensure!(n > 0, "short random read");
        off += n as usize;
    }
    b[7] = (b[7] & 15) | 0x40;
    b[8] = (b[8] & 63) | 0x80;
    Ok(guid(&b))
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Partition {
    pub number: usize,
    pub name: String,
    pub start: u64,
    pub end: u64,
    pub kind: String,
    pub uuid: String,
    pub attributes: u64,
    /// Logical sector size of the containing disk; not part of the JSON plan.
    #[serde(skip, default = "default_sector")]
    pub sector: u64,
}
impl Partition {
    pub fn bytes(&self) -> u64 {
        (self.end - self.start + 1) * self.sector
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Header {
    raw: Vec<u8>,
    lba: u64,
    table: u64,
    first: u64,
    last: u64,
    id: Vec<u8>,
    count: usize,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Gpt {
    headers: Vec<Header>,
    tables: Vec<Vec<u8>>,
    pub partitions: Vec<Partition>,
    pub disk_bytes: u64,
    pub sector: u64,
}
impl Gpt {
    pub fn last_usable(&self) -> u64 {
        self.headers[0].last
    }
    pub fn read(f: &File, disk_bytes: u64) -> Result<Self> {
        Self::read_mode(f, disk_bytes, false, SECTOR)
    }
    /// Read-only resolution on a disk with the given logical sector size.
    pub fn read_sector(f: &File, disk_bytes: u64, sector: u64) -> Result<Self> {
        ensure!(
            READ_SECTORS.contains(&sector),
            "unsupported logical sector size"
        );
        Self::read_mode(f, disk_bytes, false, sector)
    }
    /// Explicit repair planning only; normal operations always require both copies.
    pub fn read_for_backup_repair(f: &File, disk_bytes: u64) -> Result<Self> {
        Self::read_mode(f, disk_bytes, true, SECTOR)
    }
    fn read_mode(f: &File, disk_bytes: u64, repair: bool, sector: u64) -> Result<Self> {
        ensure!(
            disk_bytes.is_multiple_of(sector) && disk_bytes >= 16 * sector,
            "invalid disk capacity"
        );
        let blocks = disk_bytes / sector;
        let mbr = read_at(f, 0, 512)?;
        ensure!(
            mbr[510..512] == [0x55, 0xaa]
                && mbr[450] == 0xee
                && u32_at(&mbr, 454) == 1
                && mbr[462..510].iter().all(|b| *b == 0),
            "expected protective MBR without hybrid entries"
        );
        let mut headers = Vec::new();
        let mut tables = Vec::new();
        for (lba, other) in [(1, blocks - 1), (blocks - 1, 1)] {
            let h = read_at(f, lba * sector, sector as usize)?;
            ensure!(
                &h[..8] == b"EFI PART"
                    && u32_at(&h, 8) == 0x10000
                    && u32_at(&h, 12) == 92
                    && u32_at(&h, 20) == 0,
                "unsupported GPT header"
            );
            ensure!(
                u64_at(&h, 24) == lba && u64_at(&h, 32) == other,
                "GPT is not at both disk ends"
            );
            let mut check = h[..92].to_vec();
            check[16..20].fill(0);
            ensure!(crc(&check) == u32_at(&h, 16), "GPT header CRC mismatch");
            let count = u32_at(&h, 80) as usize;
            ensure!(
                (2..=4096).contains(&count) && u32_at(&h, 84) == 128,
                "unsupported GPT entry array"
            );
            let sectors = (count as u64 * 128).div_ceil(sector);
            let (table, first, last) = (u64_at(&h, 72), u64_at(&h, 40), u64_at(&h, 48));
            ensure!(
                first <= last && last < blocks - sectors - 1,
                "invalid usable range"
            );
            ensure!(
                if lba == 1 {
                    table == 2 && table + sectors <= first
                } else {
                    table > last && table <= lba - sectors
                },
                "unsafe GPT array placement"
            );
            let t = read_at(f, table * sector, (sectors * sector) as usize)?;
            ensure!(
                (repair && lba == blocks - 1) || crc(&t[..count * 128]) == u32_at(&h, 88),
                "GPT entries CRC mismatch"
            );
            headers.push(Header {
                lba,
                table,
                first,
                last,
                id: h[56..72].to_vec(),
                count,
                raw: h,
            });
            tables.push(t);
        }
        let a = &headers[0];
        let b = &headers[1];
        ensure!(
            a.first == b.first && a.last == b.last && a.id == b.id && a.count == b.count,
            "primary/backup geometry differs"
        );
        ensure!(
            repair || tables[0][..a.count * 128] == tables[1][..a.count * 128],
            "primary/backup entries differ"
        );
        let mut partitions = Vec::new();
        for (i, raw) in tables[0][..a.count * 128]
            .as_chunks::<128>()
            .0
            .iter()
            .enumerate()
        {
            if raw[..16] == [0; 16] {
                // The zero type GUID denotes an unused entry. OEM firmware can
                // retain a UUID, attributes and even an empty/reversed range
                // (last_parti). Preserve these bytes and do not allocate them.
                // UEFI 2.10 section 5.3.3, table 5.7.
                continue;
            }
            let words: Vec<u16> = raw[56..]
                .as_chunks::<2>()
                .0
                .iter()
                .map(|b| u16::from_le_bytes([b[0], b[1]]))
                .collect();
            let name = String::from_utf16(&words)?
                .trim_end_matches('\0')
                .to_owned();
            ensure!(
                !name.is_empty() && !name.contains('\0'),
                "invalid partition name"
            );
            let p = Partition {
                number: i + 1,
                name,
                start: u64_at(raw, 32),
                end: u64_at(raw, 40),
                kind: guid(&raw[..16]),
                uuid: guid(&raw[16..32]),
                attributes: u64_at(raw, 48),
                sector,
            };
            ensure!(
                p.start >= a.first && p.start <= p.end && p.end <= a.last,
                "partition outside usable range"
            );
            ensure!(
                raw[16..32] != [0; 16]
                    && !partitions.iter().any(|old: &Partition| old.name == p.name
                        || old.uuid == p.uuid
                        || (old.start <= p.end && p.start <= old.end)),
                "duplicate or overlapping partitions"
            );
            partitions.push(p);
        }
        let g = Self {
            headers,
            tables,
            partitions,
            disk_bytes,
            sector,
        };
        if repair {
            g.check_backup_repair_scope()?;
        }
        Ok(g)
    }
    fn check_backup_repair_scope(&self) -> Result<()> {
        // A stale Qualcomm slot update can differ only in A/B type GUIDs and
        // slot attributes. Never infer layout, names or partition UUIDs.
        for (i, (a, b)) in self.tables[0][..self.headers[0].count * 128]
            .as_chunks::<128>()
            .0
            .iter()
            .zip(self.tables[1].as_chunks::<128>().0.iter())
            .enumerate()
        {
            if a == b {
                continue;
            }
            let p = self
                .partitions
                .iter()
                .find(|p| p.number == i + 1)
                .context("backup differs in an unused entry")?;
            let (base, other) = if let Some(base) = p.name.strip_suffix("_a") {
                (base, "_b")
            } else if let Some(base) = p.name.strip_suffix("_b") {
                (base, "_a")
            } else {
                anyhow::bail!("backup differs outside an A/B entry");
            };
            let peer = self.partition(&format!("{base}{other}"))?;
            let pa = &self.tables[0][(peer.number - 1) * 128..peer.number * 128];
            let pb = &self.tables[1][(peer.number - 1) * 128..peer.number * 128];
            ensure!(
                a[16..48] == b[16..48] && a[56..] == b[56..],
                "backup partition identity or geometry differs"
            );
            ensure!(
                (u64_at(a, 48) ^ u64_at(b, 48)) & !(0xffu64 << 48) == 0,
                "backup differs in non-slot attributes"
            );
            ensure!(
                a[..16] == b[..16] || (a[..16] == pb[..16] && b[..16] == pa[..16]),
                "backup type GUIDs are not a paired slot swap"
            );
        }
        Ok(())
    }
    pub fn backup_needs_repair(&self) -> bool {
        self.tables[0][..self.headers[0].count * 128]
            != self.tables[1][..self.headers[1].count * 128]
            || crc(&self.tables[1][..self.headers[1].count * 128])
                != u32_at(&self.headers[1].raw, 88)
    }
    pub fn repair_backup(&self, f: &File) -> Result<()> {
        ensure!(
            self.sector == SECTOR,
            "backup repair supports 4 KiB GPT only"
        );
        ensure!(
            Self::read_for_backup_repair(f, self.disk_bytes)? == *self,
            "GPT changed after repair planning"
        );
        if !self.backup_needs_repair() {
            return Ok(());
        }
        // regions emits backup first. Preserve placement and padding; never write primary.
        for (offset, data) in self.regions(&self.partitions)?.into_iter().take(2) {
            f.write_all_at(&data, offset)?;
            f.sync_all()?;
            ensure!(
                read_at(f, offset, data.len())? == data,
                "backup GPT write readback differs"
            );
        }
        let after = Self::read(f, self.disk_bytes)?;
        ensure!(
            after.headers[0] == self.headers[0]
                && after.tables[0] == self.tables[0]
                && after.partitions == self.partitions,
            "primary GPT changed during backup repair"
        );
        Ok(())
    }
    pub fn partition(&self, name: &str) -> Result<&Partition> {
        self.partitions
            .iter()
            .find(|p| p.name == name)
            .with_context(|| format!("missing {name}"))
    }
    pub fn selected_b(&self) -> Result<()> {
        let a = self.partition("boot_a")?.attributes;
        let b = self.partition("boot_b")?.attributes;
        ensure!(
            a & (1 << 50) == 0 && b & (1 << 50) != 0,
            "GPT does not exclusively select B"
        );
        ensure!(
            b & (3 << 48) != 0 && b & (1 << 55) == 0,
            "B is unbootable or has zero priority"
        );
        ensure!(
            b & ((7 << 51) | (1 << 54)) != 0,
            "B has no retry/success flag"
        );
        Ok(())
    }
    /// Accept existing installations in either root/ESP order, including alignment gaps.
    pub fn check_linux_layout(&self, esp_bytes: u64, minimum_root: u64) -> Result<()> {
        self.partition("super")?;
        let user = self.partition("userdata")?;
        let root = self.partition("linux")?;
        let esp = self.partition("linux-boot")?;
        ensure!(
            root.kind == LINUX && esp.kind == ESP && [ANDROID, LINUX].contains(&user.kind.as_str()),
            "unexpected partition types"
        );
        ensure!(
            (esp_bytes == 0 || esp.bytes() == esp_bytes) && root.bytes() >= minimum_root,
            "invalid Linux/ESP sizes"
        );
        ensure!(
            user.end < root.start && user.end < esp.start,
            "Linux partitions must follow userdata"
        );
        ensure!(
            self.partitions
                .iter()
                .all(
                    |p| ["userdata", "linux-boot", "linux"].contains(&p.name.as_str())
                        || p.end < user.start
                ),
            "other partitions follow userdata"
        );
        Ok(())
    }
    pub fn split(&self, esp_bytes: u64, minimum_root: u64) -> Result<Vec<Partition>> {
        ensure!(
            self.sector == SECTOR,
            "partition planning supports 4 KiB GPT only"
        );
        let esp_bytes = if esp_bytes == 0 { 1 << 30 } else { esp_bytes };
        self.partition("super")?;
        ensure!(
            !self
                .partitions
                .iter()
                .any(|p| p.name == "linux" || p.name == "linux-boot"),
            "Linux partitions already exist"
        );
        let user = self.partition("userdata")?;
        ensure!(
            [ANDROID, LINUX].contains(&user.kind.as_str()) && user.attributes == 0,
            "unexpected userdata type/attributes"
        );
        ensure!(
            user.end == self.headers[0].last
                && self
                    .partitions
                    .iter()
                    .all(|p| p == user || p.end < user.start),
            "userdata must be the last allocation"
        );
        ensure!(
            esp_bytes > 0 && esp_bytes % (1 << 20) == 0 && esp_bytes < self.disk_bytes,
            "invalid ESP size"
        );
        let free: Vec<usize> = (1..=self.headers[0].count)
            .filter(|n| {
                self.tables[0][(n - 1) * 128..n * 128]
                    .iter()
                    .all(|b| *b == 0)
            })
            .take(2)
            .collect();
        ensure!(free.len() == 2, "no two free GPT entries");
        let boundary = (user.start + (user.end + 1 - user.start) / 2) / 256 * 256;
        ensure!(
            boundary >= user.start + (16 << 30) / SECTOR,
            "Android half is too small"
        );
        let root_start = boundary + esp_bytes / SECTOR;
        ensure!(
            root_start <= user.end && (user.end + 1 - root_start) * SECTOR >= minimum_root,
            "Linux half is too small"
        );
        let mut parts = self.partitions.clone();
        parts.iter_mut().find(|p| p.name == "userdata").unwrap().end = boundary - 1;
        for (number, name, start, end, kind) in [
            (free[0], "linux-boot", boundary, root_start - 1, ESP),
            (free[1], "linux", root_start, user.end, LINUX),
        ] {
            parts.push(Partition {
                number,
                name: name.into(),
                start,
                end,
                kind: kind.into(),
                uuid: new_guid()?,
                attributes: 0,
                sector: SECTOR,
            });
        }
        parts.sort_by_key(|p| p.number);
        Ok(parts)
    }
    pub fn regions(&self, parts: &[Partition]) -> Result<Vec<(u64, Vec<u8>)>> {
        ensure!(
            self.sector == SECTOR,
            "GPT writes support 4 KiB sectors only"
        );
        let mut table = self.tables[0].clone();
        for p in parts {
            if self.partitions.iter().any(|old| old == p) {
                continue;
            }
            ensure!(
                p.number > 0 && p.number <= self.headers[0].count,
                "entry outside GPT"
            );
            let raw = &mut table[(p.number - 1) * 128..p.number * 128];
            raw.fill(0);
            raw[..16].copy_from_slice(&guid_bytes(&p.kind)?);
            raw[16..32].copy_from_slice(&guid_bytes(&p.uuid)?);
            raw[32..40].copy_from_slice(&p.start.to_le_bytes());
            raw[40..48].copy_from_slice(&p.end.to_le_bytes());
            raw[48..56].copy_from_slice(&p.attributes.to_le_bytes());
            let words: Vec<u16> = p.name.encode_utf16().collect();
            ensure!(words.len() <= 36, "name too long");
            for (i, w) in words.iter().enumerate() {
                raw[56 + i * 2..58 + i * 2].copy_from_slice(&w.to_le_bytes());
            }
        }
        let mut result = Vec::new();
        for (h, old) in self.headers.iter().zip(&self.tables).rev() {
            let mut data = old.clone();
            data[..h.count * 128].copy_from_slice(&table[..h.count * 128]);
            let mut header = h.raw.clone();
            header[88..92].copy_from_slice(&crc(&data[..h.count * 128]).to_le_bytes());
            header[16..20].fill(0);
            let c = crc(&header[..92]);
            header[16..20].copy_from_slice(&c.to_le_bytes());
            result.push((h.table * SECTOR, data));
            result.push((h.lba * SECTOR, header));
        }
        Ok(result)
    }
    pub fn write_split(&self, f: &File, parts: &[Partition]) -> Result<()> {
        ensure!(
            Self::read(f, self.disk_bytes)? == *self,
            "GPT changed after planning"
        );
        for (offset, data) in self.regions(parts)? {
            f.write_all_at(&data, offset)?;
            f.sync_all()?;
        }
        ensure!(
            Self::read(f, self.disk_bytes)?.partitions == parts,
            "GPT readback differs; do not reboot"
        );
        Ok(())
    }
    pub fn snapshot(&self, directory: &std::path::Path) -> Result<()> {
        std::fs::create_dir(directory)?;
        for (h, t) in self.headers.iter().zip(&self.tables) {
            std::fs::write(directory.join(format!("header-{}", h.lba)), &h.raw)?;
            std::fs::write(directory.join(format!("table-{}", h.table)), t)?;
        }
        Ok(())
    }
}
/// Test-only GPT disk image writer shared by storage resolution tests.
#[cfg(test)]
pub(crate) fn write_test_disk(
    path: &std::path::Path,
    sector: u64,
    blocks: u64,
    entries: &[(&str, u64, u64, &str, &str)],
) {
    use std::fs::OpenOptions;
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)
        .unwrap();
    file.set_len(blocks * sector).unwrap();
    let mut mbr = [0; 512];
    mbr[450] = 0xee;
    mbr[454..458].copy_from_slice(&1u32.to_le_bytes());
    mbr[458..462].fill(0xff);
    mbr[510..].copy_from_slice(&[0x55, 0xaa]);
    file.write_all_at(&mbr, 0).unwrap();
    let count = 128u64;
    let sectors = (count * 128).div_ceil(sector);
    let mut table = vec![0u8; (sectors * sector) as usize];
    for (i, (name, start, end, kind, uuid)) in entries.iter().enumerate() {
        let entry = &mut table[i * 128..(i + 1) * 128];
        entry[..16].copy_from_slice(&guid_bytes(kind).unwrap());
        entry[16..32].copy_from_slice(&guid_bytes(uuid).unwrap());
        entry[32..40].copy_from_slice(&start.to_le_bytes());
        entry[40..48].copy_from_slice(&end.to_le_bytes());
        for (i, w) in name.encode_utf16().enumerate() {
            entry[56 + i * 2..58 + i * 2].copy_from_slice(&w.to_le_bytes());
        }
    }
    let first = 2 + sectors;
    let last = blocks - sectors - 2;
    let id = guid_bytes("6d1a1d4e-1c1b-4f6a-9d1e-0123456789ab").unwrap();
    let entries_crc = crc(&table[..(count * 128) as usize]);
    for (lba, other, array) in [(1, blocks - 1, 2), (blocks - 1, 1, blocks - 1 - sectors)] {
        let mut h = vec![0; sector as usize];
        h[..8].copy_from_slice(b"EFI PART");
        for (off, v) in [
            (8, 0x10000u32),
            (12, 92),
            (80, count as u32),
            (84, 128),
            (88, entries_crc),
        ] {
            h[off..off + 4].copy_from_slice(&v.to_le_bytes());
        }
        for (off, v) in [(24, lba), (32, other), (40, first), (48, last), (72, array)] {
            h[off..off + 8].copy_from_slice(&v.to_le_bytes());
        }
        h[56..72].copy_from_slice(&id);
        let c = crc(&h[..92]);
        h[16..20].copy_from_slice(&c.to_le_bytes());
        file.write_all_at(&h, lba * sector).unwrap();
        file.write_all_at(&table, array * sector).unwrap();
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs::{self, OpenOptions},
        path::PathBuf,
    };
    struct Fixture {
        path: PathBuf,
        file: File,
        size: u64,
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.path);
        }
    }
    fn fixture() -> Fixture {
        let path = std::env::temp_dir().join(format!("recovery-gpt-{}", new_guid().unwrap()));
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        let blocks = 249393152u64;
        let size = blocks * SECTOR;
        file.set_len(size).unwrap();
        let mut mbr = [0; 512];
        mbr[450] = 0xee;
        mbr[454..458].copy_from_slice(&1u32.to_le_bytes());
        mbr[458..462].fill(0xff);
        mbr[510..].copy_from_slice(&[0x55, 0xaa]);
        file.write_all_at(&mbr, 0).unwrap();
        let mut table = vec![0u8; 8192];
        for (i, (name, start, end, kind, attributes)) in [
            (
                "super",
                229376u64,
                2588671u64,
                "89a12de1-5e41-4cb3-8b4c-b1441eb5da38",
                1u64 << 60,
            ),
            ("userdata", 2588672, blocks - 6, ANDROID, 0),
        ]
        .iter()
        .enumerate()
        {
            let entry = &mut table[i * 128..(i + 1) * 128];
            entry[..16].copy_from_slice(&guid_bytes(kind).unwrap());
            entry[16..32].copy_from_slice(&guid_bytes(&new_guid().unwrap()).unwrap());
            entry[32..40].copy_from_slice(&start.to_le_bytes());
            entry[40..48].copy_from_slice(&end.to_le_bytes());
            entry[48..56].copy_from_slice(&attributes.to_le_bytes());
            for (i, w) in name.encode_utf16().enumerate() {
                entry[56 + i * 2..58 + i * 2].copy_from_slice(&w.to_le_bytes());
            }
        }
        let id = guid_bytes(&new_guid().unwrap()).unwrap();
        for (lba, other, array) in [(1, blocks - 1, 2), (blocks - 1, 1, blocks - 5)] {
            let mut h = vec![0; 4096];
            h[..8].copy_from_slice(b"EFI PART");
            for (off, v) in [
                (8, 0x10000u32),
                (12, 92),
                (80, 64),
                (84, 128),
                (88, crc(&table)),
            ] {
                h[off..off + 4].copy_from_slice(&v.to_le_bytes());
            }
            for (off, v) in [
                (24, lba),
                (32, other),
                (40, 6),
                (48, blocks - 6),
                (72, array),
            ] {
                h[off..off + 8].copy_from_slice(&v.to_le_bytes());
            }
            h[56..72].copy_from_slice(&id);
            let c = crc(&h[..92]);
            h[16..20].copy_from_slice(&c.to_le_bytes());
            file.write_all_at(&h, lba * SECTOR).unwrap();
            file.write_all_at(&table, array * SECTOR).unwrap();
        }
        Fixture { path, file, size }
    }
    #[test]
    fn preserves_oem_unused_entries_and_allocates_only_zero_entries() {
        let f = fixture();
        let mut g = Gpt::read(&f.file, f.size).unwrap();
        for table in &mut g.tables {
            let raw = &mut table[256..384];
            raw[16..32].fill(0x42);
            raw[32..40].copy_from_slice(&100u64.to_le_bytes());
            raw[40..48].copy_from_slice(&99u64.to_le_bytes());
            raw[55] = 0x10;
            for (i, w) in "last_parti".encode_utf16().enumerate() {
                raw[56 + i * 2..58 + i * 2].copy_from_slice(&w.to_le_bytes());
            }
        }
        for (offset, data) in g.regions(&g.partitions).unwrap() {
            f.file.write_all_at(&data, offset).unwrap();
        }
        let parsed = Gpt::read(&f.file, f.size).unwrap();
        assert_eq!(parsed.partitions, g.partitions);
        let parts = parsed.split(1 << 30, 16 << 30).unwrap();
        assert_eq!(
            parts.iter().map(|p| p.number).collect::<Vec<_>>(),
            [1, 2, 4, 5]
        );
        parsed.write_split(&f.file, &parts).unwrap();
        let after = Gpt::read(&f.file, f.size).unwrap();
        assert_eq!(&after.tables[0][256..384], &g.tables[0][256..384]);
        assert_eq!(&after.tables[1][256..384], &g.tables[1][256..384]);
    }
    #[test]
    fn existing_layout_accepts_both_orders_and_alignment_gaps() {
        let f = fixture();
        let mut g = Gpt::read(&f.file, f.size).unwrap();
        g.partitions = g.split(0, 16 << 30).unwrap();
        g.check_linux_layout(1 << 30, 16 << 30).unwrap();
        let first = g.partitions[2].start;
        let last = g.partitions[3].end;
        // Existing Sheng layout places root before ESP; indices are not identity.
        g.partitions[3].start = first;
        g.partitions[3].end = last - (1 << 30) / SECTOR;
        g.partitions[2].start = g.partitions[3].end + 1;
        g.partitions[2].end = last;
        g.partitions[1].end -= 128;
        g.check_linux_layout(1 << 30, 16 << 30).unwrap();
        assert!(g.check_linux_layout(2 << 30, 16 << 30).is_err());
        g.check_linux_layout(0, 16 << 30).unwrap();
        g.partitions[3].start = g.partitions[1].end;
        assert!(g.check_linux_layout(0, 16 << 30).is_err());
    }
    #[test]
    fn sparse_split_preserves_oem_gaps_and_unrelated_bytes() {
        let f = fixture();
        let g = Gpt::read(&f.file, f.size).unwrap();
        let parts = g.split(1 << 30, 16 << 30).unwrap();
        let user = &parts[1];
        let esp = &parts[2];
        let linux = &parts[3];
        assert_eq!(user.uuid, g.partitions[1].uuid);
        assert_eq!(user.start, g.partitions[1].start);
        assert_eq!(esp.bytes(), 1 << 30);
        assert_eq!(linux.end, g.last_usable());
        assert_eq!(esp.start % 256, 0);
        assert_eq!(linux.start % 256, 0);
        assert!(user.bytes().abs_diff(esp.bytes() + linux.bytes()) < 2 << 20);
        let offsets = [
            4 * SECTOR,
            5 * SECTOR,
            f.size - 3 * SECTOR,
            f.size - 2 * SECTOR,
            229376 * SECTOR,
            g.partitions[1].start * SECTOR,
        ];
        for off in offsets {
            f.file.write_all_at(b"untouched", off).unwrap();
        }
        let pmbr = read_at(&f.file, 0, 512).unwrap();
        g.write_split(&f.file, &parts).unwrap();
        let new = Gpt::read(&f.file, f.size).unwrap();
        assert_eq!(new.partitions[0], g.partitions[0]);
        assert_eq!(&new.tables[0][..128], &g.tables[0][..128]);
        assert_eq!(read_at(&f.file, 0, 512).unwrap(), pmbr);
        for off in offsets {
            assert_eq!(read_at(&f.file, off, 9).unwrap(), b"untouched");
        }
        assert!(new.split(1 << 30, 16 << 30).is_err());
    }
    #[test]
    fn rejects_crc_mismatch_and_partial_write() {
        let f = fixture();
        let g = Gpt::read(&f.file, f.size).unwrap();
        for off in [2 * SECTOR, f.size - 5 * SECTOR] {
            let old = read_at(&f.file, off, 1).unwrap();
            f.file.write_all_at(&[old[0] ^ 1], off).unwrap();
            assert!(Gpt::read(&f.file, f.size).is_err());
            f.file.write_all_at(&old, off).unwrap();
        }
        for (off, data) in g
            .regions(&g.split(1 << 30, 16 << 30).unwrap())
            .unwrap()
            .into_iter()
            .take(2)
        {
            f.file.write_all_at(&data, off).unwrap();
        }
        assert!(Gpt::read(&f.file, f.size)
            .unwrap_err()
            .to_string()
            .contains("entries differ"));
    }
    #[test]
    fn refuses_changed_userdata_or_insufficient_entries() {
        let f = fixture();
        let g = Gpt::read(&f.file, f.size).unwrap();
        for change in 0..6 {
            let mut x = g.clone();
            match change {
                0 => x.partitions[1].end -= 1,
                1 => x.partitions[1].start = x.partitions[1].end - 1000,
                2 => x.partitions[1].kind = ESP.into(),
                3 => x.partitions[1].attributes = 1,
                4 => x.partitions[0].name = "linux".into(),
                _ => x.headers[0].count = 2,
            };
            assert!(x.split(1 << 30, 16 << 30).is_err());
        }
    }
    #[test]
    fn requires_exclusive_bootable_b() {
        let f = fixture();
        let mut g = Gpt::read(&f.file, f.size).unwrap();
        g.partitions[0].name = "boot_a".into();
        g.partitions[1].name = "boot_b".into();
        for (a, b, ok) in [
            (0x72000000000000, 0x3f000000000000, true),
            (1 << 50, 0x3f000000000000, false),
            (0, 0, false),
            (0, 0xbf000000000000, false),
            (0, 7 << 48, false),
        ] {
            g.partitions[0].attributes = a;
            g.partitions[1].attributes = b;
            assert_eq!(g.selected_b().is_ok(), ok);
        }
    }
    #[test]
    fn backup_repair_preserves_primary_padding_and_payloads() {
        let f = fixture();
        let mut g = Gpt::read(&f.file, f.size).unwrap();
        let mut parts = g.partitions.clone();
        parts[0].name = "firmware_a".into();
        parts[1].name = "firmware_b".into();
        g.write_split(&f.file, &parts).unwrap();
        g = Gpt::read(&f.file, f.size).unwrap();
        let mut switched = g.partitions.clone();
        switched[0].kind = parts[1].kind.clone();
        switched[1].kind = parts[0].kind.clone();
        switched[1].attributes |= 1 << 50;
        for (off, data) in g.regions(&switched).unwrap().into_iter().skip(2) {
            f.file.write_all_at(&data, off).unwrap();
        }
        assert!(Gpt::read(&f.file, f.size).is_err());
        let primary = read_at(&f.file, 0, 4 * SECTOR as usize).unwrap();
        let untouched = [4 * SECTOR, f.size - 3 * SECTOR, parts[1].start * SECTOR];
        for off in untouched {
            f.file.write_all_at(b"keep", off).unwrap();
        }
        let plan = Gpt::read_for_backup_repair(&f.file, f.size).unwrap();
        assert!(plan.backup_needs_repair());
        for byte in [0, 16, 32, 48, 56] {
            let off = f.size - 5 * SECTOR + byte;
            let old = read_at(&f.file, off, 1).unwrap();
            f.file.write_all_at(&[old[0] ^ 1], off).unwrap();
            assert!(Gpt::read_for_backup_repair(&f.file, f.size).is_err());
            assert!(plan.repair_backup(&f.file).is_err());
            f.file.write_all_at(&old, off).unwrap();
        }
        plan.repair_backup(&f.file).unwrap();
        assert_eq!(read_at(&f.file, 0, primary.len()).unwrap(), primary);
        for off in untouched {
            assert_eq!(read_at(&f.file, off, 4).unwrap(), b"keep");
        }
        let after = Gpt::read(&f.file, f.size).unwrap();
        assert_eq!(after.partitions, switched);
        assert!(!after.backup_needs_repair());
        after.repair_backup(&f.file).unwrap();
        assert!(plan.repair_backup(&f.file).is_err());
    }
    #[test]
    fn backup_repair_rejects_layout_identity_and_primary_corruption() {
        let f = fixture();
        // No repair mode may accept a corrupt primary, even one differing only in CRC.
        for offset in [
            SECTOR + 16,
            2 * SECTOR,
            f.size - SECTOR + 16,
            f.size - 5 * SECTOR,
            f.size - 5 * SECTOR + 16,
            f.size - 5 * SECTOR + 32,
            f.size - 5 * SECTOR + 56,
            f.size - 5 * SECTOR + 256,
        ] {
            let old = read_at(&f.file, offset, 1).unwrap();
            f.file.write_all_at(&[old[0] ^ 1], offset).unwrap();
            assert!(
                Gpt::read_for_backup_repair(&f.file, f.size).is_err(),
                "offset {offset}"
            );
            f.file.write_all_at(&old, offset).unwrap();
        }
        // A CRC-valid backup header with a stale array CRC is repairable.
        let off = f.size - SECTOR;
        let mut h = read_at(&f.file, off, SECTOR as usize).unwrap();
        h[88] ^= 1;
        h[16..20].fill(0);
        let sum = crc(&h[..92]);
        h[16..20].copy_from_slice(&sum.to_le_bytes());
        f.file.write_all_at(&h, off).unwrap();
        assert!(Gpt::read(&f.file, f.size).is_err());
        Gpt::read_for_backup_repair(&f.file, f.size)
            .unwrap()
            .repair_backup(&f.file)
            .unwrap();
        Gpt::read(&f.file, f.size).unwrap();
    }
    #[test]
    fn stale_plan_cannot_write() {
        let f = fixture();
        let g = Gpt::read(&f.file, f.size).unwrap();
        let parts = g.split(1 << 30, 16 << 30).unwrap();
        g.write_split(&f.file, &parts).unwrap();
        assert!(g.write_split(&f.file, &parts).is_err());
    }
    #[test]
    fn reads_512_byte_emmc_gpt_without_changing_4k_rules() {
        let p = std::env::temp_dir().join(format!("recovery-gpt512-{}", new_guid().unwrap()));
        let blocks = 1u64 << 21;
        write_test_disk(
            &p,
            512,
            blocks,
            &[
                (
                    "system",
                    2048,
                    2048 + 8191,
                    LINUX,
                    "11111111-2222-4333-8444-555555555555",
                ),
                (
                    "userdata",
                    16384,
                    blocks - 100,
                    LINUX,
                    "21111111-2222-4333-8444-555555555555",
                ),
            ],
        );
        let f = File::open(&p).unwrap();
        let g = Gpt::read_sector(&f, blocks * 512, 512).unwrap();
        let system = g.partition("system").unwrap();
        assert_eq!(
            (system.number, system.sector, system.bytes()),
            (1, 512, 8192 * 512)
        );
        // The 4 KiB A/B reader rejects the same image instead of reinterpreting it.
        assert!(Gpt::read(&f, blocks * 512).is_err());
        assert!(Gpt::read_sector(&f, blocks * 512, 1024).is_err());
        // The A/B partition plan JSON is unchanged by the sector field.
        let json = serde_json::to_value(system).unwrap();
        assert!(json.get("sector").is_none() && json.get("uuid").is_some());
        // A/B planning and writes stay 4 KiB only.
        assert!(g.split(1 << 30, 16 << 30).is_err());
        assert!(g.regions(&g.partitions).is_err());
        fs::remove_file(p).unwrap();
    }
}
