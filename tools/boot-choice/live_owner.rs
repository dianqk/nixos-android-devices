// SPDX-License-Identifier: GPL-2.0-only
//! Native current-target owner. No caller-selected block paths or slot changes.
use super::*;
use crate::{
    live_fs::{Store, FULL, PREF},
    transaction,
};
use std::os::unix::process::CommandExt;
use std::{
    ffi::CString,
    io,
    os::{fd::AsRawFd, unix::fs::DirBuilderExt},
    process::Command,
};
fn os_error() -> String {
    io::Error::last_os_error().to_string()
}
fn lock(f: &File) -> Result<()> {
    check(
        unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0,
        "another boot-choice operation holds the device lock",
    )
}
fn trusted(p: &Path) -> Result<()> {
    for p in p.ancestors() {
        let m = fs::symlink_metadata(p).map_err(|e| e.to_string())?;
        check(
            !m.file_type().is_symlink()
                && m.uid() == 0
                && (m.mode() & 0o022 == 0 || (m.is_dir() && m.mode() & 0o1000 != 0)),
            "root-protected path required",
        )?
    }
    Ok(())
}
fn mounted(rdev: u64) -> Result<bool> {
    let id = format!("{}:{}", libc::major(rdev), libc::minor(rdev));
    Ok(text(Path::new("/proc/self/mountinfo"))?
        .lines()
        .any(|l| l.split_whitespace().nth(2) == Some(id.as_str())))
}
struct Partition {
    file: File,
    sys: PathBuf,
    rdev: u64,
    size: u64,
    first: u64,
}
fn partition(
    group: &Group,
    index: usize,
    first: u64,
    size: u64,
    writable: bool,
) -> Result<Partition> {
    let m = &group.members[index];
    let mut found = None;
    for e in fs::read_dir(&m.sys).map_err(|e| e.to_string())? {
        let e = e.map_err(|e| e.to_string())?;
        let p = e.path();
        if !p.join("partition").exists() {
            continue;
        }
        let start: u64 = text(&p.join("start"))?
            .trim()
            .parse()
            .map_err(|_| "partition start")?;
        let sectors: u64 = text(&p.join("size"))?
            .trim()
            .parse()
            .map_err(|_| "partition sectors")?;
        if start.checked_mul(512) == first.checked_mul(m.block as u64)
            && sectors.checked_mul(512) == Some(size)
        {
            check(found.is_none(), "ambiguous kernel partition")?;
            let rdev = dev(&p)?;
            let file = if writable {
                check(
                    !mounted(rdev)?
                        && fs::read_dir(p.join("holders"))
                            .map_err(|e| e.to_string())?
                            .next()
                            .is_none(),
                    "boot partition in use",
                )?;
                let name = e.file_name().into_string().map_err(|_| "partition name")?;
                check(
                    name.bytes().all(|c| c.is_ascii_alphanumeric()),
                    "kernel partition name",
                )?;
                let base = block_node_root(Path::new("/sys/firmware/efi").is_dir());
                OpenOptions::new()
                    .read(true)
                    .write(true)
                    .custom_flags(
                        libc::O_EXCL
                            | libc::O_NOFOLLOW
                            | libc::O_CLOEXEC
                            | libc::O_NONBLOCK
                            | crate::media::FLAGS,
                    )
                    .open(Path::new(base).join(name))
                    .map_err(|e| e.to_string())?
            } else {
                open_block(
                    &e.file_name().into_string().map_err(|_| "partition name")?,
                    rdev,
                )?
            };
            check(
                file.metadata().map_err(|e| e.to_string())?.rdev() == rdev
                    && geometry(&file)?.1 == size,
                "held partition identity/geometry",
            )?;
            lock(&file)?;
            found = Some(Partition {
                file,
                sys: p,
                rdev,
                size,
                first: first * m.block as u64,
            });
        }
    }
    found.ok_or_else(|| "missing exact kernel partition".into())
}
impl Partition {
    fn recheck(&self, writable: bool) -> Result<()> {
        check(
            dev(&self.sys)? == self.rdev
                && self.file.metadata().map_err(|e| e.to_string())?.rdev() == self.rdev
                && geometry(&self.file)?.1 == self.size,
            "held partition changed",
        )?;
        let start: u64 = text(&self.sys.join("start"))?
            .trim()
            .parse()
            .map_err(|_| "partition start")?;
        check(start * 512 == self.first, "partition start changed")?;
        if writable {
            check(
                !mounted(self.rdev)?
                    && fs::read_dir(self.sys.join("holders"))
                        .map_err(|e| e.to_string())?
                        .next()
                        .is_none(),
                "target became in-use",
            )?
        }
        Ok(())
    }
}
struct Mount {
    path: PathBuf,
    own: bool,
    writable: bool,
    rdev: u64,
    id: String,
}
fn mount_id(path: &Path, rdev: u64) -> Result<(String, bool)> {
    let id = format!("{}:{}", libc::major(rdev), libc::minor(rdev));
    let s = path.to_str().ok_or("mount path encoding")?;
    let mut matches = Vec::new();
    for l in text(Path::new("/proc/self/mountinfo"))?.lines() {
        let v: Vec<_> = l.split_whitespace().collect();
        if v.get(4) == Some(&s) {
            let sep = v.iter().position(|x| *x == "-").ok_or("mount separator")?;
            check(
                v.get(2) == Some(&id.as_str())
                    && v.get(3) == Some(&"/")
                    && v.get(sep + 1) == Some(&"vfat"),
                "wrong ESP mount/device/root",
            )?;
            matches.push((v[0].to_string(), v[5].split(',').any(|o| o == "rw")))
        }
    }
    check(matches.len() == 1, "unique exact ESP mount required")?;
    Ok(matches.remove(0))
}
impl Mount {
    fn open(group: &Group, esp: &Esp, part: &Partition, linux: bool) -> Result<Self> {
        if let Some(path) = esp_mount(group, esp)? {
            let path = PathBuf::from(path);
            trusted(&path)?;
            check(
                fs::canonicalize(&path).map_err(|e| e.to_string())? == path,
                "ESP path alias",
            )?;
            let (id, writable) = mount_id(&path, part.rdev)?;
            return Ok(Self {
                path,
                own: false,
                writable,
                rdev: part.rdev,
                id,
            });
        }
        check(!linux, "Linux requires actual loaded ESP mount")?;
        check(
            unsafe { libc::unshare(libc::CLONE_NEWNS) } == 0,
            "private mount namespace unavailable",
        )?;
        let slash = CString::new("/").unwrap();
        if unsafe {
            libc::mount(
                std::ptr::null(),
                slash.as_ptr(),
                std::ptr::null(),
                libc::MS_REC | libc::MS_PRIVATE,
                std::ptr::null(),
            )
        } != 0
        {
            return Err(os_error());
        }
        let path = PathBuf::from("/dev/boot-choice-esp");
        if !path.exists() {
            fs::DirBuilder::new()
                .mode(0o700)
                .create(&path)
                .map_err(|e| e.to_string())?
        }
        trusted(&path)?;
        check(
            fs::symlink_metadata(&path)
                .map_err(|e| e.to_string())?
                .is_dir()
                && fs::symlink_metadata(&path)
                    .map_err(|e| e.to_string())?
                    .mode()
                    & 0o777
                    == 0o700
                && fs::read_dir(&path)
                    .map_err(|e| e.to_string())?
                    .next()
                    .is_none(),
            "private mountpoint not empty",
        )?;
        let source = CString::new(format!("/proc/self/fd/{}", part.file.as_raw_fd())).unwrap();
        let target = CString::new(path.to_str().unwrap()).unwrap();
        let kind = CString::new("vfat").unwrap();
        let data = CString::new("uid=0,gid=0,umask=0077").unwrap();
        if unsafe {
            libc::mount(
                source.as_ptr(),
                target.as_ptr(),
                kind.as_ptr(),
                libc::MS_RDONLY | libc::MS_NODEV | libc::MS_NOSUID | libc::MS_NOEXEC,
                data.as_ptr() as _,
            )
        } != 0
        {
            return Err(os_error());
        }
        let (id, writable) = mount_id(&path, part.rdev)?;
        Ok(Self {
            path,
            own: true,
            writable,
            rdev: part.rdev,
            id,
        })
    }
    fn recheck(&self) -> Result<()> {
        let (id, rw) = mount_id(&self.path, self.rdev)?;
        check(
            id == self.id && rw == self.writable,
            "ESP mount replaced/remounted",
        )?;
        trusted(&self.path)
    }
    fn writeable(&mut self) -> Result<()> {
        self.recheck()?;
        if self.writable {
            return Ok(());
        }
        check(self.own, "existing ESP is read-only; refusing remount")?;
        let path = CString::new(self.path.to_str().unwrap()).unwrap();
        if unsafe {
            libc::mount(
                std::ptr::null(),
                path.as_ptr(),
                std::ptr::null(),
                libc::MS_REMOUNT | libc::MS_NODEV | libc::MS_NOSUID | libc::MS_NOEXEC,
                std::ptr::null(),
            )
        } != 0
        {
            return Err(os_error());
        }
        self.writable = true;
        self.recheck()
    }
    fn finish(&mut self) -> Result<()> {
        if self.own {
            self.recheck()?;
            let p = CString::new(self.path.to_str().unwrap()).unwrap();
            if unsafe { libc::umount2(p.as_ptr(), 0) } != 0 {
                return Err(os_error());
            }
            self.own = false;
        }
        Ok(())
    }
}
impl Drop for Mount {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}
fn snapshot(group: &mut Group) -> Result<[u8; 32]> {
    use authority::{DiskGroup, ReadDisk};
    let mut all = Vec::new();
    for n in 0..group.members.len() {
        let (mut d, b, last) = group.select(n).map_err(str::to_owned)?;
        let mut h = vec![0; b];
        d.read(1, &mut h).map_err(str::to_owned)?;
        all.extend_from_slice(&h);
        let mut z = vec![0; b];
        d.read(last, &mut z).map_err(str::to_owned)?;
        all.extend_from_slice(&z);
        if &h[..8] == b"EFI PART" {
            for header in [&h, &z] {
                let count = le32(header, 80) as usize;
                check(
                    (1..=1024).contains(&count) && le32(header, 84) == 128,
                    "GPT snapshot geometry",
                )?;
                let mut t = vec![0; (count * 128).div_ceil(b) * b];
                d.read(le64(header, 72), &mut t).map_err(str::to_owned)?;
                all.extend_from_slice(&t)
            }
        }
    }
    Ok(hash(&all))
}
pub(crate) struct Session {
    observed: Vec<u8>,
    group: Group,
    pub target: authority::Target,
    pub ctx: [u8; 96],
    source_path: PathBuf,
    source: Vec<u8>,
    loader: Option<(PathBuf, Vec<u8>)>,
    pub linux: bool,
    board: Board,
    esp: Esp,
    boot: Partition,
    esp_part: Partition,
    mount: Mount,
    pub store: Store,
    gpt: [u8; 32],
    _lock: File,
}
impl Session {
    pub fn acquire() -> Result<Self> {
        check(
            unsafe { libc::geteuid() } == 0,
            "root operation owner required",
        )?;
        let linux = Path::new("/sys/firmware/efi").is_dir();
        let board = Board::read(linux)?;
        let source_path = if linux {
            PathBuf::from(format!(
                "/sys/firmware/efi/efivars/{}-{}",
                provenance::NAME,
                provenance::GUID
            ))
        } else {
            PathBuf::from("/proc/bootconfig")
        };
        let source = small(&source_path, 1024 * 1024)?;
        let (ctx, loader) = if linux {
            provenance::decode(&source)?;
            let p=PathBuf::from("/sys/firmware/efi/efivars/LoaderDevicePartUUID-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f");
            let b = small(&p, 256)?;
            loader_uuid(&b)?;
            (
                <[u8; 96]>::try_from(&source[4..]).map_err(|_| "context length")?,
                Some((p, b)),
            )
        } else {
            android_unlocked(&source)?;
            let init = small(Path::new("/proc/1/cmdline"), 4096)?;
            check(
                matches!(
                    init.split(|b| *b == 0).next(),
                    Some(b"/init" | b"/system/bin/init")
                ),
                "Android init identity required; no Linux fallback",
            )?;
            (context_for(android_slot(&source)?, &[1; 32], 1, 1), None)
        };
        let mut group = Group::acquire()?;
        let lockpath = PathBuf::from(format!(
            "/dev/.boot-choice-{}",
            hex(&hash(group.controller.as_os_str().as_encoded_bytes()))
        ));
        let lockfile = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&lockpath)
            .map_err(|e| e.to_string())?;
        trusted(&lockpath)?;
        check(
            lockfile.metadata().map_err(|e| e.to_string())?.is_file(),
            "controller lock type",
        )?;
        let mut stat = unsafe { std::mem::zeroed::<libc::statfs>() };
        check(
            unsafe { libc::fstatfs(lockfile.as_raw_fd(), &mut stat) } == 0
                && stat.f_type as u64 == 0x01021994,
            "controller lock must be on dev tmpfs",
        )?;
        lock(&lockfile)?;
        let count = group.members.len();
        let target = authority::inspect_group(&mut group, &ctx, count).map_err(str::to_owned)?;
        let esp = esp(&mut group)?;
        if let Some((_, b)) = &loader {
            check(
                loader_uuid(b)? == esp.uuid,
                "actual loaded ESP UUID mismatch",
            )?
        }
        let boot = partition(
            &group,
            target.index,
            target.lba,
            target.image.len() as u64,
            true,
        )?;
        let m = &group.members[esp.member];
        let esp_part = partition(
            &group,
            esp.member,
            esp.first,
            (esp.last - esp.first + 1) * m.block as u64,
            false,
        )?;
        let mount = Mount::open(&group, &esp, &esp_part, linux)?;
        let store = Store::new(
            mount.path.clone(),
            esp_part.file.try_clone().map_err(|e| e.to_string())?,
        )?;
        check(
            store
                .directory()?
                .metadata()
                .map_err(|e| e.to_string())?
                .dev()
                == esp_part.rdev,
            "ESP root descriptor identity",
        )?;
        let gpt = snapshot(&mut group)?;
        let mut observed = vec![0; target.image.len()];
        crate::media::read_at(&boot.file, &mut observed, 0).map_err(|e| e.to_string())?;
        check(
            observed == target.image,
            "held partition disagrees with inspected whole-LUN image",
        )?;
        let mut s = Self {
            observed,
            group,
            target,
            ctx,
            source_path,
            source,
            loader,
            linux,
            board,
            esp,
            boot,
            esp_part,
            mount,
            store,
            gpt,
            _lock: lockfile,
        };
        s.gate()?;
        Ok(s)
    }
    pub fn gate(&mut self) -> Result<()> {
        check(Board::read(self.linux)? == self.board, "device board identity changed")?;
        self.group.recheck()?;
        self.boot.recheck(true)?;
        self.esp_part.recheck(false)?;
        self.mount.recheck()?;
        check(
            self.store
                .directory()?
                .metadata()
                .map_err(|e| e.to_string())?
                .dev()
                == self.esp_part.rdev,
            "ESP descriptor changed",
        )?;
        check(
            small(&self.source_path, 1024 * 1024)? == self.source,
            "boot provenance changed",
        )?;
        if let Some((p, b)) = &self.loader {
            check(
                small(p, 256)? == *b && loader_uuid(b)? == self.esp.uuid,
                "loaded ESP changed",
            )?
        }
        check(
            snapshot(&mut self.group)? == self.gpt,
            "GPT changed before write",
        )
    }
    pub fn assert_observed(&self) -> Result<()> {
        check(
            self.read_image()? == self.observed,
            "target changed outside serialized operation",
        )
    }
    pub fn probe(&mut self) -> Result<()> {
        self.gate()?;
        self.assert_observed()?;
        self.mount.writeable()?;
        flush_boot(&self.boot.file)?;
        self.store.sync()
    }
    pub fn read_image(&self) -> Result<Vec<u8>> {
        let mut b = vec![0; self.target.image.len()];
        crate::media::read_at(&self.boot.file, &mut b, 0).map_err(|e| e.to_string())?;
        Ok(b)
    }
    pub fn write_page(&mut self, offset: usize, bytes: &[u8]) -> Result<()> {
        self.gate()?;
        check(
            bytes.len() == 4096 && offset % 4096 == 0 && offset <= self.target.image.len() - 4096,
            "bounded target page write",
        )?;
        checked_page(
            &self.boot.file,
            &mut self.observed,
            offset,
            bytes,
            |f, b, at| crate::media::write_at(f, b, at),
        )
    }

    pub fn flush(&mut self) -> Result<()> {
        self.gate()?;
        flush_boot(&self.boot.file)
    }
    pub fn finish(&mut self) -> Result<()> {
        self.store.close_root()?;
        self.mount.finish()
    }
    pub fn bind_context(&mut self, pending: Option<&[u8]>) -> Result<()> {
        if !self.linux {
            let (generation, sequence, mode) = match Image::verify(&self.target.image) {
                Ok(v) => (v.generation, v.sequence, v.mode),
                Err(_) => {
                    let b = pending.ok_or("unowned/corrupt image without pending journal")?;
                    check(
                        b.len() == transaction::JOURNAL_SIZE
                            && &b[..8] == b"BCUNDO01"
                            && hash(&b[..b.len() - 32]) == b[b.len() - 32..],
                        "pending preference journal integrity",
                    )?;
                    let g = b[72..104].try_into().unwrap();
                    let seq = le64(b, 104);
                    let mode = le32(b, 204);
                    check(seq > 0 && mode <= 1, "pending preference journal state")?;
                    (g, seq, mode)
                }
            };
            self.ctx = context_for(android_slot(&self.source)?, &generation, sequence, mode)
        }
        Ok(())
    }
}
struct PreferenceIo<'a>(&'a mut Session, [usize; 3]);
impl transaction::Io for PreferenceIo<'_> {
    fn probe(&mut self) -> authority::Result<()> {
        self.0
            .probe()
            .map_err(|_| "target/ESP sync or authority probe")
    }
    fn journal_read(&mut self) -> authority::Result<Option<Vec<u8>>> {
        self.0
            .store
            .read(PREF, transaction::JOURNAL_SIZE)
            .map_err(|_| "ESP journal open/read")
    }
    fn journal_create(&mut self, b: &[u8]) -> authority::Result<()> {
        self.0
            .gate()
            .and_then(|_| self.0.assert_observed())
            .map_err(|_| "authority changed")?;
        self.0
            .store
            .create(PREF, b)
            .map_err(|_| "durable ESP journal create/sync/close/readback")
    }
    fn journal_remove(&mut self) -> authority::Result<()> {
        self.0.gate().map_err(|_| "authority changed")?;
        self.0
            .store
            .remove(PREF)
            .map_err(|_| "durable journal removal")
    }
    fn read(&mut self, lba: u64, b: &mut [u8]) -> authority::Result<()> {
        if lba != self.0.target.lba || b.len() != self.0.target.image.len() {
            return Err("readback extent");
        };
        b.copy_from_slice(&self.0.read_image().map_err(|_| "target readback")?);
        Ok(())
    }
    fn write(&mut self, lba: u64, b: &[u8]) -> authority::Result<()> {
        self.0
            .assert_observed()
            .map_err(|_| "target changed before preference region")?;
        let at = lba
            .checked_sub(self.0.target.lba)
            .and_then(|v| v.checked_mul(self.0.target.block as u64))
            .ok_or("write extent")?;
        if b.len() != 4096 || !self.1.contains(&(at as usize)) {
            return Err("preference region guard");
        };
        self.0
            .write_page(at as usize, b)
            .map_err(|_| "boot write/identity gate")
    }
    fn flush(&mut self) -> authority::Result<()> {
        self.0.flush().map_err(|_| "block flush/identity gate")
    }
}
pub fn preference(mode: u32, reset: bool) -> Result<()> {
    check(mode <= 1, "preference")?;
    let mut s = Session::acquire()?;
    check(
        s.store.read(FULL, 320 * 1024 * 1024)?.is_none(),
        "pending full-image operation; run boot-choice recover first",
    )?;
    let pending = s.store.read(PREF, transaction::JOURNAL_SIZE)?;
    s.bind_context(pending.as_deref())?;
    // Keep an independently immutable observation for transport range checks;
    // the portable policy owns and refreshes its target/context copies.
    let mut t = authority::Target {
        index: s.target.index,
        block: s.target.block,
        lba: s.target.lba,
        disk_guid: s.target.disk_guid,
        part_guid: s.target.part_guid,
        image: s.target.image.clone(),
    };
    let mut ctx = s.ctx;
    let pending_flag = u32::from(le32(&ctx, 72) != mode);
    ctx[76..80].copy_from_slice(&mode.to_le_bytes());
    ctx[80..84].copy_from_slice(&pending_flag.to_le_bytes());
    // Refreshed() deliberately clears intent, so use the checked wire CRC here.
    let mut sum = !0u32;
    for (i, b) in ctx[16..].iter().enumerate() {
        sum ^= if (76..80).contains(&i) { 0 } else { *b as u32 };
        for _ in 0..8 {
            sum = (sum >> 1) ^ (0xedb88320u32.wrapping_mul(sum & 1));
        }
    }
    ctx[92..96].copy_from_slice(&(!sum).to_le_bytes());
    let basis = preference_basis(&s.target.image, pending.as_deref())?;
    let v = Image::verify(&basis).map_err(str::to_owned)?;
    let allowed = [v.pages, v.pages + 4096, v.body.div_ceil(4096) * 4096];
    let result = transaction::execute(&mut PreferenceIo(&mut s, allowed), &mut t, &mut ctx, false)
        .map_err(str::to_owned);
    if let Err(error) = result {
        if let Ok(v) = Image::verify(&t.image) {
            if let Ok(expected) = Image::request(&t.image, &v.generation, v.sequence, mode) {
                if s.read_image().is_ok_and(|b| b == expected) {
                    return Err(format!("requested preference VERIFIED on current target, but {error}; no reboot requested; recovery/cleanup required"));
                }
            }
        }
        return Err(error);
    }
    s.finish().map_err(|e| {
        format!("preference VERIFIED/COMMITTED; ESP cleanup failed, no reboot requested: {e}")
    })?;
    reset_after_verified(reset, s.linux, standard_reset)
}
fn reset_after_verified(
    reset: bool,
    linux: bool,
    request: impl FnOnce(bool) -> Result<()>,
) -> Result<()> {
    if reset {
        request(linux)
            .map_err(|e| format!("preference VERIFIED/COMMITTED; standard reboot failed: {e}"))?
    }
    Ok(())
}
fn standard_reset(linux: bool) -> Result<()> {
    let (path, args) = if linux {
        let init = fs::canonicalize("/proc/1/exe").map_err(|e| e.to_string())?;
        let package = init
            .parent()
            .and_then(Path::parent)
            .and_then(Path::parent)
            .ok_or("systemd package path")?;
        (package.join("bin/systemctl"), vec!["reboot"])
    } else {
        android_reset_command()
    };
    let argv0 = path.file_name().ok_or("reboot command name")?.to_owned();
    let path = fs::canonicalize(path).map_err(|e| e.to_string())?;
    trusted(&path)?;
    let result = Command::new(path)
        .arg0(argv0)
        .env_clear()
        .args(args)
        .status()
        .map_err(|e| e.to_string())?;
    check(result.success(), "OS reboot request refused")
}

fn preference_basis(image: &[u8], pending: Option<&[u8]>) -> Result<Vec<u8>> {
    if Image::verify(image).is_ok() {
        return Ok(image.to_vec());
    }
    let b = pending.ok_or("corrupt image without undo")?;
    check(
        b.len() == transaction::JOURNAL_SIZE
            && &b[..8] == b"BCUNDO01"
            && hash(&b[..b.len() - 32]) == b[b.len() - 32..],
        "undo integrity",
    )?;
    let mut old = image.to_vec();
    for i in 0..2 {
        let at = usize::try_from(le64(b, 120 + i * 8)).map_err(|_| "undo offset")?;
        check(
            at % 4096 == 0 && at <= old.len() - 4096,
            "undo offset bound",
        )?;
        old[at..at + 4096].copy_from_slice(&b[224 + i * 4096..224 + (i + 1) * 4096])
    }
    check(hash(&old) == b[136..168], "undo original digest")?;
    Image::verify(&old).map_err(str::to_owned)?;
    Ok(old)
}

impl Drop for Session {
    fn drop(&mut self) {
        let _ = self.store.close_root();
        let _ = self.mount.finish();
    }
}

use crate::{
    install_transaction as full,
    live_fs::{HELPER, MENU, RECEIPT},
};
use serde::{Deserialize, Serialize};
const MENU_BYTES:&[u8]=b"title Reboot to Android\nsort-key z-android-action\nefi /EFI/android-devices/boot-choice.efi\noptions target=android\n";
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    schema: u32,
    baseline: [u8; 32],
    originals: Vec<full::FileChange>,
    installed: Vec<(String, [u8; 32])>,
}
struct FullIo<'a>(&'a mut Session);
impl full::Io for FullIo<'_> {
    fn probe(&mut self) -> Result<()> {
        self.0.probe()
    }
    fn read(&mut self) -> Result<Vec<u8>> {
        self.0.read_image()
    }
    fn write(&mut self, at: usize, b: &[u8]) -> Result<()> {
        self.0.write_page(at, b)
    }
    fn flush(&mut self) -> Result<()> {
        self.0.flush()
    }
    fn journal_read(&mut self) -> Result<Option<Vec<u8>>> {
        self.0.store.read(FULL, full::CAP)
    }
    fn journal_create(&mut self, b: &[u8]) -> Result<()> {
        self.0.gate()?;
        self.0.assert_observed()?;
        self.0.store.create(FULL, b)
    }
    fn journal_remove(&mut self) -> Result<()> {
        self.0.gate()?;
        self.0.store.remove(FULL)
    }
    fn file_read(&mut self, name: &str) -> Result<Option<Vec<u8>>> {
        self.0.store.read(name, 24 * 1024 * 1024)
    }
    fn file_replace(&mut self, name: &str, b: Option<&[u8]>, nonce: &str) -> Result<()> {
        self.0.gate()?;
        self.0.store.replace(name, b, nonce)
    }
    fn scratch_read(&mut self, name: &str, nonce: &str) -> Result<Option<Vec<u8>>> {
        self.0
            .store
            .read(&format!("{name}.{nonce}.new"), 24 * 1024 * 1024)
    }
    fn scratch_remove(&mut self, name: &str, nonce: &str) -> Result<()> {
        self.0.gate()?;
        self.0.store.retire_scratch(name, nonce)
    }
}
fn clone_target(t: &authority::Target) -> authority::Target {
    authority::Target {
        index: t.index,
        block: t.block,
        lba: t.lba,
        disk_guid: t.disk_guid,
        part_guid: t.part_guid,
        image: t.image.clone(),
    }
}
fn preference_ranges(image: &[u8], pending: Option<&[u8]>) -> Result<[usize; 3]> {
    let old = preference_basis(image, pending)?;
    let v = Image::verify(&old).map_err(str::to_owned)?;
    Ok([v.pages, v.pages + 4096, v.body.div_ceil(4096) * 4096])
}
fn context_state(s: &Session) -> Result<Option<full::State>> {
    if !s.linux {
        return Ok(None);
    }
    let c = context::decode(&s.ctx).map_err(str::to_owned)?;
    Ok(Some(full::State {
        generation: c.generation,
        sequence: c.sequence,
        mode: c.stored,
    }))
}
const RECEIPT_ORIGINAL_MAX: usize = 4 * 1024 * 1024;
const RECEIPT_MAX: usize = 24 * 1024 * 1024;
fn validate_receipt(r: &Receipt) -> Result<()> {
    check(
        r.schema == 1 && r.originals.len() == 2 && r.installed.len() == 2,
        "installation receipt schema",
    )?;
    let mut seen = Vec::new();
    for f in &r.originals {
        check(
            [HELPER, MENU].contains(&f.name.as_str())
                && !seen.contains(&f.name)
                && f.after.is_none()
                && f.before
                    .as_ref()
                    .is_none_or(|b| b.len() <= RECEIPT_ORIGINAL_MAX),
            "receipt original files",
        )?;
        seen.push(f.name.clone())
    }
    let mut seen = Vec::new();
    for (name, _) in &r.installed {
        check(
            [HELPER, MENU].contains(&name.as_str()) && !seen.contains(name),
            "receipt installed file identities",
        )?;
        seen.push(name.clone());
    }
    Ok(())
}
fn file_plan(
    mut read: impl FnMut(&str) -> Result<Option<Vec<u8>>>,
    old: &[u8],
    new: &[u8],
    helper: Option<&[u8]>,
    restore: bool,
) -> Result<Vec<full::FileChange>> {
    let before = read(RECEIPT)?;
    check(
        before.as_ref().is_none_or(|b| b.len() <= RECEIPT_MAX),
        "installation receipt size",
    )?;
    let original = if let Ok(_) = Image::verify(old) {
        Image::restore(old).map_err(str::to_owned)?
    } else {
        old.to_vec()
    };
    let saved: Option<Receipt> = before
        .as_ref()
        .map(|b| serde_json::from_slice(b).map_err(|e| e.to_string()))
        .transpose()?;
    if let Some(r) = &saved {
        validate_receipt(r)?;
        for (name, digest) in &r.installed {
            let now = read(name)?.ok_or("installed owned ESP file missing")?;
            check(
                hash(&now) == *digest,
                "installed ESP file was changed; refusing overwrite/delete",
            )?
        }
        if Image::verify(old).is_ok() {
            check(
                r.baseline == hash(&original),
                "foreign installation receipt baseline",
            )?
        }
    }
    if restore {
        let Some(r) = saved else {
            return Ok(Vec::new());
        };
        let mut changes = Vec::new();
        for f in r.originals {
            changes.push(full::FileChange {
                name: f.name.clone(),
                before: read(&f.name)?,
                after: f.before,
            })
        }
        changes.push(full::FileChange {
            name: RECEIPT.into(),
            before,
            after: None,
        });
        return Ok(changes);
    }
    let helper = helper.ok_or("matched native helper")?;
    let mut originals = Vec::new();
    let mut changes = Vec::new();
    for (name, bytes) in [(HELPER, helper), (MENU, MENU_BYTES)] {
        let current = read(name)?;
        check(
            current
                .as_ref()
                .is_none_or(|b| b.len() <= RECEIPT_ORIGINAL_MAX),
            "receipt original file exceeds supported bound",
        )?;
        originals.push(full::FileChange {
            name: name.into(),
            before: current.clone(),
            after: None,
        });
        changes.push(full::FileChange {
            name: name.into(),
            before: current,
            after: Some(bytes.to_vec()),
        })
    }
    if let Some(r) = saved {
        originals = r.originals
    }
    let baseline = Image::restore(new).map_err(str::to_owned)?;
    let receipt = Receipt {
        schema: 1,
        baseline: hash(&baseline),
        originals,
        installed: vec![
            (HELPER.into(), hash(helper)),
            (MENU.into(), hash(MENU_BYTES)),
        ],
    };
    validate_receipt(&receipt)?;
    let encoded = serde_json::to_vec(&receipt).map_err(|e| e.to_string())?;
    // Encoder must never publish a receipt the read/validation path cannot use.
    check(encoded.len() <= RECEIPT_MAX, "installation receipt size")?;
    changes.push(full::FileChange {
        name: RECEIPT.into(),
        before,
        after: Some(encoded),
    });
    Ok(changes)
}
/// Native full-image write operations; policy paths/slot are never caller input.
pub fn image_operation(operation: &str, bundle: Option<&Path>) -> Result<()> {
    check(
        ["install", "update", "restore"].contains(&operation),
        "live image operation",
    )?;
    let mut s = Session::acquire()?;
    let template = if let Some(p) = bundle {
        // The Android /data exception is available only after actual current
        // Android init/bootconfig/unlock/model authority has been established.
        let t = crate::trusted_template::load(p, !s.linux)?;
        // Trusted publisher content + manifest digests remain the boundary;
        // also reject accidentally selecting an older, unguarded helper.
        let capability: Vec<u8> = "\\EFI\\android-devices\\boot-choice.install.undo"
            .encode_utf16()
            .flat_map(u16::to_le_bytes)
            .collect();
        check(
            t.helper()
                .windows(capability.len())
                .any(|b| b == capability),
            "template helper lacks native full-journal guard; use current exported template",
        )?;
        Some(t)
    } else {
        None
    };
    let identity = full::Identity {
        disk: s.target.disk_guid,
        part: s.target.part_guid,
        esp: s.esp.uuid.clone(),
        controller: hex(&s.gpt),
        lba: s.target.lba,
        block: s.target.block,
        size: s.target.image.len(),
        slot: context::decode(&s.ctx).map_err(str::to_owned)?.slot,
    };
    let state = context_state(&s)?;
    let recovered = full::recover(&mut FullIo(&mut s), &identity, state.as_ref())?;
    s.target.image = s.read_image()?;
    if recovered && s.linux && s.target.verify(&s.ctx).is_err() {
        s.finish()?;
        return Err(
            "previous full operation recovered/committed; reboot before another live operation"
                .into(),
        );
    }
    let pending = s.store.read(PREF, transaction::JOURNAL_SIZE)?;
    if pending.is_some() {
        s.bind_context(pending.as_deref())?;
        let mut t = clone_target(&s.target);
        let mut ctx = s.ctx;
        let ranges = preference_ranges(&t.image, pending.as_deref())?;
        transaction::recover_pending(&mut PreferenceIo(&mut s, ranges), &mut t, &mut ctx)
            .map_err(str::to_owned)?;
        s.ctx = ctx;
        s.target.image = t.image;
        if s.linux && s.ctx.as_slice() != &s.source[4..] {
            s.finish()?;
            return Err("preference recovery committed; reboot before full-image operation".into());
        }
    }
    let old = s.target.image.clone();
    let owned = Image::verify(&old);
    if s.linux {
        s.target.verify(&s.ctx).map_err(str::to_owned)?
    }
    let (new, kind, helper) = match operation {
        "restore" => (
            Image::restore(&old).map_err(str::to_owned)?,
            "restore",
            None,
        ),
        "update" => {
            owned.map_err(str::to_owned)?;
            let t = template
                .as_ref()
                .ok_or("update requires trusted template")?;
            (t.update(&old)?, "update", Some(t.helper()))
        }
        "install" => {
            let t = template
                .as_ref()
                .ok_or("install requires trusted template")?;
            if owned.is_ok() {
                (t.update(&old)?, "update", Some(t.helper()))
            } else {
                check(
                    !s.linux,
                    "fresh adoption requires actual Android boot context",
                )?;
                (t.embed(&old)?, "install", Some(t.helper()))
            }
        }
        _ => unreachable!(),
    };
    let files = file_plan(
        |name| s.store.read(name, RECEIPT_MAX),
        &old,
        &new,
        helper,
        operation == "restore",
    )?;
    let state = context_state(&s)?;
    full::execute(
        &mut FullIo(&mut s),
        &identity,
        state.as_ref(),
        kind,
        &old,
        &new,
        files,
    )?;
    s.finish()?;
    println!(
        "{operation}: exact current-target image and owned ESP files VERIFIED; no reboot requested"
    );
    Ok(())
}

pub fn recover() -> Result<()> {
    let mut s = Session::acquire()?;
    let identity = full::Identity {
        disk: s.target.disk_guid,
        part: s.target.part_guid,
        esp: s.esp.uuid.clone(),
        controller: hex(&s.gpt),
        lba: s.target.lba,
        block: s.target.block,
        size: s.target.image.len(),
        slot: context::decode(&s.ctx).map_err(str::to_owned)?.slot,
    };
    let state = context_state(&s)?;
    let complete = full::recover(&mut FullIo(&mut s), &identity, state.as_ref())?;
    s.target.image = s.read_image()?;
    let pending = s.store.read(PREF, transaction::JOURNAL_SIZE)?;
    if pending.is_some() {
        s.bind_context(pending.as_deref())?;
        let mut t = clone_target(&s.target);
        let mut ctx = s.ctx;
        let ranges = preference_ranges(&t.image, pending.as_deref())?;
        transaction::recover_pending(&mut PreferenceIo(&mut s, ranges), &mut t, &mut ctx)
            .map_err(str::to_owned)?;
    } else if !complete {
        s.bind_context(None)?;
        s.target.verify(&s.ctx).map_err(str::to_owned)?;
    }
    s.finish()?;
    println!("pending operation recovery VERIFIED; no reboot requested");
    Ok(())
}
#[cfg(test)]
#[path = "live_owner_tests.rs"]
mod tests;

pub(super) fn checked_page(
    file: &File,
    observed: &mut [u8],
    at: usize,
    bytes: &[u8],
    write: impl FnOnce(&File, &[u8], u64) -> io::Result<usize>,
) -> Result<()> {
    check(
        bytes.len() == 4096
            && at % 4096 == 0
            && observed.len() >= 4096
            && at <= observed.len() - 4096,
        "bounded held-target page",
    )?;
    let mut page = [0u8; 4096];
    crate::media::read_at(file, &mut page, at as u64).map_err(|e| e.to_string())?;
    check(
        page == observed[at..at + 4096],
        "target page changed immediately before write",
    )?;
    let result = write(file, bytes, at as u64);
    // A failed/short block call may already have changed bytes. Observe that
    // exact region so the bounded policy can roll it back, not blindly assume it.
    crate::media::read_at(file, &mut page, at as u64).map_err(|e| e.to_string())?;
    observed[at..at + 4096].copy_from_slice(&page);
    let n = result.map_err(|e| e.to_string())?;
    check(
        n == 4096 && page == bytes,
        "short/incorrect boot page write",
    )
}

fn android_unlocked(source: &[u8]) -> Result<()> {
    let data = std::str::from_utf8(source).map_err(|_| "bootconfig encoding")?;
    let value = |key: &str| -> Result<Option<String>> {
        let mut out = None;
        for line in data.lines() {
            let Some((k, v)) = line.split_once('=') else {
                continue;
            };
            if k.trim() != key {
                continue;
            }
            check(out.is_none(), "duplicate unlock metadata")?;
            let v = v.trim();
            let v = if v.starts_with('"') {
                v.strip_prefix('"')
                    .and_then(|v| v.strip_suffix('"'))
                    .ok_or("unlock metadata quoting")?
            } else {
                v
            };
            check(!v.contains(['"', '\\']), "unlock metadata syntax")?;
            out = Some(v.to_string())
        }
        Ok(out)
    };
    let state = value("androidboot.verifiedbootstate")?;
    let device = value("androidboot.vbmeta.device_state")?;
    let locked = value("androidboot.flash.locked")?;
    check(
        state.as_deref() == Some("orange") || device.as_deref() == Some("unlocked"),
        "positive unlocked Android metadata required",
    )?;
    check(
        state.as_deref().is_none_or(|s| s == "orange")
            && device.as_deref().is_none_or(|s| s == "unlocked")
            && locked.as_deref().is_none_or(|s| s == "0"),
        "contradictory/locked Android boot metadata",
    )
}

fn flush_boot(file: &File) -> Result<()> {
    file.sync_all().map_err(|e| e.to_string())?;
    // Direct media reads/writes bypass both partition and parent-LUN aliases.
    // Durability is fsync; no BLKFLSBUF/cache invalidation workaround.
    Ok(())
}

fn android_reset_command() -> (PathBuf, Vec<&'static str>) {
    (PathBuf::from("/system/bin/reboot"), Vec::new())
}
