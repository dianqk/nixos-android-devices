//! Structural Android/ARM64/FDT validation, shared in spirit with the host checker.
use anyhow::{bail, ensure, Context, Result};
use std::io::Read;
fn word(b: &[u8], n: usize, be: bool) -> Result<usize> {
    let bytes: [u8; 4] = b.get(n..n + 4).context("truncated word")?.try_into()?;
    Ok(if be {
        u32::from_be_bytes(bytes)
    } else {
        u32::from_le_bytes(bytes)
    } as usize)
}
fn cstring(b: &[u8], start: usize, end: usize) -> Result<(&[u8], usize)> {
    ensure!(start < end && end <= b.len(), "invalid string bounds");
    let end = start
        + b[start..end]
            .iter()
            .position(|v| *v == 0)
            .context("unterminated string")?;
    Ok((&b[start..end], end))
}
fn align(n: usize, page: usize) -> usize {
    n.div_ceil(page) * page
}
fn dtb(b: &[u8], compatible: &str) -> Result<()> {
    ensure!(
        b.len() >= 40
            && word(b, 0, true)? == 0xd00dfeed
            && word(b, 4, true)? == b.len()
            && word(b, 20, true)? == 17,
        "invalid DTB header"
    );
    let (mut pos, strings, stringsize, size) = (
        word(b, 8, true)?,
        word(b, 12, true)?,
        word(b, 32, true)?,
        word(b, 36, true)?,
    );
    let end = pos.checked_add(size).context("DTB overflow")?;
    ensure!(
        pos >= 40
            && pos % 4 == 0
            && end <= b.len()
            && strings >= 40
            && strings
                .checked_add(stringsize)
                .is_some_and(|n| n <= b.len()),
        "invalid DTB bounds"
    );
    let mut depth = 0usize;
    let mut seen = false;
    let mut matched = false;
    let mut property = false;
    while pos + 4 <= end {
        let token = word(b, pos, true)?;
        pos += 4;
        match token {
            1 => {
                let (name, last) = cstring(b, pos, end)?;
                if depth == 0 {
                    ensure!(!seen && name.is_empty(), "invalid DTB root");
                    seen = true;
                }
                depth += 1;
                pos = align(last + 1, 4);
            }
            2 => {
                ensure!(depth > 0, "invalid DTB nesting");
                depth -= 1;
            }
            3 => {
                ensure!(depth > 0 && pos + 8 <= end, "invalid DTB property");
                let len = word(b, pos, true)?;
                let off = word(b, pos + 4, true)?;
                pos += 8;
                ensure!(
                    len <= end - pos && off < stringsize,
                    "invalid DTB property bounds"
                );
                let (name, _) = cstring(b, strings + off, strings + stringsize)?;
                if depth == 1 && name == b"compatible" {
                    ensure!(
                        !property && len > 0 && b[pos + len - 1] == 0,
                        "duplicate/invalid compatible"
                    );
                    property = true;
                    let names = &b[pos..pos + len - 1];
                    matched = names.split(|v| *v == 0).any(|v| v == compatible.as_bytes());
                    let board_names = names
                        .split(|v| *v == 0)
                        .filter(|n| n.starts_with(b"xiaomi,") || n.starts_with(b"lenovo,"))
                        .count();
                    ensure!(board_names == 1, "conflicting board identities");
                }
                pos = align(pos + len, 4);
            }
            4 => {}
            9 => {
                ensure!(
                    seen && depth == 0 && matched,
                    "missing configured board identity"
                );
                return Ok(());
            }
            _ => bail!("invalid DTB token"),
        }
    }
    bail!("missing DTB end token")
}
fn sequence(mut b: &[u8], compatible: &str) -> Result<()> {
    ensure!(!b.is_empty(), "missing DTB");
    while !b.is_empty() {
        let len = word(b, 4, true)?;
        ensure!(len >= 40 && len <= b.len(), "truncated DTB sequence");
        dtb(&b[..len], compatible)?;
        b = &b[len..];
    }
    Ok(())
}
pub fn inspect(b: &[u8], compatible: &str, recovery: bool) -> Result<()> {
    ensure!(
        b.len() >= 1632 && b.starts_with(b"ANDROID!"),
        "not an Android image"
    );
    let (ks, rs, ss, page, version) = (
        word(b, 8, false)?,
        word(b, 16, false)?,
        word(b, 24, false)?,
        word(b, 36, false)?,
        word(b, 40, false)?,
    );
    ensure!(
        version <= 2 && [2048, 4096, 8192, 16384].contains(&page) && b.len() >= page,
        "unsupported Android header"
    );
    ensure!(ks > 0 && rs > 0 && ss == 0, "invalid payload sizes");
    let end = page + align(ks, page) + align(rs, page);
    ensure!(end <= b.len(), "truncated Android payload");
    let command = [cstring(b, 64, 576)?.0, cstring(b, 608, 1632)?.0].concat();
    let command = std::str::from_utf8(&command)?;
    let targets: Vec<_> = command
        .split_whitespace()
        .filter(|v| v.starts_with("rd.systemd.unit="))
        .collect();
    ensure!(
        targets.len() <= 1 && (targets == ["rd.systemd.unit=mobile-recovery.target"]) == recovery,
        "firmware/recovery role mismatch"
    );
    let kernel = &b[page..page + ks];
    let raw;
    let appended;
    if kernel.starts_with(&[0x1f, 0x8b]) {
        let mut decoder = flate2::bufread::GzDecoder::new(kernel);
        let mut output = Vec::new();
        decoder
            .by_ref()
            .take(256 * 1024 * 1024 + 1)
            .read_to_end(&mut output)?;
        ensure!(output.len() <= 256 * 1024 * 1024, "oversized kernel");
        appended = decoder.into_inner();
        raw = output;
    } else {
        raw = kernel.to_vec();
        appended = &[];
    }
    ensure!(
        raw.get(56..60) == Some(b"ARM\x64"),
        "kernel is not an ARM64 Image"
    );
    if version >= 1 {
        ensure!(
            word(b, 1644, false)? == if version == 1 { 1648 } else { 1660 }
                && word(b, 1632, false)? == 0,
            "unsupported Android extended header"
        );
    }
    if version == 2 {
        let len = word(b, 1648, false)?;
        ensure!(
            len > 0 && end + len <= b.len() && appended.is_empty(),
            "missing/conflicting boot DTB"
        );
        sequence(&b[end..end + len], compatible)
    } else if !appended.is_empty() {
        sequence(appended, compatible)
    } else {
        let mut found = 0;
        for pos in 64..kernel.len().saturating_sub(40) {
            if kernel[pos..].starts_with(&[0xd0, 0x0d, 0xfe, 0xed])
                && sequence(&kernel[pos..], compatible).is_ok()
            {
                found += 1;
            }
        }
        ensure!(found == 1, "missing/ambiguous appended DTB");
        Ok(())
    }
}
/// Verify the repository's full-size unsigned recovery AVB format (integrity, not authenticity).
pub fn recovery_avb(b: &[u8]) -> Result<()> {
    use sha2::{Digest, Sha256};
    ensure!(
        b.len() == 100 * 1024 * 1024,
        "recovery requires the full 100 MiB AVB image"
    );
    let be64 = |off: usize| -> Result<usize> {
        ensure!(word(b, off, true)? == 0, "oversized AVB field");
        word(b, off + 4, true)
    };
    let footer = b.len() - 64;
    ensure!(
        &b[footer..footer + 12] == b"AVBf\0\0\0\x01\0\0\0\0",
        "invalid AVB footer"
    );
    let original = be64(footer + 12)?;
    let vbmeta = be64(footer + 20)?;
    let payload = 4096 + align(word(b, 8, false)?, 4096) + align(word(b, 16, false)?, 4096);
    ensure!(
        word(b, 36, false)? == 4096
            && word(b, 40, false)? == 0
            && original == payload
            && vbmeta == original
            && be64(footer + 28)? == 448
            && vbmeta < footer - 448,
        "invalid AVB layout"
    );
    ensure!(
        &b[vbmeta..vbmeta + 4] == b"AVB0"
            && be64(vbmeta + 12)? == 0
            && be64(vbmeta + 20)? == 192
            && word(b, vbmeta + 28, true)? == 0
            && be64(vbmeta + 96)? == 0
            && be64(vbmeta + 104)? == 176,
        "unsupported AVB metadata"
    );
    let d = vbmeta + 256;
    ensure!(
        be64(d)? == 2
            && be64(d + 8)? == 160
            && be64(d + 16)? == original
            && &b[d + 24..d + 30] == b"sha256"
            && b[d + 30..d + 56].iter().all(|v| *v == 0)
            && word(b, d + 56, true)? == 8
            && word(b, d + 60, true)? == 0
            && word(b, d + 64, true)? == 32
            && word(b, d + 68, true)? == 0
            && &b[d + 132..d + 140] == b"recovery",
        "unsupported recovery hash descriptor"
    );
    ensure!(
        Sha256::digest(&b[..original])[..] == b[d + 140..d + 172],
        "AVB payload digest mismatch"
    );
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    fn fdt(board: &str, nested: bool) -> Vec<u8> {
        let mut tree = Vec::new();
        fn w(b: &mut Vec<u8>, v: u32) {
            b.extend_from_slice(&v.to_be_bytes());
        }
        w(&mut tree, 1);
        tree.extend_from_slice(&[0; 4]);
        if nested {
            w(&mut tree, 1);
            tree.extend_from_slice(b"sub\0");
        }
        let names = format!("{board}\0qcom,sm8650\0");
        w(&mut tree, 3);
        w(&mut tree, names.len() as u32);
        w(&mut tree, 0);
        tree.extend_from_slice(names.as_bytes());
        tree.resize(align(tree.len(), 4), 0);
        w(&mut tree, 2);
        if nested {
            w(&mut tree, 2);
        }
        w(&mut tree, 9);
        let mut b = vec![0; 56];
        let strings = 56 + tree.len();
        b.extend_from_slice(&tree);
        b.extend_from_slice(b"compatible\0");
        let len = b.len();
        for (off, v) in [
            (0, 0xd00dfeed),
            (4, len as u32),
            (8, 56),
            (12, strings as u32),
            (16, 40),
            (20, 17),
            (24, 16),
            (32, 11),
            (36, tree.len() as u32),
        ] {
            b[off..off + 4].copy_from_slice(&v.to_be_bytes());
        }
        b
    }
    fn image(board: &str, recovery: bool, nested: bool) -> Vec<u8> {
        let mut raw = vec![0; 1024];
        raw[56..60].copy_from_slice(b"ARM\x64");
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        encoder.write_all(&raw).unwrap();
        let mut kernel = encoder.finish().unwrap();
        kernel.extend(fdt(board, nested));
        let mut b = vec![0; 4096 + align(kernel.len(), 4096) + 4096];
        b[..8].copy_from_slice(b"ANDROID!");
        for (off, v) in [(8, kernel.len() as u32), (16, 26), (36, 4096)] {
            b[off..off + 4].copy_from_slice(&v.to_le_bytes());
        }
        if recovery {
            let cmd = b"rd.systemd.unit=mobile-recovery.target";
            b[64..64 + cmd.len()].copy_from_slice(cmd);
        }
        b[4096..4096 + kernel.len()].copy_from_slice(&kernel);
        b
    }
    #[test]
    fn full_recovery_avb_rejects_corrupt_or_wrong_descriptors() {
        use sha2::{Digest, Sha256};
        let mut b = image("xiaomi,sheng", true, false);
        let original = b.len();
        b.resize(100 * 1024 * 1024, 0);
        let v = original;
        b[v..v + 4].copy_from_slice(b"AVB0");
        for (off, n) in [
            (v + 20, 192u64),
            (v + 104, 176),
            (v + 256, 2),
            (v + 264, 160),
            (v + 272, original as u64),
        ] {
            b[off..off + 8].copy_from_slice(&n.to_be_bytes());
        }
        let d = v + 256;
        b[d + 24..d + 30].copy_from_slice(b"sha256");
        for (off, n) in [(d + 56, 8u32), (d + 64, 32)] {
            b[off..off + 4].copy_from_slice(&n.to_be_bytes());
        }
        b[d + 132..d + 140].copy_from_slice(b"recovery");
        let hash = Sha256::digest(&b[..original]);
        b[d + 140..d + 172].copy_from_slice(&hash);
        let f = b.len() - 64;
        b[f..f + 12].copy_from_slice(b"AVBf\0\0\0\x01\0\0\0\0");
        for (off, n) in [
            (f + 12, original as u64),
            (f + 20, original as u64),
            (f + 28, 448u64),
        ] {
            b[off..off + 8].copy_from_slice(&n.to_be_bytes());
        }
        inspect(&b, "xiaomi,sheng", true).unwrap();
        recovery_avb(&b).unwrap();
        for off in [4096, f, f + 20, d + 132, d + 60, d + 140] {
            b[off] ^= 1;
            assert!(recovery_avb(&b).is_err(), "offset {off}");
            b[off] ^= 1;
        }
        assert!(recovery_avb(&b[..b.len() - 4096]).is_err());
    }
    #[test]
    fn gzip_appended_dtb_and_roles() {
        for recovery in [false, true] {
            let b = image("xiaomi,aurora", recovery, false);
            inspect(&b, "xiaomi,aurora", recovery).unwrap();
            assert!(inspect(&b, "xiaomi,sheng", recovery).is_err());
            assert!(inspect(&b, "xiaomi,aurora", !recovery).is_err());
            assert!(inspect(&b[..5000], "xiaomi,aurora", recovery).is_err());
        }
    }
    #[test]
    fn arbitrary_nested_compatible_cannot_identify_image() {
        let b = image("xiaomi,aurora", false, true);
        assert!(inspect(&b, "xiaomi,aurora", false).is_err());
    }
    #[test]
    fn firmware_artifact_when_provided() {
        if let Ok(path) = std::env::var("MOBILE_TEST_SHENG_RECOVERY") {
            let mut b = std::fs::read(path).unwrap();
            inspect(&b, "xiaomi,sheng", true).unwrap();
            recovery_avb(&b).unwrap();
            b[4096] ^= 1;
            assert!(recovery_avb(&b).is_err());
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_FIRMWARE") {
            inspect(&std::fs::read(path).unwrap(), "xiaomi,aurora", false).unwrap();
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_RECOVERY") {
            inspect(&std::fs::read(path).unwrap(), "xiaomi,aurora", true).unwrap();
        }
    }
}
