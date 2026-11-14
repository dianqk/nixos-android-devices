//! Strict GPT support. A/B planning and writes use 4 KiB sectors only; read-only
//! resolution also accepts 512-byte eMMC sectors. Preserve OEM placement,
//! padding and unrelated entries.
use anyhow::{ensure, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs::File,
    os::unix::fs::{FileExt, FileTypeExt},
};

pub const SECTOR: u64 = 4096;
/// Logical sector sizes accepted by read-only single-slot resolution.
pub const READ_SECTORS: [u64; 2] = [512, 4096];
fn default_sector() -> u64 {
    SECTOR
}
pub const LINUX: &str = "0fc63daf-8483-4772-8e79-3d69d8477de4";
pub const ESP: &str = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
pub const ANDROID: &str = "1b81e7e6-f50d-419b-a739-2aeef8da3335";
/// MediaTek firmware labels every partition, userdata included, as basic data.
pub const BASIC_DATA: &str = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7";
/// Names a userdata split adds, in disk order after Android userdata.
pub const USERDATA_SPLIT: [&str; 2] = ["linux-boot", "linux"];

fn u32_at(b: &[u8], n: usize) -> u32 {
    u32::from_le_bytes(b[n..n + 4].try_into().unwrap())
}
fn u64_at(b: &[u8], n: usize) -> u64 {
    u64::from_le_bytes(b[n..n + 8].try_into().unwrap())
}
pub(crate) fn crc(b: &[u8]) -> u32 {
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
/// Write one region and push it to the device: fsync, then drop cached
/// buffers so readback comes from the medium (BLKFLSBUF; ignored on files).
fn write_flush(f: &File, offset: u64, data: &[u8]) -> Result<()> {
    use std::os::fd::AsRawFd;
    f.write_all_at(data, offset)?;
    f.sync_all()?;
    if f.metadata()?.file_type().is_block_device() {
        ensure!(
            unsafe { libc::ioctl(f.as_raw_fd(), 0x1261) } == 0,
            "BLKFLSBUF failed: {}",
            std::io::Error::last_os_error()
        );
    }
    Ok(())
}
/// Write a captured rollback image back byte for byte (backup copy first,
/// like a planned write) and verify every region.
pub fn restore(f: &File, original: &[(u64, Vec<u8>)]) -> Result<()> {
    ensure!(original.len() == 4, "incomplete GPT rollback image");
    for (offset, data) in original {
        write_flush(f, *offset, data)?;
    }
    for (offset, data) in original {
        ensure!(
            read_at(f, *offset, data.len())? == *data,
            "GPT rollback readback differs"
        );
    }
    Ok(())
}
/// One GPT copy on its own, checked the way the MediaTek preloader and LK
/// check it (signature, header CRC, 128-byte entries, entries CRC over
/// count x 128): its entry count and partitions.
pub fn read_copy(
    f: &File,
    disk_bytes: u64,
    sector: u64,
    lba: u64,
) -> Result<(usize, Vec<Partition>)> {
    let _ = disk_bytes;
    let h = read_at(f, lba * sector, sector as usize)?;
    ensure!(h.len() >= 92 && &h[..8] == b"EFI PART", "no GPT header");
    let count = u32_at(&h, 80) as usize;
    ensure!((1..=4096).contains(&count), "unsupported GPT header");
    let table = read_at(f, u64_at(&h, 72) * sector, count * 128)?;
    parse_copy(&h, &table, sector, lba)
}
fn parse_copy(h: &[u8], table: &[u8], sector: u64, lba: u64) -> Result<(usize, Vec<Partition>)> {
    ensure!(
        h.len() >= 92 && &h[..8] == b"EFI PART" && u32_at(h, 12) == 92,
        "no GPT header"
    );
    let mut check = h[..92].to_vec();
    check[16..20].fill(0);
    ensure!(crc(&check) == u32_at(h, 16), "GPT header CRC mismatch");
    let count = u32_at(h, 80) as usize;
    ensure!(
        (1..=4096).contains(&count) && u32_at(h, 84) == 128 && u64_at(h, 24) == lba,
        "unsupported GPT header"
    );
    let table = table.get(..count * 128).context("truncated GPT entries")?;
    ensure!(crc(table) == u32_at(h, 88), "GPT entries CRC mismatch");
    let mut parts = Vec::new();
    for (i, raw) in table.chunks(128).enumerate() {
        if raw[..16] == [0; 16] {
            continue;
        }
        let words: Vec<u16> = raw[56..]
            .chunks(2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]))
            .collect();
        parts.push(Partition {
            number: i + 1,
            name: String::from_utf16(&words)?
                .trim_end_matches('\0')
                .to_owned(),
            start: u64_at(raw, 32),
            end: u64_at(raw, 40),
            kind: guid(&raw[..16]),
            uuid: guid(&raw[16..32]),
            attributes: u64_at(raw, 48),
            sector,
        });
    }
    Ok((count, parts))
}
/// The table a rollback image restores (its primary copy, fully checked) and
/// whether its backup copy holds the same entries.
pub fn image_partitions(image: &[(u64, Vec<u8>)], sector: u64) -> Result<(usize, Vec<Partition>)> {
    ensure!(image.len() == 4, "incomplete GPT rollback image");
    let primary = parse_copy(&image[3].1, &image[2].1, sector, image[3].0 / sector)?;
    let backup = parse_copy(&image[1].1, &image[0].1, sector, image[1].0 / sector)?;
    ensure!(primary == backup, "rollback image copies differ");
    Ok(primary)
}
/// Load a rollback image saved by `Gpt::snapshot` (header-<lba>, table-<lba>
/// files) for the given disk geometry, in write order.
pub fn load_snapshot(dir: &std::path::Path, g: &Gpt) -> Result<Vec<(u64, Vec<u8>)>> {
    let mut out = Vec::new();
    for (h, t) in g.headers.iter().zip(&g.tables).rev() {
        let table = std::fs::read(dir.join(format!("table-{}", h.table)))?;
        let header = std::fs::read(dir.join(format!("header-{}", h.lba)))?;
        ensure!(
            table.len() == t.len() && header.len() == h.raw.len(),
            "snapshot does not match this disk's GPT geometry"
        );
        ensure!(
            u64_at(&header, 24) == h.lba && u64_at(&header, 72) == h.table,
            "snapshot header belongs to another location"
        );
        out.push((h.table * g.sector, table));
        out.push((h.lba * g.sector, header));
    }
    Ok(out)
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
/// Android userdata sizes `prepare-install` may keep on A/B devices, and the
/// space the Linux ESP and root must keep in the userdata allocation.
const ANDROID_USERDATA_SIZES: [u64; 5] = [32 << 30, 64 << 30, 128 << 30, 256 << 30, 512 << 30];
pub const MINIMUM_LINUX: u64 = 64 << 30;
fn gib(bytes: u64) -> String {
    format!("{}G", bytes >> 30)
}
/// Parse a `prepare-install --android-userdata` size: whole GiB as `<N>G`.
pub fn parse_gib(text: &str) -> Result<u64> {
    let n: u64 = text
        .strip_suffix('G')
        .and_then(|n| n.parse().ok())
        .filter(|n| *n > 0 && *n <= 1 << 20)
        .with_context(|| format!("size {text:?} is not whole GiB such as 64G"))?;
    Ok(n << 30)
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
    /// Attribute bits a stale backup may differ in: the Qualcomm slot bits
    /// 48-55 (priority, active, retry count, successful, unbootable) and bit
    /// 60, which Qualcomm/Xiaomi firmware also flips on slot entries.
    const SLOT_ATTRIBUTES: u64 = (0xff << 48) | (1 << 60);
    /// The backup entries that differ from the primary, after checking that
    /// each is a stale copy of a slot entry: only entries named `<base>_a` or
    /// `<base>_b` whose partner exists may differ, and only in the type GUID
    /// (to any non-zero type: Qualcomm ABL swaps the types of a pair, Xiaomi
    /// ABL also gives the inactive slot a placeholder type) and in
    /// `SLOT_ATTRIBUTES`. Unique GUIDs, first/last LBAs, other attributes,
    /// names, unused entries, the entry count and the header geometry must
    /// match. Never infer layout, names or partition UUIDs.
    fn check_backup_repair_scope(&self) -> Result<usize> {
        let mut differing = 0;
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
            differing += 1;
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
                anyhow::bail!("backup differs outside an A/B entry ({})", p.name);
            };
            ensure!(
                !base.is_empty() && self.partition(&format!("{base}{other}")).is_ok(),
                "backup differs in {} without an A/B partner",
                p.name
            );
            ensure!(
                a[16..48] == b[16..48] && a[56..] == b[56..],
                "backup partition identity or geometry differs ({})",
                p.name
            );
            ensure!(
                (u64_at(a, 48) ^ u64_at(b, 48)) & !Self::SLOT_ATTRIBUTES == 0,
                "backup differs in non-slot attributes ({})",
                p.name
            );
            ensure!(b[..16] != [0; 16], "backup marks {} unused", p.name);
        }
        Ok(differing)
    }
    /// What a backup repair would change: differing slot entries and whether
    /// the backup header's entries CRC is stale.
    pub fn backup_repair_summary(&self) -> Result<String> {
        let entries = self.check_backup_repair_scope()?;
        let count = self.headers[1].count;
        let stale = crc(&self.tables[1][..count * 128]) != u32_at(&self.headers[1].raw, 88);
        Ok(format!(
            "{entries} A/B entries differ in type GUID/slot attributes; backup entries CRC {}",
            if stale { "stale" } else { "valid" }
        ))
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
            write_flush(f, offset, &data)?;
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
    /// The A/B plan that keeps about half of userdata for Android; the
    /// recovery operation always uses an explicit size (`split_keeping`).
    #[cfg(test)]
    pub fn split(&self, esp_bytes: u64, minimum_root: u64) -> Result<Vec<Partition>> {
        self.split_at(esp_bytes, minimum_root, None)
    }
    /// Sizes offered for this disk leave at least 64 GiB for Linux's ESP and root.
    pub fn android_userdata_choices(&self) -> Result<Vec<u64>> {
        let user = self.partition("userdata")?;
        Ok(ANDROID_USERDATA_SIZES
            .into_iter()
            .filter(|bytes| {
                let boundary = (user.start + bytes / SECTOR).div_ceil(256) * 256;
                (user.end + 1).saturating_sub(boundary) * SECTOR >= MINIMUM_LINUX
            })
            .collect())
    }
    fn require_choice(&self, android_bytes: u64) -> Result<()> {
        let choices = self.android_userdata_choices()?;
        ensure!(choices.contains(&android_bytes),
            "keeping {} of Android userdata is not offered: Linux needs {} of the userdata allocation; offered: {}",
            gib(android_bytes), gib(MINIMUM_LINUX),
            if choices.is_empty() { "none".into() } else { choices.iter().map(|b| gib(*b)).collect::<Vec<_>>().join(", ") });
        Ok(())
    }
    /// Split the trailing userdata allocation of a Qualcomm A/B disk into
    /// Android userdata of `android_bytes` (one of `android_userdata_choices`,
    /// rounded up to 1 MiB), the FAT ESP and the Linux root, which takes the
    /// rest. Nothing outside userdata changes.
    pub fn split_keeping(
        &self,
        esp_bytes: u64,
        minimum_root: u64,
        android_bytes: u64,
    ) -> Result<Vec<Partition>> {
        self.require_choice(android_bytes)?;
        self.split_at(esp_bytes, minimum_root, Some(android_bytes))
    }
    fn split_at(
        &self,
        esp_bytes: u64,
        minimum_root: u64,
        android_bytes: Option<u64>,
    ) -> Result<Vec<Partition>> {
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
        let boundary = match android_bytes {
            None => (user.start + (user.end + 1 - user.start) / 2) / 256 * 256,
            Some(bytes) => {
                ensure!(
                    bytes > 0 && bytes % (1 << 20) == 0,
                    "Android userdata size must be a whole number of MiB"
                );
                // Round up to the next 1 MiB boundary: Android keeps at least the choice.
                (user.start + bytes / SECTOR).div_ceil(256) * 256
            }
        };
        ensure!(
            boundary >= user.start + (16 << 30) / SECTOR && boundary <= user.end,
            "Android userdata is too small"
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
    /// Entry count of both headers.
    pub fn entry_count(&self) -> usize {
        self.headers[0].count
    }
    /// Entries that both array allocations hold without moving them: the
    /// array may grow within the sectors it already occupies.
    fn entry_capacity(&self) -> usize {
        self.tables.iter().map(|t| t.len() / 128).min().unwrap_or(0)
    }
    /// Split the trailing userdata allocation of a MediaTek A/B disk: Android
    /// userdata keeps the chosen size (one of `android_userdata_choices`),
    /// followed by the FAT ESP and the Linux root. Nothing outside userdata changes; the
    /// entry array grows only within its allocated, zero-filled sectors.
    pub fn split_userdata(
        &self,
        esp_bytes: u64,
        minimum_root: u64,
        android_bytes: u64,
    ) -> Result<(Vec<Partition>, usize)> {
        const ALIGN: u64 = (1 << 20) / SECTOR;
        ensure!(
            self.sector == SECTOR,
            "partition planning supports 4 KiB GPT only"
        );
        self.partition("super")?;
        self.partition("misc")?;
        ensure!(
            !self
                .partitions
                .iter()
                .any(|p| USERDATA_SPLIT.contains(&p.name.as_str())),
            "Linux partitions already exist"
        );
        let user = self.partition("userdata")?;
        ensure!(
            [ANDROID, LINUX, BASIC_DATA].contains(&user.kind.as_str()) && user.attributes == 0,
            "unexpected userdata type/attributes"
        );
        // OEM partitions may follow userdata (MediaTek: mrdump, flashinfo);
        // the split stays inside the userdata span, which the reader already
        // checked against overlaps.
        ensure!(
            esp_bytes > 0 && esp_bytes % (1 << 20) == 0,
            "invalid ESP size"
        );
        ensure!(user.start % ALIGN == 0, "userdata is not 1 MiB aligned");
        let count = self.headers[0].count;
        let mut free: Vec<usize> = (1..=count)
            .filter(|n| {
                self.tables[0][(n - 1) * 128..n * 128]
                    .iter()
                    .all(|b| *b == 0)
            })
            .take(2)
            .collect();
        let mut new_count = count;
        while free.len() < 2 {
            new_count += 1;
            free.push(new_count);
        }
        ensure!(
            new_count <= self.entry_capacity()
                && self
                    .tables
                    .iter()
                    .all(|t| t[count * 128..new_count * 128].iter().all(|b| *b == 0)),
            "no room for two GPT entries in the allocated arrays"
        );
        self.require_choice(android_bytes)?;
        // The chosen size, rounded up to the next 1 MiB boundary.
        let android = (android_bytes / SECTOR).div_ceil(ALIGN) * ALIGN;
        let esp_start = user.start + android;
        let root_start = esp_start + esp_bytes / SECTOR;
        ensure!(
            root_start <= user.end && (user.end + 1 - root_start) * SECTOR >= minimum_root,
            "Linux root is too small"
        );
        let mut parts = self.partitions.clone();
        parts.iter_mut().find(|p| p.name == "userdata").unwrap().end = esp_start - 1;
        for (number, name, start, end, kind) in [
            (free[0], "linux-boot", esp_start, root_start - 1, ESP),
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
        Ok((parts, new_count))
    }
    /// Accept a completed userdata split (layout and order of the three parts).
    pub fn check_userdata_layout(&self, esp_bytes: u64, minimum_root: u64) -> Result<()> {
        self.partition("super")?;
        let user = self.partition("userdata")?;
        let esp = self.partition("linux-boot")?;
        let root = self.partition("linux")?;
        ensure!(
            esp.kind == ESP
                && root.kind == LINUX
                && [ANDROID, LINUX, BASIC_DATA].contains(&user.kind.as_str()),
            "unexpected partition types"
        );
        ensure!(
            esp.bytes() == esp_bytes && root.bytes() >= minimum_root,
            "invalid ESP/root sizes"
        );
        ensure!(
            user.end + 1 == esp.start && esp.end + 1 == root.start,
            "expected userdata, linux-boot and linux in order"
        );
        ensure!(
            self.partitions.iter().all(|p| p.name == "userdata"
                || USERDATA_SPLIT.contains(&p.name.as_str())
                || p.end < user.start
                || p.start > root.end),
            "another partition inside the userdata span"
        );
        Ok(())
    }

    pub fn linux_only(&self, esp_bytes: u64, minimum_root: u64) -> Result<Vec<Partition>> {
        ensure!(
            self.sector == SECTOR,
            "partition planning supports 4 KiB GPT only"
        );
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
        let esp_bytes = if esp_bytes == 0 { 1 << 30 } else { esp_bytes };
        ensure!(
            esp_bytes % (1 << 20) == 0 && esp_bytes < user.bytes(),
            "invalid ESP size"
        );
        let root_start = user
            .start
            .checked_add(esp_bytes / SECTOR)
            .context("ESP overflow")?;
        ensure!(
            (user.end + 1 - root_start) * SECTOR >= minimum_root,
            "Linux root is too small"
        );
        let free = (1..=self.headers[0].count)
            .find(|n| {
                self.tables[0][(n - 1) * 128..n * 128]
                    .iter()
                    .all(|b| *b == 0)
            })
            .context("no free GPT entry")?;
        let mut parts: Vec<_> = self
            .partitions
            .iter()
            .filter(|p| *p != user)
            .cloned()
            .collect();
        for (number, name, start, end, kind) in [
            (user.number, "linux-boot", user.start, root_start - 1, ESP),
            (free, "linux", root_start, user.end, LINUX),
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
    pub fn check_linux_only_layout(&self, esp_bytes: u64, minimum_root: u64) -> Result<()> {
        self.partition("super")?;
        ensure!(
            !self.partitions.iter().any(|p| p.name == "userdata"),
            "Linux-only layout still has userdata"
        );
        let root = self.partition("linux")?;
        let esp = self.partition("linux-boot")?;
        ensure!(
            root.kind == LINUX && esp.kind == ESP,
            "unexpected Linux partition types"
        );
        ensure!(
            (esp_bytes == 0 || esp.bytes() == esp_bytes) && root.bytes() >= minimum_root,
            "invalid Linux/ESP sizes"
        );
        ensure!(
            esp.end + 1 == root.start && root.end == self.headers[0].last,
            "Linux-only allocation must occupy the disk tail"
        );
        ensure!(
            self.partitions
                .iter()
                .all(|p| ["linux", "linux-boot"].contains(&p.name.as_str()) || p.end < esp.start),
            "other partitions overlap the Linux allocation"
        );
        Ok(())
    }
    pub fn regions(&self, parts: &[Partition]) -> Result<Vec<(u64, Vec<u8>)>> {
        self.regions_with_count(parts, self.headers[0].count)
    }
    /// Header and array writes for `parts` with `count` entries (which may
    /// grow within the allocated arrays).
    pub fn regions_with_count(
        &self,
        parts: &[Partition],
        count: usize,
    ) -> Result<Vec<(u64, Vec<u8>)>> {
        ensure!(
            self.sector == SECTOR,
            "GPT writes support 4 KiB sectors only"
        );
        ensure!(
            count >= self.headers[0].count && count <= self.entry_capacity(),
            "entry count outside the allocated arrays"
        );
        let mut table = self.tables[0].clone();
        for p in parts {
            if self.partitions.iter().any(|old| old == p) {
                continue;
            }
            ensure!(p.number > 0 && p.number <= count, "entry outside GPT");
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
            data[..count * 128].copy_from_slice(&table[..count * 128]);
            let mut header = h.raw.clone();
            header[80..84].copy_from_slice(&(count as u32).to_le_bytes());
            header[88..92].copy_from_slice(&crc(&data[..count * 128]).to_le_bytes());
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
    /// The raw regions a write touches, in write order: backup array, backup
    /// header, primary array, primary header.
    fn region_layout(&self) -> Vec<(u64, usize)> {
        let mut out = Vec::new();
        for (h, t) in self.headers.iter().zip(&self.tables).rev() {
            out.push((h.table * self.sector, t.len()));
            out.push((h.lba * self.sector, h.raw.len()));
        }
        out
    }
    /// Byte-exact copy of the regions a write touches (the rollback image).
    pub fn capture(&self, f: &File) -> Result<Vec<(u64, Vec<u8>)>> {
        self.region_layout()
            .into_iter()
            .map(|(off, len)| Ok((off, read_at(f, off, len)?)))
            .collect()
    }
    /// Write a planned layout with `count` entries so that one valid GPT copy
    /// exists at every moment: the complete backup copy first (array, then
    /// header), verified on its own, then the primary. Every write is flushed
    /// to the device. On any failure the captured original bytes are written
    /// back and verified; the error says whether that succeeded.
    pub fn write_plan(&self, f: &File, parts: &[Partition], count: usize) -> Result<()> {
        ensure!(
            Self::read(f, self.disk_bytes)? == *self,
            "GPT changed after planning"
        );
        let original = self.capture(f)?;
        let regions = self.regions_with_count(parts, count)?;
        let attempt = || -> Result<()> {
            for (i, (offset, data)) in regions.iter().enumerate() {
                write_flush(f, *offset, data)?;
                ensure!(
                    read_at(f, *offset, data.len())? == *data,
                    "GPT region readback differs"
                );
                if i == 1 {
                    let backup = self.headers[1].lba;
                    ensure!(
                        read_copy(f, self.disk_bytes, self.sector, backup)?.1 == parts,
                        "backup GPT does not hold the planned layout"
                    );
                }
            }
            let after = Self::read(f, self.disk_bytes)?;
            ensure!(
                after.partitions == parts && after.headers[0].count == count,
                "GPT readback differs"
            );
            Ok(())
        };
        if let Err(e) = attempt() {
            return match restore(f, &original) {
                Ok(()) => Err(e.context("GPT write failed; the original GPT was restored")),
                Err(r) => Err(e.context(format!(
                    "CRITICAL: GPT write failed and restoring the original failed ({r:#}); do not reboot"
                ))),
            };
        }
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
/// The T880 sdc GPT (82 entries, all basic data, attributes 0), read on 2026-10-14.
pub(crate) const T880_SDC: &[(&str, u64, u64)] = &[
    ("misc", 8, 135),
    ("vb", 136, 1159),
    ("para", 1160, 1287),
    ("expdb", 1288, 34055),
    ("frp", 34056, 34311),
    ("nvcfg", 34312, 42503),
    ("nvdata", 42504, 62983),
    ("md_sec", 62984, 65031),
    ("persist", 65032, 77319),
    ("vbmeta_a", 77320, 79367),
    ("vbmeta_system_a", 79368, 81415),
    ("vbmeta_vendor_a", 81416, 83463),
    ("vbmeta_b", 83464, 85511),
    ("vbmeta_system_b", 85512, 87559),
    ("vbmeta_vendor_b", 87560, 89607),
    ("metadata", 89608, 108543),
    ("protect1", 108544, 110591),
    ("protect2", 110592, 112639),
    ("seccfg", 112640, 114687),
    ("otp", 114688, 125695),
    ("pstore", 125696, 159743),
    ("modem_a", 159744, 210943),
    ("spmfw_a", 210944, 211199),
    ("mcf_ota_a", 211200, 219391),
    ("audio_dsp_a", 219392, 223487),
    ("pi_img_a", 223488, 223999),
    ("dpm_a", 224000, 225023),
    ("scp_a", 225024, 226559),
    ("ccu_a", 226560, 227583),
    ("vcp_a", 227584, 229119),
    ("sspm_a", 229120, 229631),
    ("mcupm_a", 229632, 229887),
    ("gpueb_a", 229888, 230399),
    ("apusys_a", 230400, 231423),
    ("mvpu_algo_a", 231424, 247807),
    ("gz_a", 247808, 255999),
    ("lk_a", 256000, 260095),
    ("boot_a", 260096, 276479),
    ("vendor_boot_a", 276480, 292863),
    ("init_boot_a", 292864, 294911),
    ("dtbo_a", 294912, 296959),
    ("tee_a", 296960, 298239),
    ("connsys_bt_a", 298240, 300287),
    ("connsys_wifi_a", 300288, 302335),
    ("connsys_gnss_a", 302336, 304383),
    ("pvmfw_a", 304384, 305407),
    ("logo_a", 305408, 309247),
    ("sec1", 309248, 309759),
    ("proinfo", 309760, 310527),
    ("nvram", 310528, 326911),
    ("boot_para", 326912, 327167),
    ("dram_para", 327168, 333823),
    ("modem_b", 333824, 385023),
    ("spmfw_b", 385024, 385279),
    ("mcf_ota_b", 385280, 393471),
    ("audio_dsp_b", 393472, 397567),
    ("pi_img_b", 397568, 398079),
    ("dpm_b", 398080, 399103),
    ("scp_b", 399104, 400639),
    ("ccu_b", 400640, 401663),
    ("vcp_b", 401664, 403199),
    ("sspm_b", 403200, 403711),
    ("mcupm_b", 403712, 403967),
    ("gpueb_b", 403968, 404479),
    ("apusys_b", 404480, 405503),
    ("mvpu_algo_b", 405504, 421887),
    ("gz_b", 421888, 430079),
    ("lk_b", 430080, 434175),
    ("boot_b", 434176, 450559),
    ("vendor_boot_b", 450560, 466943),
    ("init_boot_b", 466944, 468991),
    ("connsys_bt_b", 468992, 471039),
    ("connsys_wifi_b", 471040, 473087),
    ("connsys_gnss_b", 473088, 475135),
    ("dtbo_b", 475136, 477183),
    ("pvmfw_b", 477184, 478207),
    ("logo_b", 478208, 480511),
    ("tee_b", 480512, 483327),
    ("super", 483328, 4059135),
    ("userdata", 4059136, 62410743),
    ("mrdump", 62410744, 62476279),
    ("flashinfo", 62476280, 62480375),
];

/// Test-only image of the T880 sdc GPT geometry: 82 entries in three 4 KiB
/// array sectors, first usable LBA 8, last usable LBA 62480375.
#[cfg(test)]
pub(crate) fn write_t880_disk(path: &std::path::Path, dirty_tail: bool) {
    use std::fs::OpenOptions;
    let blocks = 62480384u64;
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)
        .unwrap();
    file.set_len(blocks * SECTOR).unwrap();
    let mut mbr = [0; 512];
    mbr[450] = 0xee;
    mbr[454..458].copy_from_slice(&1u32.to_le_bytes());
    mbr[458..462].fill(0xff);
    mbr[510..].copy_from_slice(&[0x55, 0xaa]);
    file.write_all_at(&mbr, 0).unwrap();
    let count = T880_SDC.len();
    let mut table = vec![0u8; 3 * SECTOR as usize];
    for (i, (name, start, end)) in T880_SDC.iter().enumerate() {
        let entry = &mut table[i * 128..(i + 1) * 128];
        entry[..16].copy_from_slice(&guid_bytes(BASIC_DATA).unwrap());
        let uuid = format!("{i:08x}-39c2-4488-9bb0-00cb43c9ccd4");
        entry[16..32].copy_from_slice(&guid_bytes(&uuid).unwrap());
        entry[32..40].copy_from_slice(&start.to_le_bytes());
        entry[40..48].copy_from_slice(&end.to_le_bytes());
        for (i, w) in name.encode_utf16().enumerate() {
            entry[56 + i * 2..58 + i * 2].copy_from_slice(&w.to_le_bytes());
        }
    }
    if dirty_tail {
        table[count * 128 + 172] = 0x5a;
    }
    let entries_crc = crc(&table[..count * 128]);
    for (lba, other, array) in [(1, blocks - 1, 2), (blocks - 1, 1, blocks - 1 - 3 - 4)] {
        let mut h = vec![0; SECTOR as usize];
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
        for (off, v) in [(24, lba), (32, other), (40, 8), (48, 62480375), (72, array)] {
            h[off..off + 8].copy_from_slice(&v.to_le_bytes());
        }
        let c = crc(&h[..92]);
        h[16..20].copy_from_slice(&c.to_le_bytes());
        file.write_all_at(&h, lba * SECTOR).unwrap();
        file.write_all_at(&table, array * SECTOR).unwrap();
    }
}
#[cfg(test)]
pub(crate) mod tests {
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
            // Any other non-zero type of a paired entry is in scope, but
            // the plan no longer matches the disk.
            assert_eq!(
                Gpt::read_for_backup_repair(&f.file, f.size).is_ok(),
                byte == 0
            );
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
    /// Marble boot LUN (UFS LUN 4) as found after `fastboot set_active b`:
    /// valid primary (B active), CRC-valid backup header whose entries CRC
    /// does not match its array, and a backup array with 54 stale slot
    /// entries (placeholder/other type GUIDs, slot attributes and bit 60).
    /// Partition unique GUIDs are replaced by synthetic ones.
    const MARBLE_BOOT_LUN_ARRAYS: &[u8] = include_bytes!("testdata/marble-boot-lun-gpt-arrays.bin");
    fn marble_boot_lun(backup_edit: impl Fn(&mut [u8])) -> Fixture {
        let path =
            std::env::temp_dir().join(format!("recovery-gpt-marble-{}", new_guid().unwrap()));
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        let blocks = 557056u64;
        let size = blocks * SECTOR;
        file.set_len(size).unwrap();
        let mut mbr = [0; 512];
        mbr[450] = 0xee;
        mbr[454..458].copy_from_slice(&1u32.to_le_bytes());
        mbr[458..462].fill(0xff);
        mbr[510..].copy_from_slice(&[0x55, 0xaa]);
        file.write_all_at(&mbr, 0).unwrap();
        let primary = &MARBLE_BOOT_LUN_ARRAYS[..12288];
        let mut backup = MARBLE_BOOT_LUN_ARRAYS[12288..].to_vec();
        backup_edit(&mut backup);
        let id = guid_bytes("00000000-0000-4000-8000-00000000d15c").unwrap();
        for (lba, other, array, table, entries_crc) in [
            (1, blocks - 1, 2, primary, crc(primary)),
            (blocks - 1, 1, blocks - 5, &backup[..], 0x9226f53e),
        ] {
            let mut h = vec![0; 4096];
            h[..8].copy_from_slice(b"EFI PART");
            for (off, v) in [
                (8, 0x10000u32),
                (12, 92),
                (80, 96),
                (84, 128),
                (88, entries_crc),
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
            file.write_all_at(table, array * SECTOR).unwrap();
        }
        Fixture { path, file, size }
    }
    #[test]
    fn backup_repair_accepts_marble_placeholder_slot_types() {
        let f = marble_boot_lun(|_| ());
        let err = format!("{:#}", Gpt::read(&f.file, f.size).unwrap_err());
        assert!(err.contains("GPT entries CRC mismatch"), "{err}");
        let plan = Gpt::read_for_backup_repair(&f.file, f.size).unwrap();
        assert!(plan.backup_needs_repair());
        assert_eq!(
            plan.backup_repair_summary().unwrap(),
            "54 A/B entries differ in type GUID/slot attributes; backup entries CRC stale"
        );
        plan.selected_b().unwrap();
        assert_eq!(plan.partition("boot_b").unwrap().attributes, 0x3f << 48);
        let primary = read_at(&f.file, 0, 5 * SECTOR as usize).unwrap();
        plan.repair_backup(&f.file).unwrap();
        assert_eq!(read_at(&f.file, 0, primary.len()).unwrap(), primary);
        let after = Gpt::read(&f.file, f.size).unwrap();
        assert_eq!(after.partitions, plan.partitions);
        assert!(!after.backup_needs_repair());
        assert_eq!(
            read_at(&f.file, f.size - 5 * SECTOR, 12288).unwrap(),
            &MARBLE_BOOT_LUN_ARRAYS[..12288]
        );
    }
    #[test]
    fn backup_repair_refuses_marble_changes_outside_slot_metadata() {
        // Entries (1-based): 2 aop_a (differs), 25 non-slot (identical),
        // 42 boot_b (differs), 74 unused last_parti.
        let entry = |n: usize| (n - 1) * 128;
        let cases: Vec<(&str, Box<dyn Fn(&mut [u8])>)> = vec![
            ("start", Box::new(move |b| b[entry(2) + 32] ^= 1)),
            ("end", Box::new(move |b| b[entry(42) + 40] ^= 1)),
            ("unique GUID", Box::new(move |b| b[entry(2) + 16] ^= 1)),
            ("name", Box::new(move |b| b[entry(2) + 56] ^= 1)),
            ("attribute bit 0", Box::new(move |b| b[entry(42) + 48] ^= 1)),
            (
                "attribute bit 56",
                Box::new(move |b| b[entry(42) + 55] ^= 1),
            ),
            ("non-slot type", Box::new(move |b| b[entry(25)] ^= 1)),
            (
                "non-slot attributes",
                Box::new(move |b| b[entry(25) + 54] ^= 1),
            ),
            ("unused entry", Box::new(move |b| b[entry(74) + 16] ^= 1)),
            (
                "zero type",
                Box::new(move |b| b[entry(2)..entry(2) + 16].fill(0)),
            ),
        ];
        for (what, edit) in cases {
            let f = marble_boot_lun(edit);
            assert!(
                Gpt::read_for_backup_repair(&f.file, f.size).is_err(),
                "{what} accepted"
            );
        }
        // Only the slot bits and bit 60 may differ on slot entries.
        let f = marble_boot_lun(move |b| b[entry(42) + 54] ^= 0x01);
        Gpt::read_for_backup_repair(&f.file, f.size).unwrap();
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

    /// A Marble-like LUN0 (Redmi Note 12 Turbo, 256 GB): 61880320 4 KiB
    /// blocks with the measured partition names and order, `super` as sda32
    /// and `userdata` as the last allocation (sda33, about 224 GiB). The
    /// offsets of the small partitions are synthetic.
    pub(crate) fn write_marble_lun0(path: &std::path::Path) -> (u64, u64) {
        const NAMES: [&str; 31] = [
            "switch",
            "ssd",
            "dbg",
            "bk01",
            "bk02",
            "bk03",
            "bk04",
            "keystore",
            "frp",
            "countrycode",
            "misc",
            "bk05",
            "logfs",
            "ffu",
            "oops",
            "devinfo",
            "metadata",
            "bk06",
            "bk07",
            "mtdblk",
            "crash_history",
            "minidump",
            "rawdump",
            "vbmeta_system_a",
            "vbmeta_system_b",
            "bk010",
            "mem",
            "opconfig",
            "mbnconfig",
            "rescue",
            "cust",
        ];
        let blocks = 61880320u64;
        let mut entries: Vec<(String, u64, u64, &str, String)> = Vec::new();
        let mut next = 6u64;
        for (i, name) in NAMES.iter().enumerate() {
            let size = if *name == "cust" {
                (1 << 30) / SECTOR
            } else {
                0x2000
            };
            entries.push((
                name.to_string(),
                next,
                next + size - 1,
                BASIC_DATA,
                format!("{i:08x}-9a4e-4c1d-8f0e-6d61726c6500"),
            ));
            next += size;
        }
        let super_end = next + (9728u64 << 20) / SECTOR - 1;
        entries.push((
            "super".into(),
            next,
            super_end,
            BASIC_DATA,
            "0000001f-9a4e-4c1d-8f0e-6d61726c6500".into(),
        ));
        let user_start = super_end + 1;
        let last = blocks - 4 - 2;
        entries.push((
            "userdata".into(),
            user_start,
            last,
            ANDROID,
            "00000020-9a4e-4c1d-8f0e-6d61726c6500".into(),
        ));
        let refs: Vec<_> = entries
            .iter()
            .map(|(n, a, b, k, u)| (n.as_str(), *a, *b, *k, u.as_str()))
            .collect();
        write_test_disk(path, SECTOR, blocks, &refs);
        (user_start, last)
    }
    /// A disk whose userdata (the last allocation) has exactly `user_bytes`.
    fn userdata_disk(user_bytes: u64) -> (std::path::PathBuf, Gpt) {
        let path = std::env::temp_dir().join(format!("recovery-choices-{}", new_guid().unwrap()));
        let start = 256u64;
        let end = start + user_bytes / SECTOR - 1;
        write_test_disk(
            &path,
            SECTOR,
            end + 1 + 4 + 1,
            &[
                (
                    "super",
                    6,
                    255,
                    BASIC_DATA,
                    "00000001-9a4e-4c1d-8f0e-000000000001",
                ),
                (
                    "userdata",
                    start,
                    end,
                    ANDROID,
                    "00000002-9a4e-4c1d-8f0e-000000000002",
                ),
            ],
        );
        let file = File::open(&path).unwrap();
        let g = Gpt::read(&file, file.metadata().unwrap().len()).unwrap();
        assert_eq!(g.partition("userdata").unwrap().bytes(), user_bytes);
        (path, g)
    }
    #[test]
    fn android_userdata_choices_leave_linux_64_gib() {
        let gib = |n: u64| n << 30;
        let esp = gib(1);
        for (user, offered) in [
            // Exactly Android + 64 GiB for the ESP and root qualifies; 1 MiB less does not.
            (gib(32) + gib(64), vec![32]),
            (gib(32) + gib(64) - (1 << 20), vec![]),
            (gib(64) + gib(64), vec![32, 64]),
            (gib(64) + gib(64) - (1 << 20), vec![32]),
            (gib(128) + gib(64), vec![32, 64, 128]),
            (gib(128) + gib(64) - (1 << 20), vec![32, 64]),
            // 128 GB, 256 GB, 512 GB and 1 TB class userdata allocations.
            (gib(100), vec![32]),
            (gib(224), vec![32, 64, 128]),
            (gib(460), vec![32, 64, 128, 256]),
            (gib(940), vec![32, 64, 128, 256, 512]),
        ] {
            let (path, g) = userdata_disk(user);
            let choices = g.android_userdata_choices().unwrap();
            assert_eq!(
                choices,
                offered.iter().map(|c| gib(*c)).collect::<Vec<_>>(),
                "userdata {user}"
            );
            for size in [32, 64, 128, 256, 512] {
                let plan = g.split_keeping(esp, 16 << 30, gib(size));
                assert_eq!(plan.is_ok(), offered.contains(&size), "{user}: {size}G");
                if let Ok(parts) = plan {
                    let linux: u64 = parts
                        .iter()
                        .filter(|p| p.name == "linux" || p.name == "linux-boot")
                        .map(|p| p.bytes())
                        .sum();
                    assert!(linux >= MINIMUM_LINUX);
                }
            }
            let _ = fs::remove_file(&path);
        }
        assert_eq!(parse_gib("64G").unwrap(), gib(64));
        for bad in ["64", "64GiB", "0G", "-1G", "1.5G", "G", ""] {
            assert!(parse_gib(bad).is_err(), "{bad}");
        }
    }
    #[test]
    fn marble_split_keeps_the_chosen_android_userdata() {
        for (choice, root_floor) in [(64u64, 158u64), (128, 94)] {
            let path =
                std::env::temp_dir().join(format!("recovery-marble-{}", new_guid().unwrap()));
            let (user_start, user_end) = write_marble_lun0(&path);
            let file = OpenOptions::new()
                .read(true)
                .write(true)
                .open(&path)
                .unwrap();
            let size = file.metadata().unwrap().len();
            let g = Gpt::read(&file, size).unwrap();
            assert_eq!(g.sector, SECTOR);
            assert_eq!(
                g.android_userdata_choices().unwrap(),
                [32 << 30, 64 << 30, 128 << 30]
            );
            let user = g.partition("userdata").unwrap().clone();
            assert_eq!(
                (user.number, user.start, user.end),
                (33, user_start, user_end)
            );
            assert!(user.bytes() > 223 << 30 && user.bytes() < 225 << 30);
            let parts = g.split_keeping(1 << 30, 16 << 30, choice << 30).unwrap();
            for old in &g.partitions {
                let new = parts.iter().find(|p| p.number == old.number).unwrap();
                if old.name == "userdata" {
                    assert_eq!(
                        (new.start, new.kind.as_str(), new.uuid.as_str()),
                        (old.start, old.kind.as_str(), old.uuid.as_str())
                    );
                } else {
                    assert_eq!(new, old, "{} changed", old.name);
                }
            }
            let android = parts.iter().find(|p| p.name == "userdata").unwrap();
            let esp = parts.iter().find(|p| p.name == "linux-boot").unwrap();
            let root = parts.iter().find(|p| p.name == "linux").unwrap();
            assert_eq!((esp.number, root.number), (34, 35));
            // The choice, rounded up to the next 1 MiB boundary of the disk.
            assert_eq!(
                android.end + 1,
                (user.start + (choice << 30) / SECTOR).div_ceil(256) * 256
            );
            assert!(
                android.bytes() >= choice << 30 && android.bytes() < (choice << 30) + (1 << 20)
            );
            assert_eq!(
                (esp.start, esp.bytes(), esp.kind.as_str()),
                (android.end + 1, 1 << 30, ESP)
            );
            assert_eq!(
                (root.start, root.end, root.kind.as_str()),
                (esp.end + 1, user.end, LINUX)
            );
            assert!(root.bytes() > root_floor << 30);
            for p in [esp, root] {
                assert_eq!(p.start % 256, 0, "{} is not 1 MiB aligned", p.name);
            }
            println!(
                "Marble plan, Android userdata {choice}G:\n{}",
                serde_json::to_string_pretty(&parts[parts.len() - 3..]).unwrap()
            );
            // 256 GiB (and 512) leave Linux too little; other sizes are not offered.
            for (android, minimum_root) in [
                (16u64 << 30, 16u64 << 30),
                (256 << 30, 16 << 30),
                (512 << 30, 16 << 30),
                ((64 << 30) + (1 << 20), 16 << 30),
                (choice << 30, 200 << 30),
            ] {
                assert!(g.split_keeping(1 << 30, minimum_root, android).is_err());
            }
            g.write_split(&file, &parts).unwrap();
            let after = Gpt::read(&file, size).unwrap();
            after.check_linux_layout(1 << 30, 16 << 30).unwrap();
            assert!(after
                .split_keeping(1 << 30, 16 << 30, choice << 30)
                .is_err());
            drop(file);
            let _ = fs::remove_file(&path);
        }
    }
    #[test]
    fn t880_userdata_split_keeps_every_other_entry_and_grows_the_array() {
        let path = std::env::temp_dir().join(format!("recovery-t880-{}", new_guid().unwrap()));
        write_t880_disk(&path, false);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        let size = file.metadata().unwrap().len();
        let g = Gpt::read(&file, size).unwrap();
        assert_eq!(g.entry_count(), 82);
        let user = g.partition("userdata").unwrap().clone();
        let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 32 << 30).unwrap();
        assert_eq!(count, 84);
        for old in &g.partitions {
            let new = parts.iter().find(|p| p.number == old.number).unwrap();
            if old.name == "userdata" {
                assert_eq!(
                    (new.start, new.uuid.as_str()),
                    (old.start, old.uuid.as_str())
                );
                assert!(new.end < old.end);
            } else {
                assert_eq!(new, old);
            }
        }
        let added: Vec<_> = parts.iter().filter(|p| p.number > 82).collect();
        assert_eq!(
            added
                .iter()
                .map(|p| (p.number, p.name.as_str()))
                .collect::<Vec<_>>(),
            [(83, "linux-boot"), (84, "linux")]
        );
        let new_user = parts.iter().find(|p| p.name == "userdata").unwrap();
        assert_eq!(new_user.end + 1, added[0].start);
        assert_eq!(added[0].bytes(), 1 << 30);
        assert_eq!(added[1].end, user.end);
        for p in [new_user, added[0], added[1]] {
            assert_eq!(p.start % 256, 0, "{} is not 1 MiB aligned", p.name);
        }
        // The chosen 32 GiB stays with Android; Linux takes the rest.
        assert_eq!(new_user.bytes(), 32 << 30);
        assert_eq!((new_user.start, new_user.end), (4059136, 12447743));
        assert_eq!((added[0].start, added[0].end), (12447744, 12709887));
        assert_eq!((added[1].start, added[1].end), (12709888, 62410743));
        assert!(added[0].bytes() + added[1].bytes() >= MINIMUM_LINUX);
        g.write_plan(&file, &parts, count).unwrap();
        let after = Gpt::read(&file, size).unwrap();
        assert_eq!(after.partitions, parts);
        assert_eq!(after.entry_count(), 84);
        assert_eq!(after.tables[0][..84 * 128], after.tables[1][..84 * 128]);
        after.check_userdata_layout(1 << 30, 16 << 30).unwrap();
        assert!(after.split_userdata(1 << 30, 16 << 30, 32 << 30).is_err());
        drop(file);
        let _ = fs::remove_file(&path);
    }
    #[test]
    fn t880_rejects_an_extra_partition_between_esp_and_root() {
        let (path, file, size) = t880_fixture("extra-partition");
        let g = Gpt::read(&file, size).unwrap();
        let (mut parts, _) = g.split_userdata(1 << 30, 16 << 30, 32 << 30).unwrap();
        let root = parts.iter_mut().find(|p| p.name == "linux").unwrap();
        let mut extra = root.clone();
        extra.number = 85;
        extra.name = "unexpected".into();
        extra.uuid = new_guid().unwrap();
        extra.end = extra.start + (128 << 20) / SECTOR - 1;
        root.start = extra.end + 1;
        parts.push(extra);
        g.write_plan(&file, &parts, 85).unwrap();
        let after = Gpt::read(&file, size).unwrap();
        assert!(after.check_userdata_layout(1 << 30, 16 << 30).is_err());
        drop(file);
        let _ = fs::remove_file(path);
    }
    #[test]
    fn t880_split_refuses_a_dirty_array_tail() {
        let path = std::env::temp_dir().join(format!("recovery-t880-{}", new_guid().unwrap()));
        write_t880_disk(&path, true);
        let file = File::open(&path).unwrap();
        let g = Gpt::read(&file, file.metadata().unwrap().len()).unwrap();
        assert!(g.split_userdata(1 << 30, 16 << 30, 64 << 30).is_err());
        drop(file);
        let _ = fs::remove_file(&path);
    }

    fn t880_fixture(tag: &str) -> (PathBuf, File, u64) {
        let path =
            std::env::temp_dir().join(format!("recovery-t880-{tag}-{}", new_guid().unwrap()));
        write_t880_disk(&path, false);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .unwrap();
        let size = file.metadata().unwrap().len();
        (path, file, size)
    }
    #[test]
    fn t880_every_write_step_keeps_one_valid_copy() {
        let (path, file, size) = t880_fixture("steps");
        let g = Gpt::read(&file, size).unwrap();
        let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 64 << 30).unwrap();
        let regions = g.regions_with_count(&parts, count).unwrap();
        let original = g.capture(&file).unwrap();
        let blocks = size / SECTOR;
        for applied in 0..=regions.len() {
            restore(&file, &original).unwrap();
            for (offset, data) in &regions[..applied] {
                file.write_all_at(data, *offset).unwrap();
            }
            let copies: Vec<_> = [1, blocks - 1]
                .iter()
                .filter_map(|lba| read_copy(&file, size, SECTOR, *lba).ok())
                .collect();
            assert!(!copies.is_empty(), "no valid copy after {applied} writes");
            for (n, p) in &copies {
                assert!(
                    (*n == 82 && *p == g.partitions) || (*n == 84 && *p == parts),
                    "a copy is neither the old nor the new table after {applied} writes"
                );
            }
            // The preloader and LK use the primary when it is valid.
            let first = read_copy(&file, size, SECTOR, 1)
                .or_else(|_| read_copy(&file, size, SECTOR, blocks - 1))
                .unwrap();
            assert!(first.1 == g.partitions || first.1 == parts);
        }
        drop(file);
        let _ = fs::remove_file(&path);
    }
    #[test]
    fn t880_write_then_restore_is_byte_exact() {
        let (path, file, size) = t880_fixture("restore");
        let g = Gpt::read(&file, size).unwrap();
        let original = g.capture(&file).unwrap();
        let dir = path.with_extension("snapshot");
        g.snapshot(&dir).unwrap();
        assert_eq!(load_snapshot(&dir, &g).unwrap(), original);
        let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 64 << 30).unwrap();
        g.write_plan(&file, &parts, count).unwrap();
        let after = Gpt::read(&file, size).unwrap();
        // Only count and CRCs change in the headers; LBAs, disk GUID and the
        // 81 untouched entries keep their bytes.
        for (old, new) in g.headers.iter().zip(&after.headers) {
            let changed: Vec<usize> = (0..92).filter(|i| old.raw[*i] != new.raw[*i]).collect();
            assert!(
                changed
                    .iter()
                    .all(|i| (16..20).contains(i) || (80..84).contains(i) || (88..92).contains(i)),
                "{changed:?}"
            );
        }
        for p in &g.partitions {
            let raw = |t: &Vec<u8>| t[(p.number - 1) * 128..p.number * 128].to_vec();
            if p.name != "userdata" {
                assert_eq!(raw(&g.tables[0]), raw(&after.tables[0]), "{}", p.name);
            }
        }
        restore(&file, &load_snapshot(&dir, &g).unwrap()).unwrap();
        assert_eq!(g.capture(&file).unwrap(), original);
        assert_eq!(Gpt::read(&file, size).unwrap(), g);
        // An interrupted write (backup copy only) restores the same way.
        let regions = g.regions_with_count(&parts, count).unwrap();
        for (offset, data) in &regions[..3] {
            file.write_all_at(data, *offset).unwrap();
        }
        restore(&file, &original).unwrap();
        assert_eq!(Gpt::read(&file, size).unwrap(), g);
        drop(file);
        let _ = fs::remove_dir_all(&dir);
        let _ = fs::remove_file(&path);
    }
    #[test]
    fn linux_only_reuses_userdata_and_preserves_other_entries() {
        let f = fixture();
        let g = Gpt::read(&f.file, f.size).unwrap();
        let original_user = g.partition("userdata").unwrap();
        let parts = g.linux_only(1 << 30, 16 << 30).unwrap();
        assert!(!parts.iter().any(|p| p.name == "userdata"));
        let esp = parts.iter().find(|p| p.name == "linux-boot").unwrap();
        let root = parts.iter().find(|p| p.name == "linux").unwrap();
        assert_eq!(esp.number, original_user.number);
        assert_eq!(esp.start, original_user.start);
        assert_eq!(esp.bytes(), 1 << 30);
        assert_eq!(root.start, esp.end + 1);
        assert_eq!(root.end, original_user.end);
        assert_eq!(esp.bytes() + root.bytes(), original_user.bytes());
        let original_super = g.partition("super").unwrap().clone();
        let sentinel = original_super.start * SECTOR;
        f.file.write_all_at(b"preserve-super", sentinel).unwrap();
        g.write_split(&f.file, &parts).unwrap();
        let after = Gpt::read(&f.file, f.size).unwrap();
        after.check_linux_only_layout(1 << 30, 16 << 30).unwrap();
        assert_eq!(after.partition("super").unwrap(), &original_super);
        assert_eq!(read_at(&f.file, sentinel, 14).unwrap(), b"preserve-super");
        assert_eq!(&after.tables[0][..128], &g.tables[0][..128]);
        assert_eq!(&after.tables[1][..128], &g.tables[1][..128]);
        assert!(after.linux_only(1 << 30, 16 << 30).is_err());
        assert!(after.check_linux_layout(1 << 30, 16 << 30).is_err());
        assert!(g.linux_only(1, 16 << 30).is_err());
        assert!(g.linux_only(1 << 30, f.size).is_err());
    }
}
