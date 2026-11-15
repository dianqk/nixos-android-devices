// SPDX-License-Identifier: GPL-2.0-only
use super::*;
fn fixture() -> Template {
    let raw = vec![1; 128];
    let elf = b"synthetic unit ELF; actual ELF/raw exercised by exporter/QEMU".to_vec();
    let config = b"test config".to_vec();
    let mut code = vec![0; 16384 + 128];
    code[96..104].copy_from_slice(b"BCRUN001");
    let pages = 48 * 1024 * 1024;
    let payload = pages + 8192 + 65536;
    let native_end = payload + 4096;
    let archive = native_end + 2 * 1024 * 1024;
    Template {
        d: Descriptor {
            schema: 1,
            profile: "dodge".into(),
            pages,
            payload,
            native_end,
            archive,
            image_end: archive + ARCHIVE + PAGE,
            stack_offset: 4096,
            raw_length: raw.len(),
            entry_parameters: 96,
            generation_data: 64,
            selector_sha256: hex(&hash(&code)),
            raw_sha256: hex(&hash(&raw)),
            elf_sha256: hex(&hash(&elf)),
            config_sha256: hex(&hash(&config)),
            helper_sha256: hex(&hash(b"helper")),
        },
        code,
        raw,
        elf,
        config,
        helper: b"helper".to_vec(),
    }
}
fn original(size: usize, stored: usize) -> Vec<u8> {
    let mut b = vec![0; size];
    b[..8].copy_from_slice(b"ANDROID!");
    b[8..12].copy_from_slice(&(stored as u32).to_le_bytes());
    b[20..24].copy_from_slice(&1584u32.to_le_bytes());
    b[40..44].copy_from_slice(&4u32.to_le_bytes());
    b[PAGE..PAGE + 2].copy_from_slice(b"MZ");
    b[PAGE + 4..PAGE + 8].copy_from_slice(&0x1400000fu32.to_le_bytes());
    put(&mut b, PAGE + 16, align(stored));
    put(&mut b, PAGE + 24, 10);
    b[PAGE + 56..PAGE + 60].copy_from_slice(b"ARM\x64");
    for (i, x) in b[PAGE + 64..PAGE + stored].iter_mut().enumerate() {
        *x = (i % 251) as u8
    }
    b
}
#[test]
fn compiler_free_roundtrip_update_and_rejection() {
    let mut t = fixture();
    for (size, stored) in [(80 * 1024 * 1024, 8192), (80 * 1024 * 1024 + PAGE, 8193)] {
        let mut o = original(size, stored);
        o[16..20].copy_from_slice(&42u32.to_le_bytes());
        o[44..60].copy_from_slice(b"synthetic-header");
        o[PAGE + 60] = 64;
        // Original AVB data remains byte-exact, independent of output NONE.
        let o = avb::seal(&o[..align(PAGE + stored)], size).unwrap();
        let b = t.embed(&o).unwrap();
        let v = Image::verify(&b).unwrap();
        assert_eq!((v.sequence, v.mode), (1, 1));
        assert_eq!(Image::restore(&b).unwrap(), o);
        assert!(t.embed(&b).is_err());
        assert_eq!(t.update(&b).unwrap(), b);
        let android = Image::request(&b, &v.generation, 1, 0).unwrap();
        assert_eq!(t.update(&android).unwrap(), android);
        // A changed producer with unchanged firmware still triggers an update,
        // retains Android and bumps seq; neither old selector nor archive nests.
        t.code[0] ^= 1;
        let updated = t.update(&android).unwrap();
        let u = Image::verify(&updated).unwrap();
        assert_eq!((u.sequence, u.mode), (3, 0));
        assert_eq!(Image::restore(&updated).unwrap(), o);
        assert_eq!(t.update(&updated).unwrap(), updated);
        t.code[0] ^= 1;
        let mut max = android[..v.body].to_vec();
        max[v.pages..v.pages + 8192].fill(0);
        max[v.pages..v.pages + PAGE].copy_from_slice(&format::record(&v.generation, u64::MAX, 0));
        let max = avb::seal(&max, size).unwrap();
        assert_eq!(t.update(&max).unwrap(), max);
        t.code[0] ^= 1;
        assert!(t.update(&max).is_err());
        t.code[0] ^= 1;
        for (at, byte) in [
            (12, 1),
            (40, 3),
            (1580, 1),
            (24, 1),
            (1584, 1),
            (PAGE + 4, 0),
            (PAGE + 56, 0),
            (PAGE + 24, 0),
        ] {
            let mut bad = o.clone();
            bad[at] = byte;
            assert!(t.embed(&bad).is_err(), "offset {at}");
        }
        let mut bad = o.clone();
        put(&mut bad, PAGE + 16, t.d.pages + 1);
        assert!(t.embed(&bad).is_err());
        let mut bad = o.clone();
        let n = bad.len();
        bad[n - 64 + 20..n - 64 + 28].fill(255);
        assert!(t.embed(&bad).is_err());
        let mut bad = b.clone();
        bad[v.body - 4096 + 192] ^= 1;
        assert!(t.update(&bad).is_err());
    }
    let mut o = original(80 * 1024 * 1024, 8192);
    let start = PAGE + 8192;
    o[start..start + ARCHIVE].fill(1);
    let size = o.len();
    let o = avb::seal(&o[..start + ARCHIVE], size).unwrap();
    assert!(t.embed(&o).unwrap_err().contains("archive capacity"));
}
#[test]
fn malformed_template_load_refuses() {
    let root = std::env::temp_dir().join(format!("boot-template-tests-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir(&root).unwrap();
    let t = fixture();
    let mut d = serde_json::json!({"schema":1,"profile":"dodge","pages":t.d.pages,"payload":t.d.payload,"native_end":t.d.native_end,"archive":t.d.archive,"image_end":t.d.image_end,"stack_offset":t.d.stack_offset,"raw_length":t.d.raw_length,"entry_parameters":t.d.entry_parameters,"generation_data":t.d.generation_data,"selector_sha256":t.d.selector_sha256,"raw_sha256":t.d.raw_sha256,"elf_sha256":t.d.elf_sha256,"config_sha256":t.d.config_sha256,"helper_sha256":t.d.helper_sha256});
    for (name, data) in [
        ("selector.bin", &t.code[..]),
        ("firmware.bin", &t.raw),
        ("firmware.elf", &t.elf),
        ("firmware.config", &t.config),
        ("boot-choice.efi", b"helper"),
    ] {
        std::fs::write(root.join(name), data).unwrap()
    }
    std::fs::write(root.join("template.json"), d.to_string()).unwrap();
    assert!(Template::load(&root).is_ok());
    for field in [
        "pages",
        "payload",
        "native_end",
        "archive",
        "image_end",
        "stack_offset",
        "raw_length",
        "entry_parameters",
        "generation_data",
    ] {
        let old = d[field].clone();
        d[field] = serde_json::json!(usize::MAX);
        std::fs::write(root.join("template.json"), d.to_string()).unwrap();
        assert!(Template::load(&root).is_err(), "{field}");
        d[field] = old;
    }
    std::fs::write(root.join("template.json"), d.to_string()).unwrap();
    std::fs::write(root.join("firmware.bin"), b"corrupt").unwrap();
    assert!(Template::load(&root).is_err());
    std::fs::remove_dir_all(root).unwrap();
}
