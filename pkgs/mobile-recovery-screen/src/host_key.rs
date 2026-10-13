//! Optional recovery identity, separate from Android and the installed sshd.
//! The initrd unit supplies a private mount namespace and a bounded start time.
use anyhow::{ensure, Context, Result};
use serde::Deserialize;
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{FileExt, FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::Command,
};

const KEY: &str = "ssh_host_ed25519_key";
const STATE: &str = "ssh-host-key-state";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    identity: String,
    compatible: String,
    controller: String,
    root_device: PathBuf,
    root_label: String,
}

fn tool(name: &str, args: &[&str]) -> Result<String> {
    let out = Command::new(name)
        .args(args)
        .output()
        .with_context(|| format!("start {name}"))?;
    ensure!(out.status.success(), "{name} failed ({})", out.status);
    Ok(String::from_utf8(out.stdout)?.trim().to_owned())
}
fn text(p: &Path) -> Result<&str> {
    p.to_str().context("non-UTF8 path")
}

// Never follow links inside the target filesystem, including any parent directory.
fn directory(parent: &Path, name: &str, create: bool, mode: u32) -> Result<PathBuf> {
    let p = parent.join(name);
    if create && !p.try_exists()? {
        fs::create_dir(&p)?;
        fs::set_permissions(&p, fs::Permissions::from_mode(mode))?;
    }
    let m = fs::symlink_metadata(&p)?;
    ensure!(
        m.is_dir() && m.uid() == unsafe { libc::geteuid() } && m.mode() & 0o022 == 0,
        "unsafe host-key directory {}",
        p.display()
    );
    Ok(p)
}
fn key_directory(root: &Path, create: bool) -> Result<PathBuf> {
    let mut p = root.to_owned();
    for name in ["var", "lib", "mobile-recovery", "ssh"] {
        let mode = if name == "var" || name == "lib" {
            0o755
        } else {
            0o700
        };
        p = directory(&p, name, create, mode)?;
    }
    Ok(p)
}
fn private_key(path: &Path) -> Result<Vec<u8>> {
    let mut f = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)?;
    let m = f.metadata()?;
    ensure!(
        m.is_file()
            && m.uid() == unsafe { libc::geteuid() }
            && m.mode() & 0o077 == 0
            && m.nlink() == 1
            && m.len() > 0
            && m.len() <= 16384,
        "unsafe host key"
    );
    let mut b = Vec::new();
    f.read_to_end(&mut b)?;
    Ok(b)
}
fn write_new(path: &Path, data: &[u8]) -> Result<()> {
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    f.write_all(data)?;
    f.sync_all()?;
    Ok(())
}
fn public_key(path: &Path) -> Result<String> {
    let public = tool("ssh-keygen", &["-y", "-P", "", "-f", text(path)?])?;
    ensure!(
        public.starts_with("ssh-ed25519 ") && !public.contains('\n'),
        "expected Ed25519 host key"
    );
    Ok(public + "\n")
}
fn clean_ext4(superblock: &[u8]) -> Result<()> {
    ensure!(superblock.len() == 1024, "short ext4 superblock");
    let u16at = |n| u16::from_le_bytes(superblock[n..n + 2].try_into().unwrap());
    let incompat = u32::from_le_bytes(superblock[96..100].try_into().unwrap());
    ensure!(
        u16at(56) == 0xef53 && u16at(58) == 1 && incompat & 4 == 0,
        "ext4 is not clean; no repair or journal replay attempted"
    );
    Ok(())
}
fn storage(c: &Config) -> Result<PathBuf> {
    ensure!(
        !c.controller.is_empty() && !c.controller.contains('/'),
        "invalid controller"
    );
    let node = fs::canonicalize(&c.root_device)?;
    let m = fs::metadata(&node)?;
    ensure!(
        m.file_type().is_block_device(),
        "root is not a block device"
    );
    let dev = format!("{}:{}", libc::major(m.rdev()), libc::minor(m.rdev()));
    let sys = fs::canonicalize(Path::new("/sys/dev/block").join(&dev))?;
    ensure!(
        sys.join("partition").is_file()
            && sys
                .components()
                .any(|x| x.as_os_str() == c.controller.as_str())
            && !sys
                .components()
                .any(|x| x.as_os_str().to_string_lossy().starts_with("usb")),
        "root is not on the configured internal controller"
    );
    let parent = sys.parent().context("missing disk")?;
    ensure!(
        fs::read_to_string(parent.join("removable"))?.trim() == "0",
        "removable storage"
    );
    // Refuse active filesystems, swap and dm holders on this disk. Also reject
    // automount races by keeping all recovery storage services ordered after us.
    let mounts = fs::read_to_string("/proc/self/mountinfo")?;
    ensure!(
        fs::read_to_string("/proc/swaps")?.lines().count() <= 1,
        "swap is active"
    );
    for p in std::iter::once(parent.to_owned())
        .chain(fs::read_dir(parent)?.filter_map(|x| x.ok().map(|e| e.path())))
    {
        if !p.join("dev").is_file() {
            continue;
        }
        let id = fs::read_to_string(p.join("dev"))?;
        ensure!(
            !mounts
                .lines()
                .any(|l| l.split_whitespace().nth(2) == Some(id.trim())),
            "disk is mounted"
        );
        ensure!(
            fs::read_dir(p.join("holders"))?.next().is_none(),
            "disk has active holders"
        );
    }
    ensure!(
        tool("blkid", &["-p", "-s", "TYPE", "-o", "value", text(&node)?])? == "ext4"
            && tool("blkid", &["-p", "-s", "LABEL", "-o", "value", text(&node)?])? == c.root_label,
        "Linux filesystem type/label mismatch"
    );
    let mut sb = [0; 1024];
    File::open(&node)?.read_exact_at(&mut sb, 1024)?;
    clean_ext4(&sb)?;
    Ok(node)
}
struct Mount(PathBuf);
impl Mount {
    fn open(node: &Path, path: &Path, rw: bool) -> Result<Self> {
        tool(
            "mount",
            &[
                "-t",
                "ext4",
                "-o",
                if rw {
                    "rw,nosuid,nodev,noexec"
                } else {
                    "ro,noload,nosuid,nodev,noexec"
                },
                text(node)?,
                text(path)?,
            ],
        )?;
        Ok(Self(path.to_owned()))
    }
    fn close(self) -> Result<()> {
        tool("umount", &[text(&self.0)?])?;
        std::mem::forget(self);
        Ok(())
    }
}
impl Drop for Mount {
    fn drop(&mut self) {
        let _ = tool("umount", &[self.0.to_str().unwrap()]);
    }
}
fn load(root: &Path) -> Result<Option<Vec<u8>>> {
    // Missing parents are normal before first installation. Existing unsafe
    // paths and broken links must fail rather than be silently replaced.
    let mut p = root.to_owned();
    for name in ["var", "lib", "mobile-recovery", "ssh"] {
        match fs::symlink_metadata(p.join(name)) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e.into()),
            Ok(_) => p = directory(&p, name, false, 0o700)?,
        }
    }
    match fs::symlink_metadata(p.join(KEY)) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
        Ok(_) => Ok(Some(private_key(&p.join(KEY))?)),
    }
}
fn persist(root: &Path, key: &[u8], public: &str) -> Result<()> {
    let dir = key_directory(root, true)?;
    let temp = dir.join(format!(".{KEY}.{}", std::process::id()));
    write_new(&temp, key)?;
    // Publish atomically without replacing an identity or leaving a second hard
    // link across a power loss. Ext4 supports RENAME_NOREPLACE.
    let from = std::ffi::CString::new(text(&temp)?)?;
    let destination = dir.join(KEY);
    let to = std::ffi::CString::new(text(&destination)?)?;
    let renamed = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    if renamed != 0 {
        let error = std::io::Error::last_os_error();
        let _ = fs::remove_file(&temp);
        return Err(error.into());
    }
    File::open(&dir)?.sync_all()?;
    // The private key is authoritative. A failed public-file write never replaces it.
    if !dir.join(format!("{KEY}.pub")).try_exists()? {
        write_new(&dir.join(format!("{KEY}.pub")), public.as_bytes())?;
    }
    File::open(&dir)?.sync_all()?;
    Ok(())
}
pub fn prepare() -> Result<()> {
    ensure!(unsafe { libc::geteuid() } == 0, "root required");
    let c: Config = serde_json::from_slice(&fs::read("/etc/recovery-host-key.json")?)?;
    ensure!(
        Path::new("/etc/initrd-release").is_file()
            && fs::read_to_string("/etc/mobile-ram-recovery")?.trim() == c.identity
            && fs::read("/proc/device-tree/compatible")?
                .split(|x| *x == 0)
                .any(|x| x == c.compatible.as_bytes()),
        "configured RAM recovery identity mismatch"
    );
    let run = directory(Path::new("/run"), "mobile-recovery", true, 0o700)?;
    // Do not rotate an identity already served during this recovery boot.
    if run.join(KEY).try_exists()? {
        return Ok(());
    }
    fs::write(run.join(STATE), "temporary\n")?;
    // udev-trigger completing does not imply the internal disk has appeared yet.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    while !c.root_device.try_exists()? && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    let node = storage(&c)?;
    let mountpoint = directory(&run, "host-key-root", true, 0o700)?;
    let mount = Mount::open(&node, &mountpoint, false)?;
    let existing = load(&mountpoint)?;
    mount.close()?;
    let candidate = run.join(format!(".host-key-candidate-{}", std::process::id()));
    let result = (|| -> Result<()> {
        match &existing {
            Some(bytes) => write_new(&candidate, bytes)?,
            None => {
                tool(
                    "ssh-keygen",
                    &["-q", "-t", "ed25519", "-N", "", "-f", text(&candidate)?],
                )?;
            }
        }
        let public = public_key(&candidate)?;
        if existing.is_none() {
            let node = storage(&c)?; // Recheck after the read-only mount is released.
            let mount = Mount::open(&node, &mountpoint, true)?;
            ensure!(
                load(&mountpoint)?.is_none(),
                "host key appeared before creation"
            );
            persist(&mountpoint, &private_key(&candidate)?, &public)?;
            mount.close()?;
        }
        // Publish only after the filesystem has been unmounted successfully.
        fs::rename(&candidate, run.join(KEY))?;
        fs::write(run.join(format!("{KEY}.pub")), public)?;
        fs::write(run.join(STATE), "persistent\n")?;
        eprintln!("Recovery SSH identity: persistent (Linux /var/lib/mobile-recovery/ssh)");
        Ok(())
    })();
    let _ = fs::remove_file(&candidate);
    let _ = fs::remove_file(candidate.with_extension("pub"));
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    #[test]
    fn persistent_identity_and_unsafe_paths() -> Result<()> {
        let root = std::env::temp_dir().join(format!("host-key-test-{}", std::process::id()));
        fs::create_dir(&root)?;
        let result = (|| -> Result<()> {
            assert!(load(&root)?.is_none());
            persist(&root, b"first", "public")?;
            assert_eq!(load(&root)?.unwrap(), b"first");
            assert_eq!(fs::metadata(root.join("var/lib"))?.mode() & 0o777, 0o755);
            assert_eq!(
                fs::metadata(key_directory(&root, false)?)?.mode() & 0o777,
                0o700
            );
            assert!(persist(&root, b"replacement", "other").is_err());
            assert_eq!(load(&root)?.unwrap(), b"first");
            let dir = key_directory(&root, false)?;
            let path = dir.join(KEY);
            fs::set_permissions(&path, fs::Permissions::from_mode(0o644))?;
            assert!(load(&root).is_err());
            fs::remove_file(&path)?;
            symlink("/nonexistent", &path)?;
            assert!(load(&root).is_err());
            fs::remove_file(&path)?;
            write_new(&path, b"first")?;
            fs::hard_link(&path, dir.join("copy"))?;
            assert!(load(&root).is_err());
            fs::remove_file(dir.join("copy"))?;
            fs::rename(root.join("var"), root.join("old-var"))?;
            symlink(root.join("old-var"), root.join("var"))?;
            assert!(load(&root).is_err());
            Ok(())
        })();
        fs::remove_dir_all(root)?;
        result
    }
    // Run explicitly in a private mount namespace with a disposable ext4 loop
    // device supplied by the integration harness; never enumerate host disks.
    #[test]
    #[ignore = "requires disposable ext4 loop device and mount namespace"]
    fn ext4_persistence_roundtrip() -> Result<()> {
        let device = PathBuf::from(std::env::var("RECOVERY_TEST_LOOP")?);
        ensure!(
            device.to_string_lossy().starts_with("/dev/loop"),
            "test loop required"
        );
        let root = PathBuf::from(std::env::var("RECOVERY_TEST_ROOT")?);
        let mounted = root.join("mount");
        fs::create_dir(&mounted)?;
        let key = root.join("candidate");
        tool(
            "ssh-keygen",
            &["-q", "-t", "ed25519", "-N", "", "-f", text(&key)?],
        )?;
        let bytes = private_key(&key)?;
        let public = public_key(&key)?;
        let m = Mount::open(&device, &mounted, false)?;
        assert!(load(&mounted)?.is_none());
        assert!(persist(&mounted, &bytes, &public).is_err());
        m.close()?;
        let m = Mount::open(&device, &mounted, true)?;
        fs::write(mounted.join("unrelated"), b"preserve me")?;
        persist(&mounted, &bytes, &public)?;
        m.close()?;
        // A later recovery boot reads the same secret and derives the same public key.
        let m = Mount::open(&device, &mounted, false)?;
        assert_eq!(load(&mounted)?.unwrap(), bytes);
        assert_eq!(fs::read(mounted.join("unrelated"))?, b"preserve me");
        write_new(&root.join("loaded"), &load(&mounted)?.unwrap())?;
        assert_eq!(public_key(&root.join("loaded"))?, public);
        m.close()?;
        let m = Mount::open(&device, &mounted, true)?;
        assert!(persist(&mounted, b"replacement", &public).is_err());
        assert_eq!(load(&mounted)?.unwrap(), bytes);
        let p = key_directory(&mounted, false)?.join(KEY);
        fs::write(&p, b"corrupt")?;
        m.close()?;
        let m = Mount::open(&device, &mounted, false)?;
        write_new(&root.join("invalid"), &load(&mounted)?.unwrap())?;
        assert!(public_key(&root.join("invalid")).is_err());
        drop(m); // Error cleanup also releases the mount.
        assert!(!fs::read_to_string("/proc/self/mountinfo")?.contains(text(&mounted)?));
        let mut sb = [0; 1024];
        File::open(device)?.read_exact_at(&mut sb, 1024)?;
        clean_ext4(&sb)?;
        Ok(())
    }

    #[test]
    fn journal_and_error_states_refuse_storage() {
        let mut sb = [0; 1024];
        sb[56..58].copy_from_slice(&0xef53u16.to_le_bytes());
        sb[58] = 1;
        assert!(clean_ext4(&sb).is_ok());
        sb[96] = 4;
        assert!(clean_ext4(&sb).is_err());
        sb[96] = 0;
        sb[58] = 3;
        assert!(clean_ext4(&sb).is_err());
        sb[58] = 0;
        assert!(clean_ext4(&sb).is_err());
    }
}
