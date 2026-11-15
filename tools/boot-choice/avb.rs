// SPDX-License-Identifier: GPL-2.0-only
//! Portable canonical AVB NONE encoder shared by legacy and self-described images.
use alloc::vec::Vec;
use sha2::{Digest, Sha256};
type Result<T> = core::result::Result<T, &'static str>;
fn check(ok: bool, message: &'static str) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(message)
    }
}
fn hash(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}
fn be(b: &mut [u8], at: usize, value: u64) {
    b[at..at + 8].copy_from_slice(&value.to_be_bytes());
}
fn align(n: usize) -> usize {
    (n + 4095) & !4095
}
const LIMIT: usize = 256 * 1024 * 1024;

/// One intentionally narrow canonical encoding: avbtool 1.4.0, NONE, boot,
/// SHA256, empty salt, no properties, no flags/rollback. No arbitrary template
/// fields are carried forward and an invalid input hash is never repaired.
pub fn seal(body: &[u8], size: usize) -> Result<Vec<u8>> {
    check(body.len() <= LIMIT, "AVB body bound")?;
    let at = align(body.len());
    check(
        size <= LIMIT
            && body.len() <= LIMIT
            && at + 4096 + 4096 <= size
            && size.is_multiple_of(4096),
        "AVB size",
    )?;
    let mut out = Vec::new();
    out.try_reserve_exact(size).map_err(|_| "AVB allocation")?;
    out.resize(size, 0);
    out[..body.len()].copy_from_slice(body);
    let v = &mut out[at..at + 448];
    v[..4].copy_from_slice(b"AVB0");
    v[7] = 1; // required libavb major
    be(v, 20, 192); // auxiliary block
    be(v, 64, 168); // public key offset (empty)
    be(v, 80, 168); // public key metadata offset (empty)
    be(v, 104, 168); // descriptor size
    v[128..142].copy_from_slice(b"avbtool 1.4.0\0");
    be(v, 256, 2); // hash descriptor tag
    be(v, 264, 152);
    be(v, 272, body.len() as u64);
    v[280..286].copy_from_slice(b"sha256");
    v[315] = 4; // partition name length
    v[323] = 32; // digest length
    v[388..392].copy_from_slice(b"boot");
    v[392..424].copy_from_slice(&hash(body));
    let f = &mut out[size - 64..];
    f[..4].copy_from_slice(b"AVBf");
    f[7] = 1;
    be(f, 12, body.len() as u64);
    be(f, 20, at as u64);
    be(f, 28, 448);
    Ok(out)
}
