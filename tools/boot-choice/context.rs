// SPDX-License-Identifier: GPL-2.0-only
//! Strict booted-context wire decoder. This alone never grants disk authority.
pub type Result<T> = core::result::Result<T, &'static str>;
fn check(b: bool, e: &'static str) -> Result<()> {
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
fn crc(b: &[u8], zero: core::ops::Range<usize>) -> u32 {
    let mut c = !0u32;
    for (i, v) in b.iter().enumerate() {
        c ^= if zero.contains(&i) { 0 } else { *v as u32 };
        for _ in 0..8 {
            c = (c >> 1) ^ (0xedb88320u32.wrapping_mul(c & 1));
        }
    }
    !c
}
#[derive(Debug)]
pub struct Context {
    pub generation: [u8; 32],
    pub sequence: u64,
    pub slot: u32,
    pub stored: u32,
    pub selected: u32,
    pub read_only: bool,
}
pub fn decode(b: &[u8]) -> Result<Context> {
    check(b.len() == 96, "context size")?;
    check(
        u32at(b, 0) == 1 && u32at(b, 4) == 96 && u32at(b, 8) == 1 && u32at(b, 12) == 0,
        "context ABI",
    )?;
    let t = &b[16..];
    check(
        &t[..8] == b"BCINTENT"
            && u32at(t, 8) == 1
            && u32at(t, 12) == 80
            && u32at(t, 76) == crc(t, 76..80),
        "wire",
    )?;
    check(
        t[16..48].iter().any(|x| *x != 0)
            && u64at(t, 48) != 0
            && (1..=2).contains(&u32at(t, 68))
            && u32at(t, 72) == 1,
        "slot/generation/sequence",
    )?;
    check(
        u32at(t, 56) <= 1
            && u32at(t, 60) <= 1
            && ((u32at(t, 64) == 2 && u32at(t, 60) == 1)
                || u32at(t, 64) == u32::from(u32at(t, 56) != u32at(t, 60))),
        "intent",
    )?;
    Ok(Context {
        generation: t[16..48].try_into().unwrap(),
        sequence: u64at(t, 48),
        slot: u32at(t, 68),
        stored: u32at(t, 56),
        selected: u32at(t, 60),
        read_only: u32at(t, 64) == 2,
    })
}
