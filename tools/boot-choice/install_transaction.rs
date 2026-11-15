// SPDX-License-Identifier: GPL-2.0-only
//! Full-image undo operation, distinct from two-region preference journals.
//! No atomic/power-loss guarantee before OEM AVB/EFI. Never writes a slot peer.
use crate::{hash, hex, owned::Image, template, Result};
use serde::{Deserialize, Serialize};
const PAGE: usize = 4096;
pub(crate) const CAP: usize = 320 * 1024 * 1024;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Identity {
    pub disk: [u8; 16],
    pub part: [u8; 16],
    pub esp: String,
    pub controller: String,
    pub lba: u64,
    pub block: usize,
    pub size: usize,
    pub slot: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct State {
    pub generation: [u8; 32],
    pub sequence: u64,
    pub mode: u32,
}
fn state(b: &[u8]) -> Option<State> {
    Image::verify(b)
        .ok()
        .filter(|v| v.layout_flag == 3)
        .map(|v| State {
            generation: v.generation,
            sequence: v.sequence,
            mode: v.mode,
        })
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct FileChange {
    pub name: String,
    pub before: Option<Vec<u8>>,
    pub after: Option<Vec<u8>>,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Header {
    schema: u32,
    identity: Identity,
    operation: String,
    old_hash: [u8; 32],
    new_hash: [u8; 32],
    old_state: Option<State>,
    new_state: Option<State>,
    files: Vec<FileChange>,
    offsets: Vec<usize>,
}
fn check(b: bool, e: &str) -> Result<()> {
    if b {
        Ok(())
    } else {
        Err(e.into())
    }
}
pub(crate) trait Io {
    fn probe(&mut self) -> Result<()>;
    fn read(&mut self) -> Result<Vec<u8>>;
    fn write(&mut self, at: usize, b: &[u8]) -> Result<()>;
    fn flush(&mut self) -> Result<()>;
    fn journal_read(&mut self) -> Result<Option<Vec<u8>>>;
    fn journal_create(&mut self, b: &[u8]) -> Result<()>;
    fn journal_remove(&mut self) -> Result<()>;
    fn file_read(&mut self, name: &str) -> Result<Option<Vec<u8>>>;
    fn file_replace(&mut self, name: &str, b: Option<&[u8]>, nonce: &str) -> Result<()>;
    fn scratch_read(&mut self, name: &str, nonce: &str) -> Result<Option<Vec<u8>>>;
    fn scratch_remove(&mut self, name: &str, nonce: &str) -> Result<()>;
}
fn admissible(b: &[u8], expected: &Option<State>) -> Result<()> {
    match expected {
        Some(s) => check(
            state(b).as_ref() == Some(s),
            "owned full-image state mismatch",
        ),
        None => template::admit_baseline(b),
    }
}
fn files_valid(files: &[FileChange]) -> Result<()> {
    check(files.len() <= 3, "full-image file plan bound")?;
    let mut seen = Vec::new();
    for f in files {
        check(
            [
                crate::live_fs::HELPER,
                crate::live_fs::MENU,
                crate::live_fs::RECEIPT,
            ]
            .contains(&f.name.as_str())
                && !seen.contains(&f.name),
            "owned ESP file allowlist/duplicate",
        )?;
        check(
            f.before
                .as_ref()
                .is_none_or(|b| b.len() <= 24 * 1024 * 1024)
                && f.after.as_ref().is_none_or(|b| b.len() <= 24 * 1024 * 1024),
            "ESP file plan size",
        )?;
        seen.push(f.name.clone())
    }
    Ok(())
}
fn encode(h: &Header, old: &[u8]) -> Result<Vec<u8>> {
    let json = serde_json::to_vec(h).map_err(|e| e.to_string())?;
    check(
        json.len() <= 64 * 1024 * 1024,
        "file journal metadata bound",
    )?;
    let mut b = b"BCFULL01".to_vec();
    b.extend_from_slice(&(json.len() as u64).to_le_bytes());
    b.extend_from_slice(&json);
    for at in &h.offsets {
        b.extend_from_slice(&old[*at..*at + PAGE])
    }
    check(b.len() + 32 <= CAP, "full undo capacity")?;
    b.extend_from_slice(&hash(&b));
    Ok(b)
}
fn decode(b: &[u8], identity: &Identity) -> Result<(Header, usize)> {
    check(
        (48..=CAP).contains(&b.len())
            && &b[..8] == b"BCFULL01"
            && hash(&b[..b.len() - 32]) == b[b.len() - 32..],
        "full journal checksum/framing",
    )?;
    let n = usize::try_from(u64::from_le_bytes(b[8..16].try_into().unwrap()))
        .map_err(|_| "journal metadata overflow")?;
    check(
        n <= 64 * 1024 * 1024 && n <= b.len() - 48,
        "full journal header bound",
    )?;
    let h: Header = serde_json::from_slice(&b[16..16 + n]).map_err(|e| e.to_string())?;
    check(
        h.schema == 1
            && &h.identity == identity
            && ["install", "update", "restore"].contains(&h.operation.as_str()),
        "foreign full journal identity/operation",
    )?;
    check(
        identity.size <= 256 * 1024 * 1024
            && identity.size >= 5 * PAGE
            && identity.size % PAGE == 0
            && matches!(identity.block, 512 | 4096)
            && (1..=2).contains(&identity.slot),
        "full target geometry",
    )?;
    files_valid(&h.files)?;
    check(
        h.offsets.len() <= identity.size / PAGE
            && h.offsets
                .len()
                .checked_mul(PAGE)
                .and_then(|x| x.checked_add(n + 48))
                == Some(b.len()),
        "full journal extent count",
    )?;
    let mut previous = None;
    for at in &h.offsets {
        check(
            *at % PAGE == 0 && *at <= identity.size - PAGE && previous.is_none_or(|p| p < *at),
            "full undo extents",
        )?;
        previous = Some(*at)
    }
    Ok((h, 16 + n))
}
fn check_files(io: &mut impl Io, files: &[FileChange], recover: bool) -> Result<()> {
    for f in files {
        let now = io.file_read(&f.name)?;
        check(
            now == f.before || (recover && now == f.after),
            "owned ESP file changed/foreign",
        )?
    }
    Ok(())
}
fn apply_files(io: &mut impl Io, h: &Header, new: bool) -> Result<()> {
    let nonce = &hex(&h.new_hash)[..16];
    for f in &h.files {
        let now = io.file_read(&f.name)?;
        check(
            now == f.before || now == f.after,
            "owned ESP file changed during operation",
        )?;
        io.scratch_remove(&f.name, nonce)?;
        let expected = if new { &f.after } else { &f.before };
        if io.file_read(&f.name)? != *expected {
            io.file_replace(&f.name, expected.as_deref(), nonce)?
        }
        check(
            io.file_read(&f.name)? == *expected,
            "ESP file exact readback",
        )?
    }
    Ok(())
}
fn write_pages(io: &mut impl Io, image: &[u8], offsets: &[usize]) -> Result<()> {
    for at in offsets
        .iter()
        .filter(|at| **at != 0)
        .chain(offsets.iter().filter(|at| **at == 0))
    {
        io.write(*at, &image[*at..*at + PAGE])?;
    }
    io.flush()?;
    check(io.read()? == image, "full-image exact readback")
}
fn source_context(h: &Header, current_new: bool, context: Option<&State>) -> Result<()> {
    if let Some(c) = context {
        check(
            h.old_state.as_ref() == Some(c) || (current_new && h.new_state.as_ref() == Some(c)),
            "stale Linux full-operation provenance",
        )?
    }
    Ok(())
}
/// Recover before owned verification. Only positively bound GPT/slot/controller
/// may supply identity; torn bytes are reconstructed and validated before writes.
pub(crate) fn recover(
    io: &mut impl Io,
    identity: &Identity,
    context: Option<&State>,
) -> Result<bool> {
    let Some(bytes) = io.journal_read()? else {
        return Ok(false);
    };
    let (h, start) = decode(&bytes, identity)?;
    let current = io.read()?;
    check(current.len() == identity.size, "full image size")?;
    let committed = hash(&current) == h.new_hash;
    source_context(&h, committed, context)?;
    let mut old = current.clone();
    for (i, at) in h.offsets.iter().enumerate() {
        old[*at..*at + PAGE].copy_from_slice(&bytes[start + i * PAGE..start + (i + 1) * PAGE])
    }
    check(hash(&old) == h.old_hash, "full undo original digest")?;
    admissible(&old, &h.old_state)?;
    check_files(io, &h.files, true)?;
    if committed {
        admissible(&current, &h.new_state)?;
        if h.operation == "restore" {
            check(
                Image::restore(&old).map_err(str::to_owned)? == current,
                "restore original identity",
            )?
        }
    }
    io.probe()?;
    if committed {
        apply_files(io, &h, true)?
    } else {
        if current != old {
            write_pages(io, &old, &h.offsets)?
        }
        apply_files(io, &h, false)?
    }
    io.journal_remove()?;
    Ok(true)
}
/// Caller obtains old/new from the same held actual booted target and validated
/// native template. Equal bytes+files are a true no-op: no probe/sync/journal.
pub(crate) fn execute(
    io: &mut impl Io,
    identity: &Identity,
    context: Option<&State>,
    operation: &str,
    old: &[u8],
    new: &[u8],
    files: Vec<FileChange>,
) -> Result<()> {
    check(
        io.journal_read()?.is_none(),
        "pending full journal must recover first",
    )?;
    check(
        old.len() == identity.size && new.len() == identity.size,
        "full operation exact size",
    )?;
    files_valid(&files)?;
    let old_state = state(old);
    let new_state = state(new);
    admissible(old, &old_state)?;
    admissible(new, &new_state)?;
    check(
        ["install", "update", "restore"].contains(&operation),
        "full operation",
    )?;
    if operation == "restore" {
        check(
            old_state.is_some() && Image::restore(old).map_err(str::to_owned)? == new,
            "restore original",
        )?
    } else {
        check(new_state.is_some(), "new owned image required")?
    }
    let h = Header {
        schema: 1,
        identity: identity.clone(),
        operation: operation.into(),
        old_hash: hash(old),
        new_hash: hash(new),
        old_state,
        new_state,
        files,
        offsets: (0..old.len())
            .step_by(PAGE)
            .filter(|at| old[*at..*at + PAGE] != new[*at..*at + PAGE])
            .collect(),
    };
    source_context(&h, false, context)?;
    check(io.read()? == old, "target changed before prepare")?;
    check_files(io, &h.files, false)?;
    if old == new && h.files.iter().all(|f| f.before == f.after) {
        return Ok(());
    }
    let nonce = hex(&h.new_hash);
    for f in &h.files {
        check(
            io.scratch_read(&f.name, &nonce[..16])?.is_none(),
            "foreign ESP scratch retained",
        )?
    }
    let bytes = encode(&h, old)?;
    io.probe()?;
    io.journal_create(&bytes)?;
    check(
        io.journal_read()?.as_deref() == Some(bytes.as_slice()),
        "durable full undo readback",
    )?;
    let result = (|| {
        apply_files(io, &h, true)?;
        write_pages(io, new, &h.offsets)
    })();
    if let Err(error) = result {
        if write_pages(io, old, &h.offsets)
            .and_then(|_| apply_files(io, &h, false))
            .is_err()
        {
            return Err(format!("{error}; ROLLBACK FAILED, full undo retained"));
        }
        io.journal_remove()?;
        return Err(format!("{error}; restored original operation state"));
    }
    io.journal_remove()
}
#[cfg(test)]
#[path = "install_transaction_tests.rs"]
pub(crate) mod tests;
