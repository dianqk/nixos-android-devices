// SPDX-License-Identifier: GPL-2.0-only
use super::*;
fn fixture() -> (Vec<u8>, Vec<u8>) {
    let mut original = vec![0; 512 * 1024];
    original[..8].copy_from_slice(b"ANDROID!");
    original[8..12].copy_from_slice(&8192u32.to_le_bytes());
    original[20..24].copy_from_slice(&1584u32.to_le_bytes());
    original[40..44].copy_from_slice(&4u32.to_le_bytes());
    original[4096..4098].copy_from_slice(b"MZ");
    original[4152..4156].copy_from_slice(b"ARM\x64");
    put(&mut original, 4112, 8192);
    put(&mut original, 4120, 10);
    original[5000] = 42;
    original[18000] = 19;
    original[512 * 1024 - 1] = 9;
    let mut body = vec![0; 128 * 1024];
    body[..12288].copy_from_slice(&original[..12288]);
    let pages = 16384;
    let selector = pages + 8192;
    let n = body.len() - 4096;
    body[8..12].copy_from_slice(&(n as u32).to_le_bytes());
    put(&mut body, 4112, n);
    body[4100..4104]
        .copy_from_slice(&(0x14000000u32 | ((selector - 4096 - 4) / 4) as u32).to_le_bytes());
    body[pages..pages + 4096].copy_from_slice(&format::record(&[7; 32], 1, 1));
    let legacy = avb::seal(&body, original.len()).unwrap();
    assert!(Image::verify(&legacy).is_err());
    let owned =
        seal_verified_legacy(&legacy, &original, pages, &[7; 32], selector + 65536, 4096).unwrap();
    (owned, original)
}
fn reseal(mut b: Vec<u8>) -> Vec<u8> {
    let body = 4096 + u32at(&b, 8) as usize;
    let meta = body - 4096;
    let pages = 16384;
    let h = normalized(&b[..body], pages, meta);
    b[meta + 192..meta + 224].copy_from_slice(&h);
    avb::seal(&b[..body], b.len()).unwrap()
}
#[test]
fn roundtrip_requests_and_staleness() {
    let (b, o) = fixture();
    let v = Image::verify(&b).unwrap();
    assert_eq!(Image::restore(&b).unwrap(), o);
    assert_eq!(Image::request(&b, &[7; 32], 1, 1).unwrap(), b);
    assert!(Image::request(&b, &[8; 32], 1, 0).is_err());
    assert!(Image::request(&b, &[7; 32], 2, 0).is_err());
    let a = Image::request(&b, &[7; 32], 1, 0).unwrap();
    assert_eq!(Image::verify(&a).unwrap().sequence, 2);
    assert_eq!(Image::restore(&a).unwrap(), o);
    let c = Image::request(&a, &[7; 32], 2, 1).unwrap();
    assert_eq!(Image::restore(&c).unwrap(), o);
    assert_eq!(v.archive_bytes, 4160 + 16 + 2 * (4096 + 16));
}
#[test]
fn corruption_and_canonical_tail() {
    let (b, _) = fixture();
    let v = Image::verify(&b).unwrap();
    for at in [
        0,
        8,
        24,
        40,
        4096,
        4112,
        4128,
        5000,
        v.legacy_body,
        v.meta,
        v.meta + 8,
        v.meta + 12,
        v.meta + 16,
        v.meta + 128,
        v.meta + 160,
        v.meta + 192,
        v.meta + 224,
        v.body,
        b.len() - 1,
    ] {
        let mut c = b.clone();
        c[at] ^= 1;
        assert!(Image::verify(&c).is_err(), "{at}");
    }
    for (at, value) in [
        (32, usize::MAX),
        (40, usize::MAX),
        (48, 0),
        (56, 0),
        (64, 0),
        (72, usize::MAX),
        (80, 0),
        (88, 0),
        (96, 0),
        (104, usize::MAX),
        (112, 0),
        (120, 65537),
    ] {
        let mut c = b.clone();
        put(&mut c, v.meta + at, value);
        assert!(Image::verify(&reseal(c)).is_err(), "{at}");
    }
    // Authenticating metadata cannot turn a malformed archive into a valid one.
    let mut c = b.clone();
    put(&mut c, v.legacy_body, 1);
    assert!(Image::verify(&reseal(c)).is_err());
}
#[test]
fn redundant_records_and_exhaustion() {
    let (b, _) = fixture();
    let v = Image::verify(&b).unwrap();
    for mode in [0, 1] {
        let mut c = b.clone();
        c[v.pages + 4096..v.pages + 8192].copy_from_slice(&format::record(&[7; 32], 1, mode));
        assert!(Image::verify(&reseal(c)).is_err());
    }
    let mut c = b.clone();
    c[v.pages..v.pages + 4096].copy_from_slice(&format::record(&[7; 32], u64::MAX, 1));
    let c = reseal(c);
    assert!(Image::request(&c, &[7; 32], u64::MAX, 0).is_err());
    assert_eq!(Image::request(&c, &[7; 32], u64::MAX, 1).unwrap(), c);
    let mut c = b.clone();
    c[v.pages + 4096] = 3;
    let c = reseal(c);
    assert!(Image::verify(&c).is_ok());
    let mut c = b.clone();
    c[v.pages..v.pages + 4096].fill(0);
    assert!(Image::verify(&reseal(c)).is_err());
}
#[test]
fn capacity_refused() {
    let (b, mut o) = fixture();
    o[12288..].fill(7);
    let v = Image::verify(&b).unwrap();
    assert!(
        seal_verified_legacy(&b, &o, v.pages, &v.generation, v.pages + 8192 + 65536, 4096).is_err()
    );
}

#[test]
fn prelinked_flag_bounds_and_declaration() {
    let (mut b, original) = fixture();
    let body = 4096 + u32at(&b, 8) as usize;
    let meta = body - 4096;
    b[meta + 12..meta + 16].copy_from_slice(&2u32.to_le_bytes());
    // Merely changing the flag cannot reinterpret the offline allocation.
    assert!(Image::verify(&reseal(b.clone())).is_err());
    put(&mut b, meta + 88, body);
    let b = reseal(b);
    assert_eq!(Image::verify(&b).unwrap().layout_flag, 2);
    assert_eq!(Image::restore(&b).unwrap(), original);
    for (at, value) in [
        (12, 3),
        (88, body + 4096),
        (96, body),
        (104, usize::MAX),
        (64, body),
        (56, body),
        (32, body),
    ] {
        let mut bad = b.clone();
        if at == 12 {
            bad[meta + at..meta + at + 4].copy_from_slice(&(value as u32).to_le_bytes());
        } else {
            put(&mut bad, meta + at, value);
        }
        assert!(Image::verify(&reseal(bad)).is_err(), "field {at}");
    }
    for at in [8, 4100, 4112] {
        let mut bad = b.clone();
        bad[at] ^= 4;
        assert!(Image::verify(&bad).is_err());
    }
}
