// SPDX-License-Identifier: GPL-2.0-only
//! Mechanical durable ESP transport, anchored to the held root directory.
//! openat2 refuses symlinks, traversal and submount/bind-mount escapes. There is
//! deliberately no weaker fallback on kernels without these resolution guards.
use crate::Result;
use std::{
    ffi::CString,
    fs::File,
    io::{Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd, IntoRawFd},
        unix::fs::MetadataExt,
    },
    path::PathBuf,
};
pub(crate) const PREF: &str = "EFI/android-devices/boot-choice.undo";
pub(crate) const FULL: &str = "EFI/android-devices/boot-choice.install.undo";
pub(crate) const RECEIPT: &str = "EFI/android-devices/boot-choice.installation";
pub(crate) const HELPER: &str = "EFI/android-devices/boot-choice.efi";
pub(crate) const MENU: &str = "loader/entries/android-same-slot.conf";
pub(crate) struct Store {
    dir: Option<File>,
    esp: Option<File>,
    #[cfg(test)]
    pub fault: Option<&'static str>,
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn os_error() -> String {
    err(std::io::Error::last_os_error())
}
#[repr(C)]
struct OpenHow {
    flags: u64,
    mode: u64,
    resolve: u64,
}
fn c(s: &str) -> Result<CString> {
    CString::new(s).map_err(err)
}
impl Store {
    pub fn new(root: PathBuf, esp: File) -> Result<Self> {
        let dir = File::open(root).map_err(err)?;
        if unsafe { libc::flock(dir.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            return Err("ESP directory busy (native/bootstrap owner)".into());
        }
        Ok(Self {
            dir: Some(dir),
            esp: Some(esp),
            #[cfg(test)]
            fault: None,
        })
    }
    pub fn directory(&self) -> Result<&File> {
        self.dir.as_ref().ok_or_else(|| "ESP root closed".into())
    }
    pub fn close_root(&mut self) -> Result<()> {
        if let Some(f) = self.dir.take() {
            self.close(f)?
        }
        Ok(())
    }
    fn point(&self, _name: &'static str) -> Result<()> {
        #[cfg(test)]
        if self.fault == Some(_name) {
            return Err(format!("injected {_name}"));
        }
        Ok(())
    }
    fn name(name: &str) -> Result<()> {
        if name.starts_with('/')
            || name
                .split('/')
                .any(|s| s.is_empty() || s == ".." || s == ".")
        {
            return Err("internal ESP relative path".into());
        }
        Ok(())
    }
    fn open_at(&self, fd: i32, name: &str, flags: i32, mode: u64) -> std::io::Result<File> {
        let name =
            CString::new(name).map_err(|_| std::io::Error::from_raw_os_error(libc::EINVAL))?;
        let how = OpenHow {
            flags: (flags | libc::O_CLOEXEC | libc::O_NOFOLLOW) as u64,
            mode,
            resolve: 0x08 | 0x04 | 0x01,
        }; // BENEATH | NO_SYMLINKS | NO_XDEV
        let fd = unsafe {
            libc::syscall(
                libc::SYS_openat2,
                fd,
                name.as_ptr(),
                &how,
                std::mem::size_of::<OpenHow>(),
            )
        };
        if fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok(unsafe { File::from_raw_fd(fd as i32) })
    }
    pub fn read(&self, name: &str, cap: usize) -> Result<Option<Vec<u8>>> {
        Self::name(name)?;
        self.point("open-read")?;
        let mut f = match self.open_at(
            self.directory()?.as_raw_fd(),
            name,
            libc::O_RDONLY | libc::O_NONBLOCK | libc::O_NOATIME,
            0,
        ) {
            Ok(f) => f,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(err(e)),
        };
        let m = f.metadata().map_err(err)?;
        if !m.is_file()
            || m.nlink() != 1
            || m.len() > cap as u64
            || m.dev() != self.directory()?.metadata().map_err(err)?.dev()
        {
            return Err("ESP file type/size/device/alias".into());
        }
        let mut b = Vec::new();
        (&mut f)
            .take(cap as u64 + 1)
            .read_to_end(&mut b)
            .map_err(err)?;
        if b.len() != m.len() as usize || f.metadata().map_err(err)?.len() != m.len() {
            return Err("ESP file length changed".into());
        }
        Ok(Some(b))
    }
    pub fn sync(&self) -> Result<()> {
        self.point("dir-sync")?;
        self.directory()?.sync_all().map_err(err)?;
        self.point("volume-sync")?;
        if unsafe { libc::syncfs(self.directory()?.as_raw_fd()) } != 0 {
            return Err(os_error());
        }
        if let Some(f) = &self.esp {
            self.point("esp-sync")?;
            f.sync_all().map_err(err)?
        }
        Ok(())
    }
    fn close(&self, f: File) -> Result<()> {
        let fd = f.into_raw_fd();
        let result = unsafe { libc::close(fd) };
        self.point("close")?;
        if result != 0 {
            return Err(os_error());
        }
        Ok(())
    }
    fn parent(&self, name: &str, create: bool) -> Result<(File, CString)> {
        Self::name(name)?;
        let mut parts: Vec<_> = name.split('/').collect();
        let leaf = c(parts.pop().ok_or("ESP leaf")?)?;
        let mut parent = self.directory()?.try_clone().map_err(err)?;
        for part in parts {
            let flags = libc::O_RDONLY | libc::O_DIRECTORY;
            let next = match self.open_at(parent.as_raw_fd(), part, flags, 0) {
                Ok(f) => f,
                Err(e) if create && e.kind() == std::io::ErrorKind::NotFound => {
                    if unsafe { libc::mkdirat(parent.as_raw_fd(), c(part)?.as_ptr(), 0o700) } != 0 {
                        return Err(os_error());
                    }
                    parent.sync_all().map_err(err)?;
                    self.open_at(parent.as_raw_fd(), part, flags, 0)
                        .map_err(err)?
                }
                Err(e) => return Err(err(e)),
            };
            parent = next
        }
        Ok((parent, leaf))
    }
    fn write_new(&self, name: &str, bytes: &[u8]) -> Result<()> {
        self.point("allocation")?;
        let (parent, leaf) = self.parent(name, true)?;
        self.point("create")?;
        let mut f = self
            .open_at(
                parent.as_raw_fd(),
                leaf.to_str().map_err(err)?,
                libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
                0o600,
            )
            .map_err(err)?;
        self.point("write")?;
        let n = f.write(bytes).map_err(err)?;
        if n != bytes.len() {
            return Err("short ESP write".into());
        }
        self.point("file-sync")?;
        f.sync_all().map_err(err)?;
        let advice = unsafe { libc::posix_fadvise(f.as_raw_fd(), 0, 0, libc::POSIX_FADV_DONTNEED) };
        if advice != 0 {
            return Err(format!("ESP readback cache eviction: {advice}"));
        }
        self.close(f)?;
        parent.sync_all().map_err(err)?;
        Ok(())
    }
    pub fn create(&self, name: &str, bytes: &[u8]) -> Result<()> {
        Self::name(name)?;
        self.write_new(name, bytes)?;
        self.sync()?;
        self.point("reopen")?;
        if self.read(name, bytes.len())?.as_deref() != Some(bytes) {
            return Err("ESP journal readback".into());
        }
        Ok(())
    }
    pub fn remove(&self, name: &str) -> Result<()> {
        self.point("remove")?;
        let (parent, leaf) = self.parent(name, false)?;
        if unsafe { libc::unlinkat(parent.as_raw_fd(), leaf.as_ptr(), 0) } != 0 {
            return Err(os_error());
        }
        parent.sync_all().map_err(err)?;
        self.sync()
    }
    /// The journal proves scratch absence before this operation started. Recovery
    /// may retire that transaction-specific scratch, never arbitrary ESP files.
    pub fn replace(&self, name: &str, bytes: Option<&[u8]>, nonce: &str) -> Result<()> {
        let temp = format!("{name}.{nonce}.new");
        if let Some(b) = bytes {
            self.write_new(&temp, b)?;
            let (parent, leaf) = self.parent(name, false)?;
            let (_, scratch) = self.parent(&temp, false)?;
            if unsafe {
                libc::renameat(
                    parent.as_raw_fd(),
                    scratch.as_ptr(),
                    parent.as_raw_fd(),
                    leaf.as_ptr(),
                )
            } != 0
            {
                return Err(os_error());
            }
            parent.sync_all().map_err(err)?;
            self.sync()?;
            if self.read(name, b.len())?.as_deref() != Some(b) {
                return Err("installed ESP file readback".into());
            }
        } else if self.read(name, 32 * 1024 * 1024)?.is_some() {
            self.remove(name)?
        }
        Ok(())
    }
    pub fn retire_scratch(&self, name: &str, nonce: &str) -> Result<()> {
        let name = format!("{name}.{nonce}.new");
        if self.read(&name, 32 * 1024 * 1024)?.is_some() {
            self.remove(&name)?
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    #[test]
    fn real_files_and_each_durability_failure() {
        let root = std::env::temp_dir().join(format!("boot-choice-fs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let mut s = Store {
            dir: Some(File::open(&root).unwrap()),
            esp: None,
            fault: None,
        };
        assert!(s.read(PREF, 100).unwrap().is_none());
        s.create(PREF, b"exact journal").unwrap();
        assert_eq!(s.read(PREF, 100).unwrap().unwrap(), b"exact journal");
        assert!(s.create(PREF, b"overwrite").is_err());
        s.remove(PREF).unwrap();
        for fault in [
            "allocation",
            "create",
            "write",
            "file-sync",
            "close",
            "dir-sync",
            "volume-sync",
            "reopen",
        ] {
            s.fault = Some(fault);
            assert!(s.create(PREF, b"durable").is_err(), "{fault}");
            s.fault = None;
            if s.read(PREF, 100).unwrap().is_some() {
                s.remove(PREF).unwrap()
            }
        }
        s.replace(HELPER, Some(b"helper"), "unit").unwrap();
        assert_eq!(s.read(HELPER, 100).unwrap().unwrap(), b"helper");
        let foreign = root.join("foreign");
        fs::write(&foreign, b"preserve").unwrap();
        fs::remove_file(root.join(HELPER)).unwrap();
        std::os::unix::fs::symlink(&foreign, root.join(HELPER)).unwrap();
        assert!(s.read(HELPER, 100).is_err());
        fs::remove_file(root.join(HELPER)).unwrap();
        assert_eq!(fs::read(foreign).unwrap(), b"preserve");
        s.close_root().unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
