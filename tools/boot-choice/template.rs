// SPDX-License-Identifier: GPL-2.0-only
//! Compiler-free, fixed-allocation template packer. No block-device authority.
//! Template instructions/firmware are never relocated or patched. Only original
//! Image/BOOT headers and two explicitly bounded selector data fields change.
use crate::{avb, format, hash, hex, owned::Image, Result};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{fs::OpenOptions, io::Read, os::unix::fs::OpenOptionsExt, path::Path};

const PAGE: usize = 4096;
const CAP: usize = 256 * 1024 * 1024;
const ARCHIVE: usize = 16 * 1024 * 1024;
include!(concat!(env!("OUT_DIR"), "/template_wire.rs"));
fn check(ok: bool, why: &str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(why.into())
    }
}
fn align(n: usize) -> usize {
    (n + PAGE - 1) & !(PAGE - 1)
}
fn u32at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
}
fn u64at(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn be64(b: &[u8], at: usize) -> u64 {
    u64::from_be_bytes(b[at..at + 8].try_into().unwrap())
}
fn put(b: &mut [u8], at: usize, n: usize) {
    b[at..at + 8].copy_from_slice(&(n as u64).to_le_bytes());
}
fn read(path: &Path, cap: usize) -> Result<Vec<u8>> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)
        .map_err(|e| e.to_string())?;
    let m = f.metadata().map_err(|e| e.to_string())?;
    check(
        m.is_file() && m.len() > 0 && m.len() <= cap as u64,
        "template bounded regular file",
    )?;
    let mut b = Vec::new();
    f.take(cap as u64 + 1)
        .read_to_end(&mut b)
        .map_err(|e| e.to_string())?;
    check(b.len() as u64 == m.len(), "template file changed length")?;
    Ok(b)
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Descriptor {
    schema: u32,
    profile: String,
    pages: usize,
    payload: usize,
    native_end: usize,
    archive: usize,
    image_end: usize,
    stack_offset: usize,
    raw_length: usize,
    entry_parameters: usize,
    generation_data: usize,
    selector_sha256: String,
    raw_sha256: String,
    elf_sha256: String,
    config_sha256: String,
    helper_sha256: String,
}
pub struct Template {
    d: Descriptor,
    code: Vec<u8>,
    raw: Vec<u8>,
    elf: Vec<u8>,
    config: Vec<u8>,
    helper: Vec<u8>,
}
impl Template {
    /// Integrity of an explicit supplied template, NOT live installation authority.
    /// A live caller must additionally admit this package from a trusted root.
    pub fn load(dir: &Path) -> Result<Self> {
        Self::load_with(|name, cap| read(&dir.join(name), cap))
    }
    pub(crate) fn load_with(mut read: impl FnMut(&str, usize) -> Result<Vec<u8>>) -> Result<Self> {
        let d: Descriptor =
            serde_json::from_slice(&read("template.json", 16384)?).map_err(|e| e.to_string())?;
        check(
            d.schema == 1 && d.profile == "dodge",
            "template schema/profile",
        )?;
        check(
            d.pages == 48 * 1024 * 1024
                && d.raw_length > 64
                && d.raw_length <= 16 * 1024 * 1024
                && d.raw_length <= d.stack_offset
                && d.stack_offset <= 16 * 1024 * 1024,
            "template footprint limits",
        )?;
        check(
            d.payload == d.pages + 8192 + 65536
                && d.native_end == align(d.payload + d.stack_offset)
                && d.archive == d.native_end + 2 * 1024 * 1024
                && d.image_end == d.archive + ARCHIVE + PAGE
                && d.image_end < CAP - PAGE * 3,
            "template fixed layout",
        )?;
        let code = read("selector.bin", 65536)?;
        let raw = read("firmware.bin", 16 * 1024 * 1024)?;
        let elf = read("firmware.elf", 32 * 1024 * 1024)?;
        let config = read("firmware.config", 1024 * 1024)?;
        let helper = read("boot-choice.efi", 4 * 1024 * 1024)?;
        check(
            hex(&hash(&code)) == d.selector_sha256
                && hex(&hash(&raw)) == d.raw_sha256
                && hex(&hash(&elf)) == d.elf_sha256
                && hex(&hash(&config)) == d.config_sha256
                && hex(&hash(&helper)) == d.helper_sha256
                && raw.len() == d.raw_length,
            "template component digest",
        )?;
        check(
            code.len() >= 16384 + EG_RUNTIME_BYTES
                && code[code.len() - 16384..].iter().all(|v| *v == 0),
            "template materialized stack",
        )?;
        check(
            d.entry_parameters <= code.len() - 16384 - EG_RUNTIME_BYTES
                && d.entry_parameters % 8 == 0
                && d.generation_data <= d.entry_parameters
                && d.entry_parameters - d.generation_data == 32,
            "template data field bounds",
        )?;
        check(
            &code[d.entry_parameters..d.entry_parameters + 8] == b"BCRUN001"
                && code[d.entry_parameters + 8..d.entry_parameters + EG_RUNTIME_BYTES]
                    .iter()
                    .all(|v| *v == 0)
                && code[d.generation_data..d.generation_data + 32]
                    .iter()
                    .all(|v| *v == 0),
            "template pristine parameters",
        )?;
        Ok(Self {
            d,
            code,
            raw,
            elf,
            config,
            helper,
        })
    }
    pub(crate) fn helper(&self) -> &[u8] {
        &self.helper
    }
    pub fn embed(&self, baseline: &[u8]) -> Result<Vec<u8>> {
        self.pack(baseline, 1, 1)
    }
    /// Restore in memory, never nest. Identical template/pref is an exact no-op;
    /// a changed update preserves preference and increments sequence, even when
    /// firmware identity changes generation. Overflow refuses changed updates.
    pub fn update(&self, installed: &[u8]) -> Result<Vec<u8>> {
        let old = Image::verify(installed).map_err(str::to_owned)?;
        let baseline = Image::restore(installed).map_err(str::to_owned)?;
        let same = self.pack(&baseline, old.sequence, old.mode)?;
        // Preference history may have both redundant pages populated. Compare
        // immutable body identity, not a normalized replacement record layout.
        if old.body == PAGE + self.d.image_end
            && same[old.body - PAGE + 192..old.body - PAGE + 224]
                == installed[old.body - PAGE + 192..old.body - PAGE + 224]
        {
            return Ok(installed.to_vec());
        }
        self.pack(
            &baseline,
            old.sequence
                .checked_add(1)
                .ok_or("update sequence exhausted")?,
            old.mode,
        )
    }
    fn pack(&self, original: &[u8], sequence: u64, mode: u32) -> Result<Vec<u8>> {
        let (stored, entry) = baseline(original, self.d.pages)?;
        let d = &self.d;
        let body = PAGE + d.image_end;
        let meta = body - PAGE;
        let archive = PAGE + d.archive;
        check(
            body + 8192 <= original.len(),
            "partition cannot contain fixed template allocation",
        )?;
        let prefix = (PAGE + stored) & !(PAGE - 1);
        let mut records = Vec::new();
        let mut count = 0;
        for (at, bytes) in core::iter::once((0, &original[..4160])).chain(
            original[prefix..]
                .chunks_exact(PAGE)
                .enumerate()
                .filter(|(_, b)| b.iter().any(|v| *v != 0))
                .map(|(i, b)| (prefix + i * PAGE, b)),
        ) {
            check(
                records.len() + 16 + bytes.len() <= ARCHIVE,
                "original restore archive capacity",
            )?;
            records.extend_from_slice(&(at as u64).to_le_bytes());
            records.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            records.extend_from_slice(bytes);
            count += 1;
        }
        let mut h = Sha256::new();
        h.update(original);
        h.update(&self.raw);
        h.update(&self.elf);
        h.update(&self.config);
        let generation: [u8; 32] = h.finalize().into();
        let mut out = vec![0; body];
        out[..PAGE + stored].copy_from_slice(&original[..PAGE + stored]);
        out[8..12].copy_from_slice(&(d.image_end as u32).to_le_bytes());
        let selector = d.pages + 8192;
        out[PAGE + 4..PAGE + 8]
            .copy_from_slice(&(0x14000000u32 | ((selector - 4) / 4) as u32).to_le_bytes());
        put(&mut out, PAGE + 16, d.image_end);
        let mut code = self.code.clone();
        code[d.generation_data..d.generation_data + 32].copy_from_slice(&generation);
        put(&mut code, d.entry_parameters + EG_RUNTIME_ENTRY, entry);
        code[d.entry_parameters + EG_RUNTIME_INVERSE..d.entry_parameters + EG_RUNTIME_INVERSE + 8]
            .copy_from_slice(&(!(entry as u64)).to_le_bytes());
        put(&mut code, d.entry_parameters + EG_RUNTIME_STORED, stored);
        out[PAGE + selector..PAGE + selector + code.len()].copy_from_slice(&code);
        out[PAGE + d.payload..PAGE + d.payload + self.raw.len()].copy_from_slice(&self.raw);
        let pages = PAGE + d.pages;
        // Existing canonical record writer supplies CRC/zero-padding invariants.
        let first = format::record(&generation, sequence, mode);
        out[pages..pages + PAGE].copy_from_slice(&first);
        out[archive..archive + records.len()].copy_from_slice(&records);
        let m = &mut out[meta..];
        m[..8].copy_from_slice(b"OWNBOOT1");
        m[8..12].copy_from_slice(&1u32.to_le_bytes());
        m[12..16].copy_from_slice(&3u32.to_le_bytes());
        for (at, n) in [
            (16, original.len()),
            (24, body),
            (32, archive),
            (40, pages),
            (48, pages + 8192),
            (56, PAGE + d.payload),
            (64, PAGE + d.payload),
            (72, PAGE + d.payload + self.raw.len()),
            (80, align(PAGE + d.payload + self.raw.len())),
            (88, body),
            (96, archive),
            (104, records.len()),
            (112, prefix),
            (120, count),
            (224, PAGE + d.native_end),
            (232, 2 * 1024 * 1024),
            (240, 1),
        ] {
            put(m, at, n)
        }
        m[128..160].copy_from_slice(&generation);
        m[160..192].copy_from_slice(&hash(original));
        let mut h = Sha256::new();
        h.update(&out[..pages]);
        h.update([0; 8192]);
        h.update(&out[pages + 8192..meta + 192]);
        h.update([0; 32]);
        h.update(&out[meta + 224..]);
        out[meta + 192..meta + 224].copy_from_slice(&h.finalize());
        let sealed = avb::seal(&out, original.len()).map_err(str::to_owned)?;
        Image::verify(&sealed).map_err(str::to_owned)?;
        Ok(sealed)
    }
}
/// Structurally admitted kernel-only BOOT4, not an audit of arbitrary future
/// Android/KSU code. Original AVB is archived verbatim, not trusted/re-signed.
fn baseline(b: &[u8], max: usize) -> Result<(usize, usize)> {
    check(
        (5 * PAGE..=CAP).contains(&b.len()) && b.len() % PAGE == 0,
        "baseline partition bound",
    )?;
    check(
        &b[..8] == b"ANDROID!"
            && u32at(b, 40) == 4
            && u32at(b, 20) == 1584
            && u32at(b, 12) == 0
            && u32at(b, 1580) == 0
            && b[24..40].iter().chain(&b[1584..PAGE]).all(|v| *v == 0),
        "kernel-only BOOT4 required",
    )?;
    let stored = u32at(b, 8) as usize;
    check(
        (PAGE..=max).contains(&stored) && stored <= b.len() - PAGE,
        "baseline stored kernel bound",
    )?;
    let end = align(PAGE + stored);
    check(
        end <= b.len() && b[PAGE + stored..end].iter().all(|v| *v == 0),
        "kernel page padding",
    )?;
    check(
        end < PAGE || &b[end - PAGE..end - PAGE + 8] != b"OWNBOOT1",
        "already owned: use update",
    )?;
    check(
        &b[PAGE..PAGE + 2] == b"MZ"
            && &b[PAGE + 56..PAGE + 60] == b"ARM\x64"
            && u64at(b, PAGE + 8) == 0
            && u64at(b, PAGE + 24) == 10
            && b[PAGE + 32..PAGE + 56].iter().all(|v| *v == 0),
        "ARM64 Image admission",
    )?;
    let footprint = u64at(b, PAGE + 16);
    check(
        footprint >= stored as u64 && footprint <= max as u64,
        "baseline footprint exceeds template",
    )?;
    let branch = u32at(b, PAGE + 4);
    check(
        branch & 0xfc000000 == 0x14000000,
        "original entry must be B",
    )?;
    let entry = 4i64 + ((((branch & 0x03ffffff) as i32) << 6 >> 6) as i64) * 4;
    check(
        entry >= 64 && entry < (stored as i64),
        "original branch outside stored kernel",
    )?;
    let f = &b[b.len() - 64..];
    if &f[..4] == b"AVBf" {
        check(
            u32::from_be_bytes(f[4..8].try_into().unwrap()) == 1
                && f[8..12].iter().chain(&f[36..]).all(|v| *v == 0),
            "AVB footer version/reserved",
        )?;
        let original = be64(f, 12);
        let offset = be64(f, 20);
        let size = be64(f, 28);
        check(
            original >= end as u64
                && original <= offset
                && size >= 256
                && offset <= (b.len() - 64) as u64
                && size <= (b.len() - 64) as u64 - offset,
            "baseline AVB bounds",
        )?;
        let v = &b[offset as usize..(offset + size) as usize];
        check(
            &v[..4] == b"AVB0"
                && be64(v, 12)
                    .checked_add(be64(v, 20))
                    .and_then(|n| n.checked_add(256))
                    == Some(size),
            "baseline AVB framing",
        )?;
    } else {
        check(
            b[end..].iter().all(|v| *v == 0),
            "unknown nonzero baseline tail",
        )?;
    }
    Ok((stored, entry as usize))
}

#[cfg(test)]
#[path = "template_tests.rs"]
mod tests;

pub(crate) fn admit_baseline(b: &[u8]) -> Result<()> {
    baseline(b, 48 * 1024 * 1024).map(|_| ())
}
