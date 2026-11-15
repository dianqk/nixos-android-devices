// SPDX-License-Identifier: GPL-2.0-only
//! Owned-image engine and explicitly bound Linux device adapter. No reboot capability.
extern crate alloc;
pub mod avb;
pub mod context;
pub mod provenance;
pub mod device;
pub mod format;
pub mod owned;
pub mod template;
mod trusted_template;
pub mod live_status;
mod live_fs;
mod media;
mod install_transaction;
#[path = "../../pkgs/boot-choice-efi/transaction.rs"]
pub(crate) mod transaction;
#[path = "../../pkgs/boot-choice-efi/authority.rs"]
pub(crate) mod authority;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::io::{self, Read, Seek, SeekFrom, Write};
pub type Result<T> = std::result::Result<T, String>;
fn check(ok: bool, message: &str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(message.into())
    }
}
pub fn hash(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}
pub fn hex(b: &[u8]) -> String {
    b.iter().map(|v| format!("{v:02x}")).collect()
}
fn number(v: &Value) -> Result<usize> {
    usize::try_from(v.as_u64().ok_or("missing integer")?).map_err(|_| "integer overflow".into())
}
fn le32(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(b[at..at + 4].try_into().unwrap())
}
fn le64(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn align(n: usize) -> usize {
    (n + 4095) & !4095
}
const LIMIT: usize = 256 * 1024 * 1024;
pub fn seal(body: &[u8], size: usize) -> Result<Vec<u8>> {
    avb::seal(body, size).map_err(str::to_owned)
}

/// Trusted catalog + exact source inputs are the offline authority. Hashes are
/// integrity, NOT authentication of a maliciously replaced catalog/source set.
#[derive(Clone, serde::Serialize)]
pub struct Owned {
    size: usize,
    body: usize,
    pages: usize,
    generation: [u8; 32],
    immutable: String,
}
impl Owned {
    pub fn from_sources(
        c: &Value,
        original: &[u8],
        raw: &[u8],
        elf: &[u8],
        config: &[u8],
    ) -> Result<Self> {
        check(c["format"] == "BOOT-EXPERIMENT-V1", "catalog format")?;
        check(
            original.len() >= 8192
                && original.len() <= LIMIT
                && original.len().is_multiple_of(4096),
            "original size",
        )?;
        check(
            &original[..8] == b"ANDROID!" && le32(original, 40) == 4,
            "original BOOT4",
        )?;
        let b = &c["selector_manifest"]["binding"];
        for (key, bytes) in [
            ("original_sha256", original),
            ("payload_sha256", raw),
            ("elf_sha256", elf),
            ("config_sha256", config),
        ] {
            check(
                b[key].as_str() == Some(&hex(&hash(bytes))),
                "source digest mismatch",
            )?;
        }
        check(
            c["original"]["sha256"].as_str() == Some(&hex(&hash(original))),
            "original authority",
        )?;
        let mut sha = Sha256::new();
        for bytes in [original, raw, elf, config] {
            sha.update(bytes);
        }
        let generation: [u8; 32] = sha.finalize().into();
        check(
            b["request_generation"].as_str() == Some(&hex(&generation)),
            "generation binding",
        )?;
        let expanded = number(&c["expanded_image_size"])?;
        let pages = number(&b["symbols"]["eg_request_pages"])?;
        check(
            &original[4096 + 56..4096 + 60] == b"ARM\x64"
                && le32(original, 4096) & 0xffff == 0x5a4d,
            "original ARM64 MZ",
        )?;
        let old_extent = usize::try_from(le64(original, 4096 + 16)).map_err(|_| "old extent")?;
        check(
            old_extent <= LIMIT
                && pages == align(old_extent)
                && expanded <= LIMIT
                && pages + 8192 < expanded,
            "request layout",
        )?;
        check(
            number(&c["selector_offset"])? == pages + 8192
                && number(&b["symbols"]["eg_image_end"])? == expanded,
            "selector layout",
        )?;
        check(
            expanded.is_multiple_of(4096) && expanded + 4096 + 8192 <= original.len(),
            "expanded bounds",
        )?;
        let immutable = c["immutable_body_sha256"]
            .as_str()
            .ok_or("missing immutable binding")?
            .to_owned();
        check(immutable.len() == 64, "immutable digest")?;
        Ok(Self {
            size: original.len(),
            body: expanded + 4096,
            pages: pages + 4096,
            generation,
            immutable,
        })
    }
    pub fn verify(&self, image: &[u8]) -> Result<()> {
        check(image.len() == self.size, "partition exact size")?;
        check(
            &image[..8] == b"ANDROID!"
                && le32(image, 40) == 4
                && le32(image, 8) as usize == self.body - 4096
                && le32(image, 12) == 0
                && le32(image, 20) == 1584
                && le32(image, 1580) == 0,
            "strict BOOT4",
        )?;
        check(
            image[4096..4098] == *b"MZ"
                && &image[4152..4156] == b"ARM\x64"
                && le64(image, 4112) == (self.body - 4096) as u64
                && le64(image, 4104) == 0
                && le64(image, 4120) == 10,
            "ARM64 extent/flags",
        )?;
        check(
            image[24..40].iter().all(|v| *v == 0) && image[1584..4096].iter().all(|v| *v == 0),
            "BOOT reserved/padding",
        )?;
        // Image+4 must branch to the selector immediately after the pages.
        let target = self.pages + 8192 - 4096;
        check(
            le32(image, 4100) == 0x14000000 | (((target - 4) / 4) as u32),
            "selector branch",
        )?;
        let mut immutable = image[..self.body].to_vec();
        immutable[self.pages..self.pages + 8192].fill(0);
        check(
            hex(&hash(&immutable)) == self.immutable,
            "immutable body mismatch",
        )?;
        check(
            seal(&image[..self.body], self.size)? == image,
            "invalid/noncanonical AVB NONE",
        )?;
        // At least one valid owned record is required for mutation. Firmware
        // fallback semantics for corrupt pages do not grant writer ownership.
        let p = &image[self.pages..self.pages + 8192];
        check(
            format::parse(&p[..4096], &self.generation).is_some()
                || format::parse(&p[4096..], &self.generation).is_some(),
            "no owned record",
        )?;
        Ok(())
    }
    pub fn prepare(&self, image: &[u8], mode: u32) -> Result<Vec<u8>> {
        self.verify(image)?;
        let mut body = image[..self.body].to_vec();
        format::update(
            &mut body[self.pages..self.pages + 8192],
            &self.generation,
            mode,
        )?;
        let next = seal(&body, self.size)?;
        self.verify(&next)?;
        Ok(next)
    }
}

/// Explicit offline legacy migration. Exact trusted catalog and all native sources
/// remain mandatory for first sealing; self-description never grants authority.
pub fn seal_legacy(
    c: &Value,
    original: &[u8],
    raw: &[u8],
    elf: &[u8],
    config: &[u8],
    image: &[u8],
) -> Result<Vec<u8>> {
    let old = Owned::from_sources(c, original, raw, elf, config)?;
    old.verify(image)?;
    check(
        c["output_sha256"].as_str() == Some(&hex(&hash(image))),
        "exact legacy catalog image",
    )?;
    owned::seal_verified_legacy(
        image,
        original,
        old.pages,
        &old.generation,
        number(&c["payload_offset"])? + 4096,
        raw.len(),
    )
    .map_err(str::to_owned)
}

/// Sync is explicit so tests can fail every durability boundary. Implementors
/// must provide exclusive access and a stable identity. No block implementation
/// belongs in the engine: the Linux device module supplies ROM/slot/install,
/// PARTUUID, dev_t, GPT/BCB and power validation, never pathname inference.
pub trait Storage: Read + Write + Seek {
    fn sync(&mut self) -> io::Result<()>;
}
impl Storage for std::fs::File {
    fn sync(&mut self) -> io::Result<()> {
        self.sync_all()
    }
}
fn read_all<S: Storage>(s: &mut S, size: usize) -> io::Result<Vec<u8>> {
    if s.seek(SeekFrom::End(0))? != size as u64 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "size changed"));
    }
    s.seek(SeekFrom::Start(0))?;
    let mut b = vec![0; size];
    s.read_exact(&mut b)?;
    Ok(b)
}
fn write_at<S: Storage>(s: &mut S, at: usize, b: &[u8]) -> io::Result<()> {
    s.seek(SeekFrom::Start(at as u64))?;
    s.write_all(b)
}
/// Caller supplies a new, empty durable ordinary-file journal. Entire original
/// is staged and read back BEFORE mutation. Keep it after success or error.
/// Errors attempt exact restoration; rollback failure is explicitly distinct.
/// Power loss between page and AVB updates is NOT atomic or supported.
pub fn transact<S: Storage, J: Storage>(s: &mut S, j: &mut J, o: &Owned, mode: u32) -> Result<()> {
    transact_with_gate(s, j, o, mode, || Ok(()))
}
/// Device adapter rechecks live platform gates after durable journal staging,
/// immediately before the first mutation. Gate failure never initiates rollback.
pub fn transact_with_gate<S: Storage, J: Storage>(
    s: &mut S,
    j: &mut J,
    o: &Owned,
    mode: u32,
    mut gate: impl FnMut() -> Result<()>,
) -> Result<()> {
    let before = read_all(s, o.size).map_err(|e| e.to_string())?;
    let next = o.prepare(&before, mode)?;
    check(
        j.seek(SeekFrom::End(0)).map_err(|e| e.to_string())? == 0,
        "journal not empty",
    )?;
    write_at(j, 0, &before)
        .and_then(|_| j.sync())
        .map_err(|e| format!("journal: {e}"))?;
    check(
        read_all(j, o.size).map_err(|e| e.to_string())? == before,
        "journal readback",
    )?;
    // Revalidate immediately before the first write; catches concurrent changes
    // but does not replace the exclusive-access requirement.
    check(
        read_all(s, o.size).map_err(|e| e.to_string())? == before,
        "target changed",
    )?;
    gate()?;
    let run = (|| -> io::Result<()> {
        // Only the older/invalid page changes; never touch the surviving page.
        for at in [o.pages, o.pages + 4096] {
            if before[at..at + 4096] != next[at..at + 4096] {
                write_at(s, at, &next[at..at + 4096])?;
            }
        }
        s.sync()?;
        write_at(s, o.body, &next[o.body..])?;
        s.sync()?;
        let actual = read_all(s, o.size)?;
        if actual != next || o.verify(&actual).is_err() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "whole bundle readback",
            ));
        }
        Ok(())
    })();
    if let Err(e) = run {
        let rollback = write_at(s, 0, &before)
            .and_then(|_| s.sync())
            .and_then(|_| {
                if read_all(s, o.size)? != before {
                    Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "rollback readback",
                    ))
                } else {
                    Ok(())
                }
            });
        return Err(match rollback {
            Ok(()) => format!("transaction failed; original restored: {e}"),
            Err(r) => format!("UNRECOVERED; retain journal; no reboot: {e}; rollback: {r}"),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests;
