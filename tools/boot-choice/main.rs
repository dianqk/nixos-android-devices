// SPDX-License-Identifier: GPL-2.0-only
use boot_choice_native::{transact, Owned, Result};
use std::{
    env,
    fs::{File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::Path,
};
// Open first, then fstat: no pathname check/open race grants device access.
fn regular(path: &Path) -> Result<File> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC)
        .open(path)
        .map_err(|e| e.to_string())?;
    let m = f.metadata().map_err(|e| e.to_string())?;
    if !m.is_file() || m.len() > 256 * 1024 * 1024 {
        return Err("bounded regular files only".into());
    }
    Ok(f)
}
fn read(path: &str) -> Result<Vec<u8>> {
    let mut b = Vec::new();
    regular(Path::new(path))?
        .take(256 * 1024 * 1024 + 1)
        .read_to_end(&mut b)
        .map_err(|e| e.to_string())?;
    if b.len() > 256 * 1024 * 1024 {
        return Err("file grew".into());
    }
    Ok(b)
}
fn create(path: &str) -> Result<File> {
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| e.to_string())?;
    File::open(
        Path::new(path)
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new(".")),
    )
    .and_then(|p| p.sync_all())
    .map_err(|e| e.to_string())?;
    Ok(f)
}
fn run() -> Result<()> {
    let a: Vec<_> = env::args().collect();
    if a.len() == 2 && matches!(a[1].as_str(), "--help" | "help" | "-h") {
        println!(
            "boot-choice: native current-booted-target operation owner\n\
status (root, strict current context/GPT/controller/ESP inspection; NOT write authority)\n\
owned-inspect IMAGE\n\
owned-restore IMAGE NEW_OUTPUT\n\
owned-request IMAGE GENERATION SEQUENCE android|uboot NEW_OUTPUT\n\
owned-seal CATALOG ORIGINAL RAW ELF CONFIG IMAGE NEW_OUTPUT\n\
image embed|update TEMPLATE INPUT NEW_OUTPUT\n\
image restore OWNED NEW_OUTPUT\n\
reboot android|nixos (root; verified commit then standard OS reset)\n\
install TEMPLATE | update TEMPLATE | restore | recover (root; actual current target only)\n\
Live operations require guarded current slot/context, UFS/GPT/ESP identity and durable undo."
        );
        return Ok(());
    }
    if a.len() == 3 && a[1] == "reboot" {
        let mode = match a[2].as_str() {
            "android" => 0,
            "nixos" => 1,
            _ => return Err("reboot android|nixos".into()),
        };
        boot_choice_native::live_status::owner::preference(mode, true)?;
        println!("preference VERIFIED; standard OS reboot requested");
        return Ok(());
    }
    if a.len() == 3 && matches!(a[1].as_str(), "install" | "update") {
        return boot_choice_native::live_status::owner::image_operation(
            &a[1],
            Some(Path::new(&a[2])),
        );
    }
    if a.len() == 2 && a[1] == "restore" {
        return boot_choice_native::live_status::owner::image_operation("restore", None);
    }
    if a.len() == 2 && a[1] == "recover" {
        return boot_choice_native::live_status::owner::recover();
    }
    if a.len() == 2 && a[1] == "status" {
        println!(
            "{}",
            serde_json::to_string_pretty(&boot_choice_native::live_status::inspect()?)
                .map_err(|e| e.to_string())?
        );
        return Ok(());
    }
    if a.get(1).map(String::as_str) == Some("image") {
        use boot_choice_native::{owned::Image, template::Template};
        let out =
            match a.get(2).map(String::as_str) {
                Some("embed" | "update") if a.len() == 6 => {
                    let template = Template::load(Path::new(&a[3]))?;
                    let bytes = read(&a[4])?;
                    if a[2] == "embed" {
                        template.embed(&bytes)?
                    } else {
                        template.update(&bytes)?
                    }
                }
                Some("restore") if a.len() == 5 => {
                    Image::restore(&read(&a[3])?).map_err(str::to_owned)?
                }
                _ => return Err(
                    "image embed|update TEMPLATE INPUT NEW_OUTPUT | image restore OWNED NEW_OUTPUT"
                        .into(),
                ),
            };
        let mut written = create(a.last().unwrap())?;
        written.write_all(&out).map_err(|e| e.to_string())?;
        written.sync_all().map_err(|e| e.to_string())?;
        drop(written);
        // A separate reopen/readback verifies the exclusive regular-file output.
        let output = a.last().unwrap();
        let f = regular(Path::new(output))?;
        f.sync_all().map_err(|e| e.to_string())?;
        if read(output)? != out {
            return Err("output readback mismatch".into());
        }
        return Ok(());
    }
    if a.get(1).is_some_and(|v| v.starts_with("owned-")) {
        use boot_choice_native::{hash, hex, owned::Image, seal_legacy};
        let err = || {
            "owned-inspect IMAGE | owned-restore IMAGE NEW_OUTPUT | owned-request IMAGE GENERATION SEQUENCE android|uboot NEW_OUTPUT | owned-seal CATALOG ORIGINAL RAW ELF CONFIG IMAGE NEW_OUTPUT".to_owned()
        };
        let output = match a[1].as_str() {
            "owned-inspect" if a.len() == 3 => {
                let b = read(&a[2])?;
                let v = Image::verify(&b).map_err(str::to_owned)?;
                println!("HOST VERIFIED v1 layout_flag={} (1=offline legacy, 2=prelinked; not device authority) generation={} sequence={} mode={} body={} legacy_body={} archive={} sha256={}", v.layout_flag, hex(&v.generation),v.sequence,v.mode,v.body,v.legacy_body,v.archive_bytes,hex(&hash(&b)));
                return Ok(());
            }
            "owned-restore" if a.len() == 4 => (
                a[3].as_str(),
                Image::restore(&read(&a[2])?).map_err(str::to_owned)?,
            ),
            "owned-request" if a.len() == 7 => {
                let b = read(&a[2])?;
                let v = Image::verify(&b).map_err(str::to_owned)?;
                if a[3] != hex(&v.generation) {
                    return Err("expected generation".into());
                }
                let seq = a[4].parse().map_err(|_| "sequence")?;
                let mode = match a[5].as_str() {
                    "android" => 0,
                    "uboot" => 1,
                    _ => return Err("mode".into()),
                };
                (
                    a[6].as_str(),
                    Image::request(&b, &v.generation, seq, mode).map_err(str::to_owned)?,
                )
            }
            "owned-seal" if a.len() == 9 => {
                let c = serde_json::from_slice(&read(&a[2])?).map_err(|e| e.to_string())?;
                (
                    a[8].as_str(),
                    seal_legacy(
                        &c,
                        &read(&a[3])?,
                        &read(&a[4])?,
                        &read(&a[5])?,
                        &read(&a[6])?,
                        &read(&a[7])?,
                    )?,
                )
            }
            _ => return Err(err()),
        };
        let mut f = create(output.0)?;
        f.write_all(&output.1)
            .and_then(|_| f.sync_all())
            .map_err(|e| e.to_string())?;
        println!("verified offline output; input untouched; NOT FLASHABLE");
        return Ok(());
    }
    if a.len() != 8 && a.len() != 12 {
        return Err("verify CATALOG ORIGINAL RAW ELF CONFIG IMAGE | request CATALOG ORIGINAL RAW ELF CONFIG IMAGE android|uboot NEW_OUTPUT NEW_JOURNAL --execute-offline".into());
    }
    let c = serde_json::from_slice(&read(&a[2])?).map_err(|e| e.to_string())?;
    let o = Owned::from_sources(
        &c,
        &read(&a[3])?,
        &read(&a[4])?,
        &read(&a[5])?,
        &read(&a[6])?,
    )?;
    let b = read(&a[7])?;
    o.verify(&b)?;
    match a[1].as_str() {
        "verify" if a.len() == 8 => println!("owned BOOT4 and canonical AVB NONE verified"),
        "request" if a.len() == 12 && a[11] == "--execute-offline" => {
            let mode = match a[8].as_str() {
                "android" => 0,
                "uboot" => 1,
                _ => return Err("mode".into()),
            };
            o.prepare(&b, mode)?;
            let mut out = create(&a[9])?;
            out.write_all(&b)
                .and_then(|_| out.sync_all())
                .map_err(|e| e.to_string())?;
            let mut journal = create(&a[10])?;
            transact(&mut out, &mut journal, &o, mode)?;
            println!("verified new offline image; original input untouched; retain journal");
        }
        _ => return Err("command/explicit offline execution required".into()),
    }
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("boot-choice-native: {e}");
        std::process::exit(1)
    }
}
