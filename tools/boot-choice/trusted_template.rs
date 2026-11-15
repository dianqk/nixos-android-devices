// SPDX-License-Identifier: GPL-2.0-only
//! Live template admission: walk held descriptors, never canonicalize then reopen.
use crate::{check, template::Template, Result};
use std::{
    ffi::CString,
    fs::File,
    io::Read,
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::fs::MetadataExt,
    },
    path::{Component, Path},
};
#[repr(C)]
struct OpenHow {
    flags: u64,
    mode: u64,
    resolve: u64,
}
fn child(parent: &File, name: &str, directory: bool, same_device: bool) -> Result<File> {
    let name = CString::new(name).map_err(|e| e.to_string())?;
    let how = OpenHow {
        flags: (libc::O_RDONLY
            | libc::O_CLOEXEC
            | libc::O_NOFOLLOW
            | libc::O_NONBLOCK
            | if directory { libc::O_DIRECTORY } else { 0 }) as u64,
        mode: 0,
        resolve: 0x08 | 0x04 | if same_device { 0x01 } else { 0 },
    };
    let fd = unsafe {
        libc::syscall(
            libc::SYS_openat2,
            parent.as_raw_fd(),
            name.as_ptr(),
            &how,
            std::mem::size_of::<OpenHow>(),
        )
    };
    check(
        fd >= 0,
        &format!("template openat2: {}", std::io::Error::last_os_error()),
    )?;
    Ok(unsafe { File::from_raw_fd(fd as _) })
}
fn protected(uid: u32, mode: u32, dir: bool) -> bool {
    uid == 0 && (mode & 0o022 == 0 || (dir && mode & 0o1000 != 0))
}
fn admit(uid: u32, gid: u32, mode: u32, dir: bool, android_data: bool) -> Result<()> {
    check(
        (if android_data {
            uid == 0 && mode & 0o022 == 0
        } else {
            protected(uid, mode, dir)
        }) || (android_data
            && dir
            && ((uid == 1000 && gid == 1000) || (uid == 0 && [0, 1000].contains(&gid)))
            && mode & 0o7777 == 0o771),
        "root-protected template path required",
    )
}
struct Directory(File);
impl Directory {
    fn open(root: File, path: &Path, android: bool) -> Result<Self> {
        let parts: Vec<_> = path.components().collect();
        check(
            parts.first() == Some(&Component::RootDir) && parts.len() > 1,
            "absolute template path required",
        )?;
        let mut fd = root;
        let m = fd.metadata().map_err(|e| e.to_string())?;
        admit(m.uid(), m.gid(), m.mode(), m.is_dir(), false)?;
        for (i, part) in parts.iter().enumerate().skip(1) {
            let Component::Normal(name) = part else {
                return Err("template path traversal".into());
            };
            let name = name.to_str().ok_or("template path encoding")?;
            let data = android
                && i == 1
                && name == "data"
                && parts.get(2) == Some(&Component::Normal("adb".as_ref()));
            // Cross /data and /nix mounts while validating every held ancestor;
            // within the admitted final directory every asset stays on-device.
            fd = child(&fd, name, true, false)?;
            let m = fd.metadata().map_err(|e| e.to_string())?;
            let adb_subtree = android
                && i >= 2
                && parts.get(1) == Some(&Component::Normal("data".as_ref()))
                && parts.get(2) == Some(&Component::Normal("adb".as_ref()));
            if adb_subtree {
                check(
                    m.uid() == 0 && m.mode() & 0o022 == 0,
                    "protected Android adb subtree required",
                )?;
            }
            admit(m.uid(), m.gid(), m.mode(), m.is_dir(), data)?;
        }
        Ok(Self(fd))
    }
    fn read(&self, name: &str, cap: usize) -> Result<Vec<u8>> {
        let f = child(&self.0, name, false, true)?;
        let m = f.metadata().map_err(|e| e.to_string())?;
        admit(m.uid(), m.gid(), m.mode(), false, false)?;
        check(
            m.is_file() && m.len() > 0 && m.len() <= cap as u64,
            "template bounded protected regular file",
        )?;
        let mut bytes = Vec::new();
        f.take(cap as u64 + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        check(
            bytes.len() == m.len() as usize,
            "template file changed length",
        )?;
        Ok(bytes)
    }
}
pub(crate) fn load(path: &Path, android: bool) -> Result<Template> {
    let dir = Directory::open(File::open("/").map_err(|e| e.to_string())?, path, android)?;
    Template::load_with(|name, cap| dir.read(name, cap))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn android_data_metadata_boundary() {
        assert!(admit(1000, 1000, 0o40771, true, true).is_ok());
        assert!(admit(0, 1000, 0o40771, true, true).is_ok());
        assert!(admit(0, 0, 0o40771, true, true).is_ok());
        for (u, g, m, d, a) in [
            (1001, 1000, 0o40771, true, true),
            (1000, 1001, 0o40771, true, true),
            (1000, 1000, 0o40777, true, true),
            (1000, 1000, 0o40771, true, false),
            (1000, 1000, 0o100771, false, true),
            (0, 0, 0o40777, true, false),
        ] {
            assert!(admit(u, g, m, d, a).is_err());
        }
    }
    #[test]
    fn actual_open_refuses_symlinks() {
        let p = std::env::temp_dir().join(format!("bc-template-link-{}", std::process::id()));
        std::fs::create_dir(&p).unwrap();
        std::fs::write(p.join("file"), b"bytes").unwrap();
        std::os::unix::fs::symlink("file", p.join("alias")).unwrap();
        let fd = File::open(&p).unwrap();
        assert!(child(&fd, "file", false, true).is_ok());
        assert!(child(&fd, "alias", false, true)
            .unwrap_err()
            .contains("openat2"));
        std::fs::remove_dir_all(p).unwrap();
    }
    #[test]
    #[ignore = "root-only isolated Android ownership fixture; run explicitly with sudo"]
    fn android_template_root_fixture() {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(unsafe { libc::geteuid() }, 0);
        // Test-only bridge: the real sourced customize script invokes a mock
        // write owner whose argv is admitted by this production FD loader.
        // No runtime CLI override or block-device operation is involved.
        if let Ok(root) = std::env::var("BOOT_CHOICE_ADMISSION_TEST_ROOT") {
            let full = std::env::var("BOOT_CHOICE_ADMISSION_TEST_PATH").unwrap();
            let relative = Path::new(&full).strip_prefix(&root).unwrap();
            let absolute = Path::new("/").join(relative);
            eprintln!("production template admission: {}", absolute.display());
            let held = Directory::open(File::open(root).unwrap(), &absolute, true).unwrap();
            Template::load_with(|name, cap| held.read(name, cap)).unwrap();
            return;
        }
        let p = std::env::temp_dir().join(format!("bc-android-root-{}", std::process::id()));
        let dir = p.join("data/adb/modules_update/id/template");
        std::fs::create_dir_all(&dir).unwrap();
        let data = CString::new(p.join("data").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::chown(data.as_ptr(), 1000, 1000) }, 0);
        std::fs::set_permissions(p.join("data"), std::fs::Permissions::from_mode(0o771)).unwrap();
        std::fs::write(dir.join("asset"), b"protected asset").unwrap();
        let actual = std::env::var("BOOT_CHOICE_TEMPLATE_FIXTURE")
            .expect("actual shipped template fixture required");
        load(Path::new(&actual), false).unwrap();
        for name in [
            "template.json",
            "selector.bin",
            "firmware.bin",
            "firmware.elf",
            "firmware.config",
            "boot-choice.efi",
        ] {
            std::fs::copy(Path::new(&actual).join(name), dir.join(name)).unwrap();
        }

        let open =
            |path, android| Directory::open(File::open(&p).unwrap(), Path::new(path), android);
        assert!(open("/data/adb/modules_update/id/template", false).is_err());
        // Negative control: the former all-ancestors predicate rejects this
        // real Android UID1000/mode0771 fixture before reading any template.
        assert!(!dir.ancestors().all(|p| {
            let m = std::fs::symlink_metadata(p).unwrap();
            protected(m.uid(), m.mode(), m.is_dir())
        }));
        assert_eq!(unsafe { libc::chown(data.as_ptr(), 0, 0) }, 0);
        open("/data/adb/modules_update/id/template", true).unwrap();
        assert_eq!(unsafe { libc::chown(data.as_ptr(), 1000, 1000) }, 0);
        let held = open("/data/adb/modules_update/id/template", true).unwrap();
        Template::load_with(|name, cap| held.read(name, cap)).unwrap();
        assert_eq!(held.read("asset", 1024).unwrap(), b"protected asset");
        let asset = CString::new(dir.join("asset").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::chown(asset.as_ptr(), 1000, 1000) }, 0);
        assert!(held.read("asset", 1024).is_err());
        assert_eq!(unsafe { libc::chown(asset.as_ptr(), 0, 0) }, 0);
        std::fs::set_permissions(dir.join("asset"), std::fs::Permissions::from_mode(0o666))
            .unwrap();
        assert!(held.read("asset", 1024).is_err());
        std::fs::set_permissions(dir.join("asset"), std::fs::Permissions::from_mode(0o644))
            .unwrap();
        std::os::unix::fs::symlink("asset", dir.join("alias")).unwrap();
        assert!(held.read("alias", 1024).is_err());

        // Standard KernelSU legitimately uses an unprotected modules_update
        // mode below its private adb root. Old customization fails admission;
        // new customization stages only assets in a protected direct sibling.
        std::fs::set_permissions(p.join("data/adb"), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        let update = p.join("data/adb/modules_update");
        std::fs::set_permissions(&update, std::fs::Permissions::from_mode(0o777)).unwrap();
        assert!(open("/data/adb/modules_update/id/template", true).is_err());
        let module = p.join("data/adb/modules_update/id");
        std::fs::create_dir_all(module.join("bin")).unwrap();
        std::fs::create_dir_all(module.join("system/bin")).unwrap();
        for name in ["action.sh", "uninstall.sh", "system/bin/boot-choice"] {
            std::fs::write(module.join(name), b"fixture").unwrap();
        }
        let wrapper = b"#!/bin/sh\nBOOT_CHOICE_ADMISSION_TEST_ROOT=\"$TEST_ROOT\" BOOT_CHOICE_ADMISSION_TEST_PATH=\"$2\" \"$TEST_EXE\" --ignored --exact trusted_template::tests::android_template_root_fixture --nocapture\n";
        std::fs::write(module.join("bin/boot-choice"), wrapper).unwrap();
        std::fs::set_permissions(
            module.join("bin/boot-choice"),
            std::fs::Permissions::from_mode(0o755),
        )
        .unwrap();
        let script = r#"
ui_print(){ echo "$*"; }
abort(){ echo "$*" >&2; exit 41; }
set_perm(){ chmod "$4" "$1"; }
set_perm_recursive(){ find "$1" -type d -exec chmod "$4" '{}' +; find "$1" -type f -exec chmod "$5" '{}' +; }
mktemp(){ [ "$*" = '-d /data/adb/boot-choice-template.XXXXXX' ] || exit 98; command mktemp -d "$TEST_ROOT/data/adb/boot-choice-template.XXXXXX"; }
. "$CUSTOMIZE_FIXTURE"
"#;
        let run = |customize: &str| {
            std::process::Command::new("sh")
                .args(["-c", script])
                .env("KSU", "true")
                .env("MODPATH", &module)
                .env("TEST_ROOT", &p)
                .env("TEST_EXE", std::env::current_exe().unwrap())
                .env("CUSTOMIZE_FIXTURE", customize)
                .output()
                .unwrap()
        };
        let old = std::env::var("BOOT_CHOICE_OLD_CUSTOMIZE_FIXTURE")
            .expect("historical customize fixture required");
        let before = run(&old);
        assert_eq!(
            before.status.code(),
            Some(41),
            "{}",
            String::from_utf8_lossy(&before.stderr)
        );
        eprintln!(
            "old customize rejected as expected: {}",
            String::from_utf8_lossy(&before.stdout)
        );
        let new = std::env::var("BOOT_CHOICE_CUSTOMIZE_FIXTURE")
            .expect("current customize fixture required");
        let after = run(&new);
        assert!(
            after.status.success(),
            "{}",
            String::from_utf8_lossy(&after.stderr)
        );
        eprintln!(
            "new customize accepted: {}",
            String::from_utf8_lossy(&after.stdout)
        );
        assert_eq!(std::fs::metadata(&update).unwrap().mode() & 0o7777, 0o777);
        assert!(!std::fs::read_dir(p.join("data/adb")).unwrap().any(|e| e
            .unwrap()
            .file_name()
            .to_str()
            .unwrap()
            .starts_with("boot-choice-template.")));
        std::fs::set_permissions(&update, std::fs::Permissions::from_mode(0o755)).unwrap();

        // Rename after admission cannot redirect reads to a replacement path.
        std::fs::rename(&dir, dir.with_file_name("saved")).unwrap();
        std::fs::create_dir(&dir).unwrap();
        std::fs::write(dir.join("asset"), b"replacement").unwrap();
        assert_eq!(held.read("asset", 1024).unwrap(), b"protected asset");
        for path in [p.join("data/adb"), p.join("data/adb/modules_update/id")] {
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o777)).unwrap();
            assert!(open("/data/adb/modules_update/id/template", true).is_err());
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o1777)).unwrap();
            assert!(open("/data/adb/modules_update/id/template", true).is_err());
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
            let cp = CString::new(path.to_str().unwrap()).unwrap();
            assert_eq!(unsafe { libc::chown(cp.as_ptr(), 1000, 1000) }, 0);
            assert!(open("/data/adb/modules_update/id/template", true).is_err());
            assert_eq!(unsafe { libc::chown(cp.as_ptr(), 0, 0) }, 0);
        }
        assert_eq!(unsafe { libc::chown(data.as_ptr(), 1001, 1000) }, 0);
        assert!(open("/data/adb/modules_update/id/template", true).is_err());
        assert_eq!(unsafe { libc::chown(data.as_ptr(), 1000, 1000) }, 0);
        std::fs::create_dir(p.join("data/elsewhere")).unwrap();
        assert!(open("/data/elsewhere", true).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
        std::os::unix::fs::symlink("saved", &dir).unwrap();
        assert!(open("/data/adb/modules_update/id/template", true).is_err());
        std::fs::remove_dir_all(&p).unwrap();
    }
}
