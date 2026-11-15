// SPDX-License-Identifier: GPL-2.0-only
//! Self-described v1 envelopes. Flag 1 offline; flag 2 prelinked allocation. Integrity is not install authority.
//! Uses core + alloc only; adapters must provide independent adoption authority.
use crate::{avb, format};
use alloc::{vec, vec::Vec};
use sha2::{Digest, Sha256};
pub type Result<T> = core::result::Result<T, &'static str>;
const PAGE: usize = 4096;
const CAP: usize = 256 * 1024 * 1024;
const ARCHIVE_CAP: usize = 16 * 1024 * 1024;
const MAGIC: &[u8; 8] = b"OWNBOOT1";
fn require(b: bool, e: &'static str) -> Result<()> {
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
fn num(b: &[u8], n: usize) -> Result<usize> {
    usize::try_from(u64at(b, n)).map_err(|_| "integer overflow")
}
fn put(b: &mut [u8], n: usize, v: usize) {
    b[n..n + 8].copy_from_slice(&(v as u64).to_le_bytes());
}
fn hash(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}
fn aligned(n: usize) -> bool {
    n.is_multiple_of(PAGE)
}
fn normalized(b: &[u8], pages: usize, meta: usize) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(&b[..pages]);
    h.update([0; 8192]);
    h.update(&b[pages + 8192..meta + 192]);
    h.update([0; 32]);
    h.update(&b[meta + 224..]);
    h.finalize().into()
}
#[derive(Debug, Clone)]
pub struct Image {
    pub body: usize,
    pub layout_flag: u32,
    pub legacy_body: usize,
    pub pages: usize,
    pub generation: [u8; 32],
    pub sequence: u64,
    pub mode: u32,
    pub archive_bytes: usize,
    meta: usize,
    prefix: usize,
    count: usize,
}
fn records(b: &[u8], pages: usize, g: &[u8; 32]) -> Result<(u64, u32)> {
    let a = format::parse(&b[pages..pages + PAGE], g);
    let c = format::parse(&b[pages + PAGE..pages + 8192], g);
    match (a, c) {
        (Some(a), Some(c)) => {
            require(a.0 != c.0, "duplicate/conflicting sequence")?;
            Ok(if a.0 > c.0 { a } else { c })
        }
        (Some(a), None) | (None, Some(a)) => Ok(a),
        _ => Err("no owned request record"),
    }
}
impl Image {
    /// Strict locator: last page of BOOT4 kernel body, never a magic scan.
    pub fn verify(b: &[u8]) -> Result<Self> {
        require(
            b.len() >= 5 * PAGE && b.len() <= CAP && aligned(b.len()),
            "partition bound",
        )?;
        require(
            &b[..8] == b"ANDROID!"
                && u32at(b, 40) == 4
                && u32at(b, 12) == 0
                && u32at(b, 20) == 1584
                && u32at(b, 1580) == 0,
            "BOOT4",
        )?;
        require(
            b[24..40].iter().chain(&b[1584..4096]).all(|v| *v == 0),
            "BOOT reserved",
        )?;
        let kernel = u32at(b, 8) as usize;
        require(
            kernel >= 3 * PAGE && kernel <= b.len() - 3 * PAGE && aligned(kernel),
            "body bound",
        )?;
        let body = PAGE + kernel;
        let meta = body - PAGE;
        let m = &b[meta..body];
        let layout_flag = u32at(m, 12);
        require(
            &m[..8] == MAGIC && u32at(m, 8) == 1 && matches!(layout_flag, 1..=3),
            "owned v1 locator/flag",
        )?;
        let reserved = if layout_flag == 3 { 248 } else { 224 };
        require(m[reserved..].iter().all(|v| *v == 0), "metadata reserved")?;
        require(num(m, 16)? == b.len() && num(m, 24)? == body, "bound sizes")?;
        require(
            &b[4096..4098] == b"MZ"
                && &b[4152..4156] == b"ARM\x64"
                && u64at(b, 4112) == kernel as u64
                && u64at(b, 4104) == 0
                && u64at(b, 4120) == 10
                && b[4128..4152].iter().all(|v| *v == 0),
            "ARM64",
        )?;
        let legacy = num(m, 32)?;
        let pages = num(m, 40)?;
        let selector = num(m, 48)?;
        let selector_end = num(m, 56)?;
        let payload = num(m, 64)?;
        let payload_end = num(m, 72)?;
        let workspace = num(m, 80)?;
        let workspace_end = num(m, 88)?;
        let archive = num(m, 96)?;
        let archive_bytes = num(m, 104)?;
        let prefix = num(m, 112)?;
        let count = num(m, 120)?;
        require(
            pages >= 2 * PAGE
                && pages <= legacy
                && legacy <= meta
                && aligned(pages)
                && aligned(legacy),
            "legacy/page bound",
        )?;
        require(
            selector == pages + 8192
                && selector_end == selector + 65536
                && payload == selector_end
                && payload_end > payload
                && payload_end <= workspace
                && workspace - payload_end < PAGE
                && aligned(workspace)
                && workspace < legacy
                && workspace < workspace_end
                && if layout_flag == 1 {
                    workspace_end == legacy
                } else {
                    workspace_end == body
                },
            "selector/payload/workspace layout",
        )?;
        if layout_flag == 3 {
            let fdt = num(m, 224)?;
            let size = num(m, 232)?;
            require(
                size == 2 * 1024 * 1024
                    && u64at(m, 240) == 1
                    && aligned(fdt)
                    && fdt >= workspace
                    && fdt <= legacy
                    && size == legacy - fdt
                    && b[fdt..legacy].iter().all(|v| *v == 0),
                "intent FDT workspace/capability",
            )?;
        }
        require(
            archive == legacy
                && archive_bytes <= ARCHIVE_CAP
                && archive_bytes <= meta - archive
                && b[archive + archive_bytes..meta].iter().all(|v| *v == 0),
            "archive bound/padding",
        )?;
        require(
            prefix >= 4160 && prefix <= pages && aligned(prefix) && (1..=65536).contains(&count),
            "restore bounds",
        )?;
        require(
            u32at(b, 4100) == 0x14000000 | (((selector - PAGE - 4) / 4) as u32),
            "entry branch",
        )?;
        let generation = m[128..160].try_into().unwrap();
        let (sequence, mode) = records(b, pages, &generation)?;
        require(
            normalized(&b[..body], pages, meta) == m[192..224],
            "immutable hash",
        )?;
        require(avb::seal(&b[..body], b.len())? == b, "canonical AVB NONE")?;
        let out = Self {
            body,
            layout_flag,
            legacy_body: legacy,
            pages,
            generation,
            sequence,
            mode,
            archive_bytes,
            meta,
            prefix,
            count,
        };
        // Validate archive semantics on inspect too, not just when restoring.
        out.reconstruct(b)?;
        Ok(out)
    }
    fn reconstruct(&self, b: &[u8]) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        out.try_reserve_exact(b.len()).map_err(|_| "restore allocation")?;
        out.resize(b.len(), 0);
        out[..self.prefix].copy_from_slice(&b[..self.prefix]);
        let mut cursor = self.legacy_body;
        let end = cursor + self.archive_bytes;
        let mut previous = 0;
        for i in 0..self.count {
            require(cursor <= end && end - cursor >= 16, "archive record header")?;
            let at = num(b, cursor)?;
            let len = num(b, cursor + 8)?;
            cursor += 16;
            require(
                at >= previous && at <= b.len() && len <= b.len() - at && len <= end - cursor,
                "archive extent",
            )?;
            if i == 0 {
                require(at == 0 && len == 4160, "restore headers")?;
            } else {
                require(
                    at >= self.prefix
                        && aligned(at)
                        && len == PAGE
                        && b[cursor..cursor + len].iter().any(|v| *v != 0),
                    "sparse suffix",
                )?;
            }
            out[at..at + len].copy_from_slice(&b[cursor..cursor + len]);
            cursor += len;
            previous = at + len;
        }
        require(cursor == end, "archive trailing bytes")?;
        require(
            hash(&out) == b[self.meta + 160..self.meta + 192],
            "restored baseline digest",
        )?;
        Ok(out)
    }
    pub fn restore(b: &[u8]) -> Result<Vec<u8>> {
        Self::verify(b)?.reconstruct(b)
    }
    /// Pure offline transformation; caller must bind expected install generation/sequence.
    /// Same target is byte-identical, even at sequence exhaustion.
    pub fn request(b: &[u8], generation: &[u8; 32], sequence: u64, mode: u32) -> Result<Vec<u8>> {
        let v = Self::verify(b)?;
        require(
            &v.generation == generation && v.sequence == sequence && mode <= 1,
            "stale generation/sequence or mode",
        )?;
        if v.mode == mode {
            return Ok(b.to_vec());
        }
        let mut body = b[..v.body].to_vec();
        format::update(&mut body[v.pages..v.pages + 8192], generation, mode)?;
        let out = avb::seal(&body, b.len())?;
        Self::verify(&out)?;
        Ok(out)
    }
}
/// Host conversion helper. Call ONLY after exact legacy catalog/source validation.
/// Not exported as device adoption authority; emitted flag 1 means OFFLINE ONLY.
/// Restores a zero suffix plus nonzero 4K blocks, never a second full image.
pub(crate) fn seal_verified_legacy(
    b: &[u8],
    original: &[u8],
    pages: usize,
    generation: &[u8; 32],
    payload: usize,
    raw_len: usize,
) -> Result<Vec<u8>> {
    require(
        b.len() == original.len() && b.len() <= CAP,
        "conversion sizes",
    )?;
    let legacy = PAGE + u32at(b, 8) as usize;
    let prefix = (PAGE + u32at(original, 8) as usize) & !(PAGE - 1);
    require(
        prefix >= 4160
            && aligned(prefix)
            && prefix <= pages
            && b[4160..prefix] == original[4160..prefix],
        "unchanged original kernel prefix",
    )?;
    let mut archive = Vec::new();
    let mut count = 0;
    for (at, bytes) in core::iter::once((0, &original[..4160])).chain(
        original[prefix..]
            .as_chunks::<PAGE>()
            .0
            .iter()
            .enumerate()
            .filter(|(_, v)| v.iter().any(|x| *x != 0))
            .map(|(i, v)| (prefix + i * PAGE, &v[..])),
    ) {
        require(
            archive.len() + 16 + bytes.len() <= ARCHIVE_CAP,
            "restore archive capacity",
        )?;
        archive.extend_from_slice(&(at as u64).to_le_bytes());
        archive.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        archive.extend_from_slice(bytes);
        count += 1;
    }
    let meta = (legacy + archive.len() + PAGE - 1) & !(PAGE - 1);
    let body = meta + PAGE;
    require(body + 8192 <= b.len() && body <= CAP, "partition capacity")?;
    let mut out = vec![0; body];
    out[..legacy].copy_from_slice(&b[..legacy]);
    out[legacy..legacy + archive.len()].copy_from_slice(&archive);
    out[8..12].copy_from_slice(&((body - PAGE) as u32).to_le_bytes());
    put(&mut out, 4112, body - PAGE);
    let m = &mut out[meta..];
    m[..8].copy_from_slice(MAGIC);
    m[8..12].copy_from_slice(&1u32.to_le_bytes());
    m[12..16].copy_from_slice(&1u32.to_le_bytes());
    for (at, value) in [
        (16, b.len()),
        (24, body),
        (32, legacy),
        (40, pages),
        (48, pages + 8192),
        (56, pages + 8192 + 65536),
        (64, payload),
        (72, payload + raw_len),
        (80, (payload + raw_len + PAGE - 1) & !(PAGE - 1)),
        (88, legacy),
        (96, legacy),
        (104, archive.len()),
        (112, prefix),
        (120, count),
    ] {
        put(m, at, value)
    }
    m[128..160].copy_from_slice(generation);
    m[160..192].copy_from_slice(&hash(original));
    let digest = normalized(&out, pages, meta);
    out[meta + 192..meta + 224].copy_from_slice(&digest);
    let out = avb::seal(&out, b.len())?;
    Image::verify(&out)?;
    Ok(out)
}

#[cfg(test)]
#[path = "owned_tests.rs"]
mod tests;
