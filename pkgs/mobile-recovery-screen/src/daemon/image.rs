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
                        .filter(|n| {
                            [&b"xiaomi,"[..], b"lenovo,", b"alldocube,", b"oneplus,"]
                                .iter()
                                .any(|v| n.starts_with(v))
                        })
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
/// Kernel and ramdisk sizes and page size of an Android boot image header.
/// v0-v2: variable page size; v3/v4: fixed 4096-byte pages and a compact
/// header (kernel, ramdisk, os_version, header_size, header_version, command
/// line; v4 adds a boot signature size, which must be zero here).
fn android_layout(b: &[u8]) -> Option<(usize, usize, usize, usize)> {
    if !b.starts_with(b"ANDROID!") {
        return None;
    }
    let version = word(b, 40, false).ok()?;
    let (ks, rs, page) = match version {
        0..=2 => (
            word(b, 8, false).ok()?,
            word(b, 16, false).ok()?,
            word(b, 36, false).ok()?,
        ),
        3 | 4 => (word(b, 8, false).ok()?, word(b, 12, false).ok()?, 4096),
        _ => return None,
    };
    (page > 0).then_some((version, ks, rs, page))
}
pub fn inspect(b: &[u8], compatible: &str, recovery: bool) -> Result<()> {
    ensure!(
        b.len() >= 1632 && b.starts_with(b"ANDROID!"),
        "not an Android image"
    );
    let (version, ks, rs, page) = android_layout(b).context("unsupported Android header")?;
    ensure!(
        [2048, 4096, 8192, 16384].contains(&page) && b.len() >= page,
        "unsupported Android header"
    );
    let command = if version <= 2 {
        ensure!(ks > 0 && rs > 0 && word(b, 24, false)? == 0, "invalid payload sizes");
        [cstring(b, 64, 576)?.0, cstring(b, 608, 1632)?.0].concat()
    } else {
        let header = if version == 3 { 1580 } else { 1584 };
        ensure!(
            word(b, 20, false)? == header
                && b[24..40].iter().all(|v| *v == 0)
                && (version == 3 || word(b, 1580, false)? == 0)
                && b[header..page].iter().all(|v| *v == 0),
            "unsupported Android v{version} header"
        );
        ensure!(word(b, 16, false)? != 0, "missing Android os_version");
        // Firmware (U-Boot) images carry no ramdisk; a recovery needs one.
        ensure!(ks > 0 && (rs > 0 || !recovery), "invalid payload sizes");
        cstring(b, 44, 1580)?.0.to_vec()
    };
    let end = page + align(ks, page) + align(rs, page);
    ensure!(end <= b.len(), "truncated Android payload");
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
    if version == 1 || version == 2 {
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
/// Decode an LZ4 legacy frame (`lz4 -l`), as MediaTek LK accepts for kernels.
fn lz4_legacy(b: &[u8], max: usize) -> Result<Vec<u8>> {
    ensure!(
        b.len() >= 8 && word(b, 0, false)? == 0x184c_2102,
        "not an LZ4 legacy frame"
    );
    let mut out = Vec::new();
    let mut pos = 4;
    while pos < b.len() {
        if b.len() - pos >= 4 && word(b, pos, false)? == 0x184c_2102 {
            break;
        }
        let size = word(b, pos, false)?;
        pos += 4;
        let block = b.get(pos..pos + size).context("truncated LZ4 block")?;
        pos += size;
        lz4_block(block, &mut out, max)?;
    }
    ensure!(!out.is_empty(), "empty LZ4 frame");
    Ok(out)
}
fn lz4_block(src: &[u8], out: &mut Vec<u8>, max: usize) -> Result<()> {
    let length = |i: &mut usize, mut n: usize| -> Result<usize> {
        if n == 15 {
            loop {
                let v = *src.get(*i).context("truncated LZ4 length")?;
                *i += 1;
                n += v as usize;
                if v != 255 {
                    break;
                }
            }
        }
        Ok(n)
    };
    let mut i = 0;
    loop {
        let token = *src.get(i).context("truncated LZ4 token")?;
        i += 1;
        let literals = length(&mut i, (token >> 4) as usize)?;
        out.extend_from_slice(src.get(i..i + literals).context("truncated LZ4 literals")?);
        i += literals;
        if i == src.len() {
            break;
        }
        let offset = u16::from_le_bytes(
            src.get(i..i + 2)
                .context("truncated LZ4 offset")?
                .try_into()?,
        ) as usize;
        i += 2;
        ensure!(offset > 0 && offset <= out.len(), "invalid LZ4 offset");
        let count = length(&mut i, (token & 15) as usize)? + 4;
        ensure!(out.len() + count <= max, "oversized LZ4 payload");
        let start = out.len() - offset;
        for k in 0..count {
            let v = out[start + k];
            out.push(v);
        }
    }
    ensure!(out.len() <= max, "oversized LZ4 payload");
    Ok(())
}
/// Header v4 firmware image of a MediaTek board: an LZ4-legacy ARM64 payload
/// (U-Boot with its control DTB appended), no ramdisk and no command line.
pub fn inspect_v4_firmware(b: &[u8], compatible: &str) -> Result<()> {
    ensure!(
        b.len() >= 4096 && b.starts_with(b"ANDROID!") && word(b, 40, false)? == 4,
        "not an Android header v4 image"
    );
    let (ks, rs) = (word(b, 8, false)?, word(b, 12, false)?);
    ensure!(ks > 0 && rs == 0, "firmware carries no ramdisk");
    ensure!(
        word(b, 20, false)? == 1584 && b[44..1580].iter().all(|v| *v == 0),
        "unexpected v4 header size or command line"
    );
    let kernel = b
        .get(4096..4096 + ks)
        .context("truncated Android payload")?;
    let raw = lz4_legacy(kernel, 64 << 20)?;
    ensure!(
        raw.get(56..60) == Some(b"ARM\x64"),
        "payload is not an ARM64 Image"
    );
    let mut found = 0;
    for pos in (64..raw.len().saturating_sub(40)).step_by(4) {
        if raw[pos..].starts_with(&[0xd0, 0x0d, 0xfe, 0xed])
            && sequence(&raw[pos..], compatible).is_ok()
        {
            found += 1;
        }
    }
    ensure!(found == 1, "missing/ambiguous control DTB");
    Ok(())
}
/// An unsigned AVB hash footer (`avbtool add_hash_footer --algorithm NONE`)
/// covering a full partition image: layout, partition name and SHA-256.
pub fn avb_hash_footer(b: &[u8], partition: usize, name: &str) -> Result<()> {
    use sha2::{Digest, Sha256};
    ensure!(
        b.len() == partition,
        "image must fill the {partition}-byte partition"
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
    let (original, vbmeta, size) = (be64(footer + 12)?, be64(footer + 20)?, be64(footer + 28)?);
    ensure!(
        original > 0 && vbmeta >= original && vbmeta + size <= footer && size >= 256,
        "invalid AVB layout"
    );
    let v = &b[vbmeta..vbmeta + size];
    ensure!(
        v.starts_with(b"AVB0") && word(v, 28, true)? == 0,
        "unsupported AVB metadata"
    );
    let auth = {
        ensure!(word(v, 12, true)? == 0, "oversized AVB field");
        word(v, 16, true)?
    };
    let (offset, length) = {
        ensure!(
            word(v, 96, true)? == 0 && word(v, 104, true)? == 0,
            "oversized AVB field"
        );
        (word(v, 100, true)?, word(v, 108, true)?)
    };
    let d = 256 + auth + offset;
    ensure!(
        d + 132 <= size && d + length <= size,
        "invalid AVB descriptors"
    );
    let names = name.len();
    ensure!(
        word(v, d, true)? == 0
            && word(v, d + 4, true)? == 2
            && word(v, d + 16, true)? == 0
            && word(v, d + 20, true)? == original
            && &v[d + 24..d + 30] == b"sha256"
            && v[d + 30..d + 56].iter().all(|x| *x == 0)
            && word(v, d + 56, true)? == names
            && word(v, d + 60, true)? == 0
            && word(v, d + 64, true)? == 32
            && d + 132 + names + 32 <= size
            && &v[d + 132..d + 132 + names] == name.as_bytes(),
        "unsupported {name} hash descriptor"
    );
    ensure!(
        Sha256::digest(&b[..original])[..] == v[d + 132 + names..d + 164 + names],
        "AVB payload digest mismatch"
    );
    Ok(())
}
/// Flattened tree walk for FIT images: every node path with its properties.
fn fdt_nodes(b: &[u8]) -> Result<Vec<(String, Vec<(String, &[u8])>)>> {
    ensure!(
        b.len() >= 40 && word(b, 0, true)? == 0xd00dfeed && word(b, 4, true)? <= b.len(),
        "invalid FIT header"
    );
    let (mut pos, strings, stringsize, size) = (
        word(b, 8, true)?,
        word(b, 12, true)?,
        word(b, 32, true)?,
        word(b, 36, true)?,
    );
    let end = pos.checked_add(size).context("FIT overflow")?;
    ensure!(
        end <= b.len() && strings + stringsize <= b.len(),
        "invalid FIT bounds"
    );
    let mut path: Vec<String> = Vec::new();
    let mut nodes: Vec<(String, Vec<(String, &[u8])>)> = Vec::new();
    while pos + 4 <= end {
        let token = word(b, pos, true)?;
        pos += 4;
        match token {
            1 => {
                let (name, last) = cstring(b, pos, end)?;
                path.push(String::from_utf8(name.to_vec())?);
                nodes.push((path.join("/"), Vec::new()));
                pos = align(last + 1, 4);
            }
            2 => {
                ensure!(path.pop().is_some(), "invalid FIT nesting");
            }
            3 => {
                let (len, off) = (word(b, pos, true)?, word(b, pos + 4, true)?);
                pos += 8;
                ensure!(len <= end - pos && off < stringsize, "invalid FIT property");
                let (name, _) = cstring(b, strings + off, strings + stringsize)?;
                let current = path.join("/");
                let node = nodes
                    .iter_mut()
                    .rev()
                    .find(|n| n.0 == current)
                    .context("FIT property outside a node")?;
                node.1
                    .push((String::from_utf8(name.to_vec())?, &b[pos..pos + len]));
                pos = align(pos + len, 4);
            }
            4 => {}
            9 => {
                ensure!(path.is_empty(), "unterminated FIT nodes");
                return Ok(nodes);
            }
            _ => bail!("invalid FIT token"),
        }
    }
    bail!("missing FIT end token")
}
/// Ramdisk of an Android v0-v4 boot image.
fn android_ramdisk(b: &[u8]) -> Option<&[u8]> {
    let (_, ks, rs, page) = android_layout(b)?;
    let start = page + align(ks, page);
    b.get(start..start.checked_add(rs)?)
}
/// A v0-v4 U-Boot boot image whose ramdisk is a device tree blob, the
/// `u-boot-fit` RAM recovery layout.
pub fn has_fit_ramdisk(b: &[u8]) -> bool {
    android_ramdisk(b).is_some_and(|r| r.starts_with(&[0xd0, 0x0d, 0xfe, 0xed]))
}
/// `u-boot-fit` recovery: the board's U-Boot image (firmware DTB, no initrd
/// target in its header) carrying a RAM recovery FIT for the system board.
pub fn inspect_fit_recovery_image(
    b: &[u8],
    firmware_compatible: &str,
    compatible: &str,
) -> Result<()> {
    inspect(b, firmware_compatible, false)?;
    let ramdisk = android_ramdisk(b).context("missing ramdisk")?;
    let size = word(ramdisk, 4, true)?;
    ensure!(
        size >= 40 && size <= ramdisk.len(),
        "truncated recovery FIT"
    );
    inspect_fit(&ramdisk[..size], compatible)
}
/// RAM recovery FIT (pkgs/mobile/recovery-fit.nix): payload marker, default
/// configuration, gzip ARM64 kernel, initrd and a board DTB whose bootargs
/// select the recovery target.
pub fn inspect_fit(b: &[u8], compatible: &str) -> Result<()> {
    let nodes = fdt_nodes(b)?;
    let prop = |node: &str, name: &str| -> Option<&[u8]> {
        nodes
            .iter()
            .find(|n| n.0 == node)
            .and_then(|n| n.1.iter().find(|p| p.0 == name).map(|p| p.1))
    };
    let text = |node: &str, name: &str| -> Result<String> {
        let v = prop(node, name).with_context(|| format!("missing {node}/{name}"))?;
        ensure!(v.last() == Some(&0), "{node}/{name} is not a string");
        Ok(String::from_utf8(v[..v.len() - 1].to_vec())?)
    };
    ensure!(
        text("", "android-devices,payload")? == "ram-recovery",
        "not a RAM recovery FIT"
    );
    let config = format!("/configurations/{}", text("/configurations", "default")?);
    let image = |kind: &str| -> Result<String> { Ok(format!("/images/{}", text(&config, kind)?)) };
    let (kernel, ramdisk, fdt) = (image("kernel")?, image("ramdisk")?, image("fdt")?);
    ensure!(
        text(&kernel, "arch")? == "arm64"
            && text(&kernel, "os")? == "linux"
            && text(&ramdisk, "type")? == "ramdisk"
            && text(&fdt, "type")? == "flat_dt",
        "unexpected FIT image types"
    );
    ensure!(
        prop(&ramdisk, "data").is_some_and(|d| !d.is_empty()),
        "missing initrd"
    );
    let raw = fit_kernel(
        prop(&kernel, "data").context("missing kernel")?,
        &text(&kernel, "compression")?,
    )?;
    ensure!(
        raw.get(56..60) == Some(b"ARM\x64"),
        "kernel is not an ARM64 Image"
    );
    let tree = prop(&fdt, "data").context("missing DTB")?;
    dtb(tree, compatible)?;
    let chosen = fdt_nodes(tree)?;
    let bootargs = chosen
        .iter()
        .find(|n| n.0 == "/chosen")
        .and_then(|n| n.1.iter().find(|p| p.0 == "bootargs"))
        .context("missing recovery bootargs")?
        .1;
    let bootargs = std::str::from_utf8(bootargs.strip_suffix(&[0]).unwrap_or(bootargs))?;
    let targets: Vec<_> = bootargs
        .split_whitespace()
        .filter(|v| v.starts_with("rd.systemd.unit="))
        .collect();
    ensure!(
        targets == ["rd.systemd.unit=mobile-recovery.target"],
        "FIT is not a recovery"
    );
    Ok(())
}
/// Decompress a FIT kernel as U-Boot does: gzip, or LZMA in the
/// `lzma_alone` format (pkgs/mobile/recovery-fit.nix), at most 256 MiB.
fn fit_kernel(data: &[u8], compression: &str) -> Result<Vec<u8>> {
    const LIMIT: usize = 256 * 1024 * 1024;
    let mut raw = Vec::new();
    match compression {
        "gzip" => {
            flate2::bufread::GzDecoder::new(data)
                .take(LIMIT as u64 + 1)
                .read_to_end(&mut raw)?;
        }
        "lzma" => {
            let options = lzma_rs::decompress::Options {
                memlimit: Some(LIMIT + 1),
                ..Default::default()
            };
            lzma_rs::lzma_decompress_with_options(&mut &data[..], &mut raw, &options)
                .map_err(|e| anyhow::anyhow!("invalid LZMA kernel: {e}"))?;
        }
        other => anyhow::bail!("unexpected FIT kernel compression {other}"),
    }
    ensure!(raw.len() <= LIMIT, "kernel is larger than 256 MiB");
    Ok(raw)
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
    /// Header v3/v4 U-Boot image shaped like marbleUBoot: gzip ARM64 payload
    /// with the control DTB appended after the gzip stream, no ramdisk, no
    /// command line, os_version set, 4096-byte header page.
    fn image_v4(board: &str, version: u32, ramdisk: &[u8]) -> Vec<u8> {
        let gz = image(board, false, false);
        let ks = word(&gz, 8, false).unwrap();
        let kernel = gz[4096..4096 + ks].to_vec();
        let mut b = vec![0; 4096 + align(ks, 4096) + align(ramdisk.len(), 4096)];
        b[..8].copy_from_slice(b"ANDROID!");
        let header = if version == 3 { 1580 } else { 1584 };
        for (off, v) in [
            (8, ks as u32),
            (12, ramdisk.len() as u32),
            (16, 0x2000_01a8),
            (20, header),
            (40, version),
        ] {
            b[off..off + 4].copy_from_slice(&v.to_le_bytes());
        }
        b[4096..4096 + ks].copy_from_slice(&kernel);
        let r = 4096 + align(ks, 4096);
        b[r..r + ramdisk.len()].copy_from_slice(ramdisk);
        b
    }
    #[test]
    fn header_v3_v4_firmware() {
        for version in [3, 4] {
            let b = image_v4("xiaomi,marble", version, &[]);
            inspect(&b, "xiaomi,marble", false).unwrap();
            assert!(inspect(&b, "xiaomi,aurora", false).is_err());
            // No ramdisk: not a recovery, and not a FIT recovery.
            assert!(inspect(&b, "xiaomi,marble", true).is_err());
            assert!(!has_fit_ramdisk(&b));
            assert!(inspect(&b[..b.len() - 4096], "xiaomi,marble", false).is_err());
            for (off, v) in [
                (8, 0u32),         // empty kernel
                (16, 0),           // missing os_version
                (20, 1632),        // wrong header size
                (24, 1),           // reserved field
                (40, 5),           // unknown version
                (40, 7 - version), // v3/v4 header size swapped
            ] {
                let mut c = b.clone();
                c[off..off + 4].copy_from_slice(&v.to_le_bytes());
                assert!(inspect(&c, "xiaomi,marble", false).is_err(), "offset {off}");
            }
            let mut c = b.clone();
            let cmd = b"rd.systemd.unit=mobile-recovery.target";
            c[44..44 + cmd.len()].copy_from_slice(cmd);
            assert!(inspect(&c, "xiaomi,marble", false).is_err());
            let mut c = b.clone();
            c[2000] = 1; // header padding
            assert!(inspect(&c, "xiaomi,marble", false).is_err());
        }
        let mut b = image_v4("xiaomi,marble", 4, &[]);
        b[1580..1584].copy_from_slice(&4096u32.to_le_bytes()); // boot signature
        assert!(inspect(&b, "xiaomi,marble", false).is_err());
        // A FIT-shaped ramdisk is found after the 4096-byte aligned kernel.
        let b = image_v4("xiaomi,marble", 4, &fdt("xiaomi,marble", false));
        assert!(has_fit_ramdisk(&b));
        inspect(&b, "xiaomi,marble", false).unwrap();
        assert!(inspect_fit_recovery_image(&b, "xiaomi,marble", "xiaomi,marble").is_err());
    }
    #[test]
    fn oneplus_firmware_requires_one_board_identity() {
        let b = image_v4("oneplus,dodge", 4, &[]);
        inspect(&b, "oneplus,dodge", false).unwrap();
        assert!(inspect(&b, "oneplus,other", false).is_err());
        for boards in ["oneplus,dodge\0oneplus,other", "oneplus,dodge\0xiaomi,aurora"] {
            let b = image_v4(boards, 4, &[]);
            assert!(inspect(&b, "oneplus,dodge", false).is_err());
        }
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
    fn placeholder_ramdisk_is_not_a_fit_recovery() {
        let b = image("xiaomi,aurora", false, false);
        assert!(!has_fit_ramdisk(&b));
        assert!(inspect_fit_recovery_image(&b, "xiaomi,aurora", "xiaomi,aurora").is_err());
    }
    #[test]
    fn arbitrary_nested_compatible_cannot_identify_image() {
        let b = image("xiaomi,aurora", false, true);
        assert!(inspect(&b, "xiaomi,aurora", false).is_err());
    }
    #[test]
    fn fit_kernel_compressions() {
        let image = b"ARM64 kernel image payload".repeat(64);
        let mut lzma = Vec::new();
        lzma_rs::lzma_compress(&mut &image[..], &mut lzma).unwrap();
        assert_eq!(fit_kernel(&lzma, "lzma").unwrap(), image);
        assert!(fit_kernel(&lzma[..lzma.len() / 2], "lzma").is_err());
        assert!(fit_kernel(&lzma, "gzip").is_err());
        assert!(fit_kernel(&image, "none").is_err());
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
        if let Ok(path) = std::env::var("MOBILE_TEST_T880_FIRMWARE") {
            let mut b = std::fs::read(path).unwrap();
            inspect_v4_firmware(&b, "alldocube,t880").unwrap();
            avb_hash_footer(&b, 64 << 20, "boot").unwrap();
            assert!(inspect_v4_firmware(&b, "xiaomi,aurora").is_err());
            assert!(avb_hash_footer(&b, 64 << 20, "recovery").is_err());
            assert!(avb_hash_footer(&b[..b.len() - 4096], 64 << 20, "boot").is_err());
            b[4096 + 100] ^= 1;
            assert!(avb_hash_footer(&b, 64 << 20, "boot").is_err());
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_T880_FIT") {
            let b = std::fs::read(path).unwrap();
            inspect_fit(&b, "alldocube,t880").unwrap();
            assert!(inspect_fit(&b, "xiaomi,aurora").is_err());
            assert!(inspect_fit(&b[..b.len() / 2], "alldocube,t880").is_err());
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_DODGE_FIRMWARE") {
            let b = std::fs::read(path).unwrap();
            inspect(&b, "oneplus,dodge", false).unwrap();
            avb_hash_footer(&b, 96 << 20, "boot").unwrap();
            assert!(inspect(&b, "oneplus,other", false).is_err());
            assert!(inspect(&b, "oneplus,dodge", true).is_err());
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_MARBLE_FIRMWARE") {
            let b = std::fs::read(path).unwrap();
            inspect(&b, "xiaomi,marble", false).unwrap();
            assert!(inspect(&b, "xiaomi,marble", true).is_err());
            assert!(inspect(&b, "xiaomi,aurora", false).is_err());
            assert!(!has_fit_ramdisk(&b));
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_MARBLE_RECOVERY") {
            let mut b = std::fs::read(path).unwrap();
            assert!(has_fit_ramdisk(&b));
            inspect_fit_recovery_image(&b, "xiaomi,marble", "xiaomi,marble").unwrap();
            assert!(inspect_fit_recovery_image(&b, "xiaomi,marble", "xiaomi,aurora").is_err());
            assert!(inspect(&b, "xiaomi,marble", true).is_err());
            let fit = 4096 + align(word(&b, 8, false).unwrap(), 4096);
            b[fit] ^= 1;
            assert!(!has_fit_ramdisk(&b));
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_CLOVER_RECOVERY") {
            let b = std::fs::read(path).unwrap();
            assert!(has_fit_ramdisk(&b));
            inspect_fit_recovery_image(&b, "xiaomi,clover", "xiaomi,clover-lte").unwrap();
            assert!(inspect_fit_recovery_image(&b, "xiaomi,clover", "xiaomi,aurora").is_err());
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_FIRMWARE") {
            inspect(&std::fs::read(path).unwrap(), "xiaomi,aurora", false).unwrap();
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_RECOVERY") {
            inspect(&std::fs::read(path).unwrap(), "xiaomi,aurora", true).unwrap();
        }
        if let Ok(path) = std::env::var("MOBILE_TEST_FIT_RECOVERY") {
            let mut b = std::fs::read(path).unwrap();
            assert!(has_fit_ramdisk(&b));
            inspect_fit_recovery_image(&b, "xiaomi,aurora", "xiaomi,aurora").unwrap();
            assert!(inspect_fit_recovery_image(&b, "xiaomi,aurora", "xiaomi,sheng").is_err());
            // Not a plain recovery: the header carries no recovery target.
            assert!(inspect(&b, "xiaomi,aurora", true).is_err());
            let fit = 4096 + align(word(&b, 8, false).unwrap(), 4096);
            let size = b[fit + 4..fit + 8].to_vec();
            b[fit + 4..fit + 8].copy_from_slice(&u32::MAX.to_be_bytes());
            assert!(inspect_fit_recovery_image(&b, "xiaomi,aurora", "xiaomi,aurora").is_err());
            b[fit + 4..fit + 8].copy_from_slice(&size);
            b[fit] ^= 1;
            assert!(!has_fit_ramdisk(&b));
            assert!(inspect_fit_recovery_image(&b, "xiaomi,aurora", "xiaomi,aurora").is_err());
        }
    }
}
