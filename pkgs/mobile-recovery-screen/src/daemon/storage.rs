//! Explicit device adapter. No board-name dispatch or implicit mounts by this daemon.
use super::{
    engine::Job,
    gpt::{Gpt, Partition},
};
use anyhow::{ensure, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    os::{
        fd::AsRawFd,
        unix::fs::{FileTypeExt, OpenOptionsExt, PermissionsExt},
    },
    path::{Path, PathBuf},
    process::Command,
};
fn slot_hints(cmdline: &str, boot: &str) -> Result<(bool, Option<String>)> {
    let mut uuid = None;
    let mut seen = false;
    for arg in cmdline.split_whitespace() {
        if let Some((key, value)) = arg.split_once('=') {
            match key {
                "androidboot.slot_suffix" | "boot.slot_suffix" => {
                    ensure!(value == "_b", "conflicting boot slot hint");
                    seen = true;
                }
                "androidboot.vbmeta.device" => {
                    let v = value
                        .strip_prefix("PARTUUID=")
                        .context("unsupported vbmeta hint")?;
                    ensure!(
                        uuid.as_ref().is_none_or(|old| old == v),
                        "conflicting vbmeta hints"
                    );
                    uuid = Some(v.to_string());
                }
                _ => {}
            }
        }
    }
    {
        for line in boot.lines() {
            if let Some((key, v)) = line.split_once('=') {
                if ["androidboot.slot_suffix", "boot.slot_suffix"].contains(&key.trim()) {
                    ensure!(
                        v.trim().trim_matches('"') == "_b",
                        "conflicting bootconfig slot"
                    );
                    seen = true;
                }
            }
        }
    }
    Ok((seen, uuid))
}
/// One storage role of a single-slot device. Only `label` is required: the
/// partition must be the unique GPT entry with that name on the controller.
/// Measured fields, when present, must all match.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Role {
    pub label: String,
    pub partuuid: Option<String>,
    pub number: Option<usize>,
    /// Start in 512-byte units, as reported by blkid PART_ENTRY_OFFSET.
    pub offset: Option<u64>,
    pub bytes: Option<u64>,
    pub min_bytes: Option<u64>,
    pub max_bytes: Option<u64>,
    pub fs_label: Option<String>,
    pub fs_uuid: Option<String>,
    /// Refuse use until partuuid and bytes are measured.
    pub require_measured: bool,
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Roles {
    pub root: Role,
    pub esp: Role,
    pub firmware: Role,
    pub recovery: Role,
    pub misc: Role,
}
/// Installed-state files that must be valid before an offline deployment.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Requirements {
    /// Files that must contain one colon-separated MAC address.
    pub mac_files: Vec<String>,
    /// Directories whose SHA256SUMS must verify.
    pub checksum_dirs: Vec<String>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub identity: String,
    pub compatible: String,
    pub controller: String,
    pub hostname: String,
    pub root_label: String,
    pub esp_bytes: u64,
    pub minimum_root_bytes: u64,
    pub slot_metadata: String,
    pub misc_bytes: usize,
    pub recovery_avb: bool,
    /// "ab": B-only Android A/B layout; "single": one slot with explicit roles.
    pub slot_model: String,
    /// Root compatible required in firmware images.
    pub firmware_compatible: String,
    /// "argument": reboot argument only; "bcb": write boot-recovery to misc.
    pub boot_request: String,
    pub recovery_reboot_argument: Option<String>,
    pub roles: Option<Roles>,
    /// Controller sysfs directory whose clock gating/scaling must be disabled.
    pub ufs_safe_mode: Option<String>,
    pub deploy_requirements: Requirements,
}
/// Filesystem roots for storage resolution; fixtures replace the live paths.
pub struct Host {
    pub sys: PathBuf,
    pub dev: PathBuf,
    pub block_devices: bool,
}
impl Host {
    pub fn live() -> Self {
        Self {
            sys: "/sys".into(),
            dev: "/dev".into(),
            block_devices: true,
        }
    }
}
fn read_trim(p: &Path) -> Result<String> {
    Ok(fs::read_to_string(p)
        .with_context(|| format!("read {}", p.display()))?
        .trim()
        .to_string())
}
/// Resolve a single-slot storage role without external tools: unique GPT name
/// on the controller's non-removable disk, kernel geometry, label symlink and
/// every measured field.
pub fn resolve_role(host: &Host, controller: &str, what: &str, r: &Role) -> Result<Device> {
    ensure!(
        !r.require_measured || (r.partuuid.is_some() && r.bytes.is_some()),
        "{what}: set its measured storage role (partuuid and bytes) before use"
    );
    ensure!(
        !r.label.is_empty() && !r.label.contains('/'),
        "{what}: invalid GPT name"
    );
    let mut found = Vec::new();
    for entry in fs::read_dir(host.sys.join("class/block"))? {
        let path = entry?.path();
        if let Ok(uevent) = fs::read_to_string(path.join("uevent")) {
            if uevent.lines().any(|v| v == format!("PARTNAME={}", r.label)) {
                found.push(path);
            }
        }
    }
    ensure!(
        found.len() == 1,
        "{what}: GPT name {} is missing or not unique",
        r.label
    );
    let sys = fs::canonicalize(&found[0])?;
    ensure!(
        sys.components().any(|v| v.as_os_str() == controller),
        "{what} is on another controller"
    );
    let disk_sys = sys.parent().context("missing disk")?;
    ensure!(
        read_trim(&disk_sys.join("removable"))? == "0",
        "{what} is on a removable disk"
    );
    let sector: u64 = read_trim(&disk_sys.join("queue/logical_block_size"))?.parse()?;
    let disk_bytes = read_trim(&disk_sys.join("size"))?.parse::<u64>()? * 512;
    let node = host.dev.join(sys.file_name().context("partition name")?);
    let disk = host.dev.join(disk_sys.file_name().context("disk name")?);
    if host.block_devices {
        ensure!(
            fs::metadata(&node)?.file_type().is_block_device(),
            "not a block partition"
        );
    }
    let gpt = Gpt::read_sector(&File::open(&disk)?, disk_bytes, sector)?;
    let entry = gpt.partition(&r.label)?.clone();
    ensure!(
        read_trim(&sys.join("partition"))?.parse::<usize>()? == entry.number
            && read_trim(&sys.join("start"))?.parse::<u64>()? == entry.start * sector / 512
            && read_trim(&sys.join("size"))?.parse::<u64>()? == entry.bytes() / 512,
        "{what}: kernel partition geometry differs from GPT"
    );
    ensure!(
        fs::canonicalize(host.dev.join("disk/by-partlabel").join(&r.label))?
            == fs::canonicalize(&node)?,
        "{what}: partition label symlink mismatch"
    );
    if let Some(v) = &r.partuuid {
        ensure!(
            v.eq_ignore_ascii_case(&entry.uuid),
            "{what}: GPT UUID mismatch"
        );
    }
    if let Some(v) = r.number {
        ensure!(v == entry.number, "{what}: GPT number mismatch");
    }
    if let Some(v) = r.offset {
        ensure!(
            v == entry.start * sector / 512,
            "{what}: GPT offset mismatch"
        );
    }
    if let Some(v) = r.bytes {
        ensure!(v == entry.bytes(), "{what}: partition size mismatch");
    }
    ensure!(
        r.min_bytes.is_none_or(|v| entry.bytes() >= v)
            && r.max_bytes.is_none_or(|v| entry.bytes() <= v),
        "{what}: partition size outside the expected range"
    );
    Ok(Device {
        node,
        disk,
        gpt,
        entry,
    })
}
/// Disable UFS clock gating/scaling before storage access, as the board requires.
pub fn ufs_safe_mode(controller: &Path) -> Result<()> {
    for (name, value) in [
        ("power/control", "on"),
        ("clkgate_enable", "0"),
        ("clkscale_enable", "0"),
    ] {
        let p = controller.join(name);
        fs::write(&p, value).with_context(|| format!("write {}", p.display()))?;
        ensure!(read_trim(&p)? == value, "UFS safe mode not applied: {name}");
    }
    Ok(())
}
/// Validate installed identity/calibration state required before deployment.
pub fn check_requirements(root: &Path, r: &Requirements) -> Result<()> {
    use sha2::{Digest, Sha256};
    for file in &r.mac_files {
        let v =
            fs::read_to_string(inside(root, file)?).with_context(|| format!("missing {file}"))?;
        let v = v.trim();
        ensure!(
            v.len() == 17
                && v.split(':').count() == 6
                && v.split(':')
                    .all(|o| o.len() == 2 && o.bytes().all(|b| b.is_ascii_hexdigit())),
            "invalid identity in {file}"
        );
    }
    for dir in &r.checksum_dirs {
        let base = inside(root, dir)?;
        let sums = fs::read_to_string(base.join("SHA256SUMS"))
            .with_context(|| format!("missing {dir}/SHA256SUMS"))?;
        ensure!(!sums.trim().is_empty(), "empty {dir}/SHA256SUMS");
        for line in sums.lines() {
            let (hash, name) = line.split_once("  ").context("malformed SHA256SUMS")?;
            ensure!(
                !name.is_empty() && !name.starts_with('/') && !name.split('/').any(|c| c == ".."),
                "unsafe SHA256SUMS entry"
            );
            let path = inside(root, &format!("{dir}/{name}"))?;
            ensure!(path.starts_with(&base), "SHA256SUMS entry escapes {dir}");
            let digest = format!("{:x}", Sha256::digest(fs::read(&path)?));
            ensure!(digest == hash, "checksum mismatch: {dir}/{name}");
        }
    }
    Ok(())
}
impl Config {
    pub fn single(&self) -> bool {
        self.slot_model == "single"
    }
    pub fn load() -> Result<Self> {
        let c: Self = serde_json::from_slice(&fs::read("/etc/mobile-recovery.json")?)?;
        c.check()?;
        Ok(c)
    }
    fn check(&self) -> Result<()> {
        let c = self;
        ensure!(
            ["argument", "bcb"].contains(&c.boot_request.as_str())
                && !c.firmware_compatible.is_empty(),
            "invalid boot request or firmware identity"
        );
        if c.single() {
            ensure!(
                c.slot_metadata == "none" && c.roles.is_some() && !c.recovery_avb,
                "single-slot recovery needs storage roles and no A/B metadata"
            );
        } else {
            ensure!(c.slot_model == "ab", "unsupported slot model");
            ensure!(
                c.roles.is_none() && c.ufs_safe_mode.is_none(),
                "A/B recovery uses fixed partition names"
            );
        }
        ensure!(
            ["qcom-gpt", "boot-hints", "none"].contains(&c.slot_metadata.as_str())
                && (c.single() || c.slot_metadata != "none"),
            "unsupported slot metadata"
        );
        ensure!(
            [1048576, 4194304].contains(&c.misc_bytes),
            "unsupported misc capacity"
        );
        ensure!(
            !c.controller.is_empty() && !c.controller.contains('/') && !c.compatible.is_empty(),
            "invalid adapter"
        );
        Ok(())
    }
    pub fn identity(&self) -> Result<()> {
        ensure!(unsafe { libc::geteuid() } == 0, "root is required");
        ensure!(
            fs::read("/proc/device-tree/compatible")?
                .split(|b| *b == 0)
                .any(|s| s == self.compatible.as_bytes()),
            "device-tree identity mismatch"
        );
        ensure!(
            fs::read_to_string("/proc/1/comm")?.trim() == "systemd"
                && Path::new("/etc/initrd-release").is_file()
                && fs::read_to_string("/etc/mobile-ram-recovery")?.trim() == self.identity,
            "use the configured RAM recovery"
        );
        Ok(())
    }
    pub fn slot(&self, j: &Job) -> Result<()> {
        self.identity()?;
        if self.single() {
            if let Some(c) = &self.ufs_safe_mode {
                ufs_safe_mode(Path::new(c))?;
            }
            return Ok(());
        }
        let (seen, uuid) = slot_hints(
            &fs::read_to_string("/proc/cmdline")?,
            &fs::read_to_string("/proc/bootconfig").unwrap_or_default(),
        )?;
        if self.slot_metadata == "qcom-gpt" {
            self.partition(j, "boot_b")?.gpt.selected_b()?;
        } else {
            ensure!(seen || uuid.is_some(), "cannot verify active slot B");
        }
        if let Some(uuid) = uuid {
            ensure!(
                self.partition(j, "vbmeta_b")?
                    .entry
                    .uuid
                    .eq_ignore_ascii_case(&uuid),
                "vbmeta hint does not select B"
            );
        }
        Ok(())
    }
    pub fn ram_gate(&self, j: &Job) -> Result<()> {
        self.slot(j)?;
        for line in fs::read_to_string("/proc/self/mountinfo")?.lines() {
            let fields: Vec<_> = line.split_whitespace().collect();
            ensure!(fields.len() > 6, "malformed mountinfo");
            ensure!(
                !Path::new("/sys/dev/block").join(fields[2]).exists(),
                "unmount all block filesystems first"
            );
            let kind = line
                .split_once(" - ")
                .context("malformed mountinfo")?
                .1
                .split_whitespace()
                .next()
                .unwrap_or("");
            ensure!(
                [
                    "rootfs",
                    "ramfs",
                    "tmpfs",
                    "devtmpfs",
                    "proc",
                    "sysfs",
                    "devpts",
                    "cgroup",
                    "cgroup2",
                    "securityfs",
                    "debugfs",
                    "tracefs",
                    "configfs",
                    "functionfs",
                    "pstore",
                    "mqueue",
                    "bpf",
                    // EFI recovery mounts firmware variables automatically;
                    // this is not a mounted UFS target filesystem.
                    "efivarfs",
                    "fusectl"
                ]
                .contains(&kind),
                "unmount non-RAM filesystem: {kind}"
            );
        }
        ensure!(
            fs::read_to_string("/proc/swaps")?.lines().count() <= 1,
            "disable swap first"
        );
        for entry in fs::read_dir("/sys/class/block")? {
            let p = entry?.path();
            if self.on_controller(&p)? {
                ensure!(
                    fs::read_dir(p.join("holders"))?.next().is_none(),
                    "UFS has active holders"
                );
            }
        }
        Ok(())
    }
    fn on_controller(&self, p: &Path) -> Result<bool> {
        Ok(fs::canonicalize(p)?
            .components()
            .any(|v| v.as_os_str() == self.controller.as_str()))
    }
    pub fn partition(&self, j: &Job, name: &str) -> Result<Device> {
        self.partition_mode(j, name, false)
    }
    pub fn partition_for_backup_repair(&self, j: &Job, name: &str) -> Result<Device> {
        self.partition_mode(j, name, true)
    }
    fn partition_mode(&self, j: &Job, name: &str, repair: bool) -> Result<Device> {
        let mut found = Vec::new();
        for entry in fs::read_dir("/sys/class/block")? {
            let path = entry?.path();
            if let Ok(uevent) = fs::read_to_string(path.join("uevent")) {
                if uevent.lines().any(|v| v == format!("PARTNAME={name}")) {
                    found.push(path);
                }
            }
        }
        ensure!(found.len() == 1, "missing or ambiguous GPT label: {name}");
        let sys = &found[0];
        ensure!(self.on_controller(sys)?, "{name} is on another controller");
        let node = PathBuf::from("/dev").join(sys.file_name().unwrap());
        ensure!(
            fs::metadata(&node)?.file_type().is_block_device(),
            "not a block partition"
        );
        let parent = fs::canonicalize(sys)?
            .parent()
            .context("missing disk")?
            .file_name()
            .context("missing disk name")?
            .to_owned();
        let disk = PathBuf::from("/dev").join(parent);
        let diskstr = disk.to_str().context("disk path")?;
        ensure!(
            j.run(
                Command::new("/bin/blockdev").args(["--getss", diskstr]),
                None
            )?
            .trim()
                == "4096",
            "expected 4096-byte sectors"
        );
        let bytes = j
            .run(
                Command::new("/bin/blockdev").args(["--getsize64", diskstr]),
                None,
            )?
            .trim()
            .parse()?;
        let f = File::open(&disk)?;
        let gpt = if repair {
            Gpt::read_for_backup_repair(&f, bytes)?
        } else {
            Gpt::read(&f, bytes)?
        };
        let entry = gpt.partition(name)?.clone();
        ensure!(
            fs::read_to_string(sys.join("partition"))?
                .trim()
                .parse::<usize>()?
                == entry.number,
            "partition number mismatch"
        );
        ensure!(
            fs::read_to_string(sys.join("start"))?
                .trim()
                .parse::<u64>()?
                == entry.start * 8
                && fs::read_to_string(sys.join("size"))?
                    .trim()
                    .parse::<u64>()?
                    == entry.bytes() / 512,
            "kernel partition geometry differs from GPT"
        );
        ensure!(
            fs::canonicalize(Path::new("/dev/disk/by-partlabel").join(name))? == node,
            "partition label symlink mismatch"
        );
        Ok(Device {
            node,
            disk,
            gpt,
            entry,
        })
    }
    fn roles(&self) -> Result<&Roles> {
        self.roles
            .as_ref()
            .context("storage roles are not configured")
    }
    /// The firmware, recovery or misc partition of this slot model.
    pub fn named(&self, j: &Job, which: &str) -> Result<Device> {
        if self.single() {
            self.slot(j)?;
            let r = self.roles()?;
            let role = match which {
                "firmware" => &r.firmware,
                "recovery" => &r.recovery,
                "misc" => &r.misc,
                _ => anyhow::bail!("unknown storage role {which}"),
            };
            return resolve_role(&Host::live(), &self.controller, which, role);
        }
        let name = match which {
            "firmware" => "boot_b",
            "recovery" => "recovery_b",
            "misc" => "misc",
            _ => anyhow::bail!("unknown storage role {which}"),
        };
        self.partition(j, name)
    }
    fn single_layout(&self, j: &Job, filesystems: bool) -> Result<Layout> {
        self.slot(j)?;
        let r = self.roles()?;
        let host = Host::live();
        let root = resolve_role(&host, &self.controller, "root", &r.root)?;
        let esp = resolve_role(&host, &self.controller, "esp", &r.esp)?;
        ensure!(root.node != esp.node, "root and ESP roles overlap");
        ensure!(
            root.entry.bytes() >= self.minimum_root_bytes
                && (self.esp_bytes == 0 || esp.entry.bytes() == self.esp_bytes),
            "invalid root/ESP sizes"
        );
        if filesystems {
            ensure!(
                probe(j, &root.node, "TYPE")? == "ext4"
                    && probe(j, &root.node, "LABEL")? == self.root_label,
                "expected labelled ext4 root"
            );
            ensure!(
                probe(j, &esp.node, "TYPE")? == "vfat",
                "prepare FAT boot first"
            );
            for (d, role) in [(&root, &r.root), (&esp, &r.esp)] {
                if let Some(uuid) = &role.fs_uuid {
                    ensure!(
                        probe(j, &d.node, "UUID")?.eq_ignore_ascii_case(uuid),
                        "filesystem UUID mismatch"
                    );
                }
            }
            if let Some(label) = &r.esp.fs_label {
                ensure!(
                    &probe(j, &esp.node, "LABEL")? == label,
                    "FAT label mismatch"
                );
            }
        }
        Ok(Layout { root, esp })
    }
    pub fn layout(&self, j: &Job, filesystems: bool) -> Result<Layout> {
        if self.single() {
            return self.single_layout(j, filesystems);
        }
        self.slot(j)?;
        let root = self.partition(j, "linux")?;
        let esp = self.partition(j, "linux-boot")?;
        ensure!(root.disk == esp.disk, "root and ESP are on different disks");
        root.gpt
            .check_linux_layout(self.esp_bytes, self.minimum_root_bytes)?;
        if filesystems {
            ensure!(
                probe(j, &root.node, "TYPE")? == "ext4"
                    && probe(j, &root.node, "LABEL")? == self.root_label,
                "expected labelled ext4 root"
            );
            ensure!(
                probe(j, &esp.node, "TYPE")? == "vfat",
                "prepare FAT boot first"
            );
        }
        Ok(Layout { root, esp })
    }
}
#[derive(Debug)]
pub struct Device {
    pub node: PathBuf,
    pub disk: PathBuf,
    pub gpt: Gpt,
    pub entry: Partition,
}
pub struct Layout {
    pub root: Device,
    pub esp: Device,
}
pub fn probe(j: &Job, p: &Path, field: &str) -> Result<String> {
    Ok(j.run(
        Command::new("/bin/blkid")
            .args(["-p", "-s", field, "-o", "value"])
            .arg(p),
        None,
    )?
    .trim()
    .to_string())
}
pub fn exclusive(p: &Path) -> Result<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_EXCL | libc::O_CLOEXEC)
        .open(p)
        .with_context(|| format!("exclusive open {}", p.display()))
}
pub fn reread(f: &File) -> Result<()> {
    ensure!(
        unsafe { libc::ioctl(f.as_raw_fd(), 0x125f) } == 0,
        "GPT written but kernel reread failed: {}; stay in recovery",
        std::io::Error::last_os_error()
    );
    Ok(())
}
pub fn sync() {
    unsafe {
        libc::sync();
    }
}

/// Resolve absolute symlinks with chroot semantics, never against the live host.
pub fn inside(root: &Path, path: &str) -> Result<PathBuf> {
    ensure!(path.starts_with('/'), "expected absolute target path");
    let mut remaining: std::collections::VecDeque<String> =
        path.split('/').map(String::from).collect();
    let mut resolved: Vec<String> = Vec::new();
    let mut links = 0;
    while let Some(c) = remaining.pop_front() {
        match c.as_str() {
            "" | "." => continue,
            ".." => {
                ensure!(resolved.pop().is_some(), "path escapes target");
                continue;
            }
            _ => {}
        }
        let mut candidate = root.to_path_buf();
        for item in &resolved {
            candidate.push(item);
        }
        candidate.push(&c);
        if fs::symlink_metadata(&candidate).is_ok_and(|m| m.file_type().is_symlink()) {
            links += 1;
            ensure!(links <= 40, "symlink loop");
            let link = fs::read_link(candidate)?;
            let link = link.to_str().context("non-UTF8 symlink")?;
            if link.starts_with('/') {
                resolved.clear();
            }
            for part in link.split('/').rev() {
                remaining.push_front(part.to_string());
            }
        } else {
            resolved.push(c);
        }
    }
    let mut p = root.to_path_buf();
    for c in resolved {
        p.push(c);
    }
    Ok(p)
}
pub fn directory(root: &Path, path: &str) -> Result<PathBuf> {
    let p = root.join(path.trim_start_matches('/'));
    ensure!(
        inside(root, &format!("/{}", path.trim_start_matches('/')))? == p,
        "unsafe target directory: {path}"
    );
    fs::create_dir_all(&p)?;
    ensure!(fs::symlink_metadata(&p)?.is_dir(), "not a directory");
    Ok(p)
}
const STORE_PARENTS: &[&str] = &[
    "nix",
    "nix/store",
    "nix/var",
    "nix/var/nix",
    "nix/var/nix/profiles",
];
/// The daemon's private umask must not make the installed store root-only.
/// Preserve ownership, sticky/group-write bits and all private child directories.
pub fn prepare_store_access(root: &Path) -> Result<()> {
    for name in STORE_PARENTS {
        let p = directory(root, name)?;
        let mode = fs::metadata(&p)?.permissions().mode();
        fs::set_permissions(&p, fs::Permissions::from_mode(mode | 0o555))?;
    }
    check_store_access(root)
}
pub fn check_store_access(root: &Path) -> Result<()> {
    for name in STORE_PARENTS {
        let p = root.join(name);
        ensure!(
            inside(root, &format!("/{name}"))? == p,
            "unsafe store parent: {name}"
        );
        let m = fs::symlink_metadata(&p)?;
        ensure!(m.is_dir() && m.permissions().mode() & 0o555 == 0o555,
            "store parent /{name} is inaccessible to service users; reinstall/select a generation to repair");
    }
    Ok(())
}
#[derive(Default)]
pub struct Mounts {
    pub points: Vec<PathBuf>,
    owner: Option<Job>,
}
impl Mounts {
    pub fn new() -> Self {
        Self {
            points: Vec::new(),
            owner: None,
        }
    }
    pub fn mount(&mut self, j: &Job, args: &[&str], point: &Path) -> Result<()> {
        self.owner = Some(j.clone());
        let result = j.run(Command::new("/bin/mount").args(args).arg(point), None);
        // Cancellation can arrive just after mount(8) succeeded: still own it.
        let mounted = fs::read_to_string("/proc/self/mountinfo")?
            .lines()
            .any(|line| line.split_whitespace().nth(4) == point.to_str());
        if mounted {
            self.points.push(point.into());
        }
        result?;
        ensure!(mounted, "mount command did not create its mountpoint");
        Ok(())
    }
    pub fn cleanup(&mut self) -> Result<()> {
        while let Some(p) = self.points.last() {
            let result = Command::new("/bin/umount").arg("-R").arg(p).output()?;
            ensure!(
                result.status.success(),
                "unmount {} failed: {}",
                p.display(),
                String::from_utf8_lossy(&result.stderr)
            );
            self.points.pop();
        }
        Ok(())
    }
}
impl Drop for Mounts {
    fn drop(&mut self) {
        if let Err(e) = self.cleanup() {
            eprintln!("cleanup failed: {e:#}");
            if let Some(job) = &self.owner {
                job.engine.fault(format!("Cleanup failed: {e:#}"));
            }
        }
    }
}
pub fn no_pending(root: &Path) -> Result<()> {
    for p in [
        "mobile-offline-rebuild",
        "mobile-offline-deploy",
        "mobile-efi-preparation",
    ] {
        ensure!(
            !inside(root, &format!("/var/lib/{p}/pending"))?.exists(),
            "complete the pending {p} first"
        );
    }
    Ok(())
}
/// A failed rebuild can be retried or rolled back explicitly, while incomplete
/// first installation/deployment still blocks both paths.
pub fn rebuild_pending_gate(c: &Config, root: &Path) -> Result<()> {
    for name in ["mobile-offline-deploy", "mobile-efi-preparation"] {
        ensure!(
            !inside(root, &format!("/var/lib/{name}/pending"))?.exists(),
            "complete pending {name} first"
        );
    }
    let marker = inside(root, "/var/lib/mobile-offline-rebuild/pending")?;
    if marker.exists() {
        system_path(c, fs::read_to_string(marker)?.trim())?;
    }
    Ok(())
}
pub fn store_path(s: &str) -> bool {
    let Some(s) = s.strip_prefix("/nix/store/") else {
        return false;
    };
    let Some((hash, name)) = s.split_once('-') else {
        return false;
    };
    hash.len() == 32
        && hash
            .bytes()
            .all(|b| b"0123456789abcdfghijklmnpqrsvwxyz".contains(&b))
        && !name.is_empty()
        && !name.contains('/')
        && !name.chars().any(char::is_whitespace)
}
pub fn system_path(c: &Config, s: &str) -> Result<()> {
    ensure!(
        store_path(s) && s[44..].starts_with(&format!("nixos-system-{}-", c.hostname)),
        "system does not match configured host"
    );
    Ok(())
}
pub fn selected(c: &Config, root: &Path) -> Result<String> {
    let resolved = inside(root, "/nix/var/nix/profiles/system")?;
    let s = format!(
        "/{}",
        resolved
            .strip_prefix(root)?
            .to_str()
            .context("profile path")?
    );
    system_path(c, &s)?;
    Ok(s)
}
pub fn validate_system(c: &Config, root: &Path, s: &str, layout: &Layout) -> Result<()> {
    system_path(c, s)?;
    if let Some(roles) = &c.roles {
        check_installed_roles(root, s, roles)?;
    }
    ensure!(
        inside(root, &format!("{s}/mobile-efi"))?.is_file(),
        "system does not support EFI"
    );
    ensure!(
        fs::read_to_string(inside(root, &format!("{s}/mobile-device"))?)?.trim() == c.identity,
        "system belongs to another device"
    );
    let fstab = fs::read_to_string(inside(root, &format!("{s}/etc/fstab"))?)?;
    validate_fstab(&fstab, &layout.root.node, &layout.esp.node)
}
/// The installed system must carry the same storage contract as recovery.
pub fn check_installed_roles(root: &Path, s: &str, roles: &Roles) -> Result<()> {
    let installed: Roles = serde_json::from_slice(
        &fs::read(inside(root, &format!("{s}/mobile-storage-roles.json"))?)
            .context("system lacks its storage roles")?,
    )?;
    ensure!(
        installed == *roles,
        "system and recovery storage roles differ"
    );
    Ok(())
}
fn validate_fstab(fstab: &str, root: &Path, esp: &Path) -> Result<()> {
    for (point, kind, device) in [("/", "ext4", root), ("/boot", "vfat", esp)] {
        let matches: Vec<Vec<&str>> = fstab
            .lines()
            .filter(|l| !l.trim_start().starts_with('#'))
            .map(|l| l.split_whitespace().collect::<Vec<_>>())
            .filter(|f| f.len() >= 3 && f[1] == point)
            .collect();
        ensure!(
            matches.len() == 1 && matches[0][2] == kind,
            "invalid {point} fstab entry"
        );
        let raw = matches[0][0];
        let source = if let Some(label) = raw.strip_prefix("LABEL=") {
            Path::new("/dev/disk/by-label").join(label)
        } else if let Some(uuid) = raw.strip_prefix("UUID=") {
            Path::new("/dev/disk/by-uuid").join(uuid)
        } else {
            PathBuf::from(raw)
        };
        ensure!(
            fs::canonicalize(source)? == *device,
            "system changes {point} partition"
        );
    }
    Ok(())
}
pub fn check_efi(root: &Path, s: &str) -> Result<()> {
    ensure!(
        fs::metadata(inside(root, "/boot/EFI/BOOT/BOOTAA64.EFI")?)?.len() > 0,
        "missing EFI fallback loader"
    );
    let mut found = false;
    for entry in fs::read_dir(inside(root, "/boot/loader/entries")?)? {
        let p = entry?.path();
        if p.extension().is_some_and(|s| s == "conf")
            && fs::read_to_string(p)?.contains(&format!("init={s}/init"))
        {
            found = true;
        }
    }
    ensure!(found, "selected generation missing from EFI menu");
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn store_access_repairs_private_umask_without_exposing_private_state() {
        let root = std::env::temp_dir().join(format!("store-access-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("nix/var/nix/db")).unwrap();
        fs::set_permissions(root.join("nix"), fs::Permissions::from_mode(0o700)).unwrap();
        fs::set_permissions(root.join("nix/var/nix"), fs::Permissions::from_mode(0o700)).unwrap();
        fs::set_permissions(
            root.join("nix/var/nix/db"),
            fs::Permissions::from_mode(0o700),
        )
        .unwrap();
        fs::create_dir(root.join("nix/store")).unwrap();
        fs::set_permissions(root.join("nix/store"), fs::Permissions::from_mode(0o1775)).unwrap();
        assert!(check_store_access(&root).is_err());
        prepare_store_access(&root).unwrap();
        prepare_store_access(&root).unwrap();
        check_store_access(&root).unwrap();
        assert_eq!(
            fs::metadata(root.join("nix/store"))
                .unwrap()
                .permissions()
                .mode()
                & 0o7777,
            0o1775
        );
        assert_eq!(
            fs::metadata(root.join("nix/var/nix/db"))
                .unwrap()
                .permissions()
                .mode()
                & 0o7777,
            0o700
        );
        fs::remove_dir(root.join("nix/var/nix/profiles")).unwrap();
        std::os::unix::fs::symlink("/private", root.join("nix/var/nix/profiles")).unwrap();
        assert!(prepare_store_access(&root).is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn boot_hints_reject_conflicting_or_unknown_slots() {
        for (cmd, boot, seen, valid) in [
            ("androidboot.slot_suffix=_b", "", true, true),
            ("", "boot.slot_suffix = \"_b\"", true, true),
            ("", "", false, true),
            ("boot.slot_suffix=_a", "", false, false),
            (
                "boot.slot_suffix=_b",
                "androidboot.slot_suffix = \"_a\"",
                false,
                false,
            ),
            ("boot.slot_suffix=_a boot.slot_suffix=_b", "", false, false),
            ("androidboot.slot_suffix=unknown", "", false, false),
            ("androidboot.vbmeta.device=bad", "", false, false),
            (
                "androidboot.vbmeta.device=PARTUUID=a androidboot.vbmeta.device=PARTUUID=b",
                "",
                false,
                false,
            ),
        ] {
            let result = slot_hints(cmd, boot);
            assert_eq!(result.is_ok(), valid, "{cmd} / {boot}");
            if let Ok((actual, _)) = result {
                assert_eq!(actual, seen);
            }
        }
    }
    #[test]
    fn absolute_target_links_never_escape_to_live_root() {
        let root = std::env::temp_dir().join(format!("recovery-links-{}", std::process::id()));
        fs::create_dir_all(root.join("nix/store")).unwrap();
        std::os::unix::fs::symlink("/nix/store/system", root.join("profile")).unwrap();
        assert_eq!(
            inside(&root, "/profile/etc/fstab").unwrap(),
            root.join("nix/store/system/etc/fstab")
        );
        assert!(inside(&root, "/../../etc").is_err());
        std::os::unix::fs::symlink("/cycle", root.join("cycle")).unwrap();
        assert!(inside(&root, "/cycle").is_err());
        assert!(directory(&root, "profile").is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn store_and_host_validation() {
        let c = Config {
            identity: "aurora".into(),
            compatible: "xiaomi,aurora".into(),
            controller: "ufs".into(),
            hostname: "aurora".into(),
            root_label: "ROOT".into(),
            esp_bytes: 1 << 30,
            minimum_root_bytes: 16 << 30,
            slot_metadata: "qcom-gpt".into(),
            misc_bytes: 4194304,
            recovery_avb: false,
            ..Default::default()
        };
        assert!(system_path(
            &c,
            "/nix/store/00000000000000000000000000000000-nixos-system-aurora-1"
        )
        .is_ok());
        assert!(system_path(
            &c,
            "/nix/store/00000000000000000000000000000000-nixos-system-sheng-1"
        )
        .is_err());
        assert!(!store_path(
            "/nix/store/00000000000000000000000000000000-test/../escape"
        ));
    }
}
#[cfg(test)]
mod fstab_tests {
    use super::*;
    #[test]
    fn verifies_both_filesystems_before_profile_selection() {
        let dir = std::env::temp_dir().join(format!("recovery-fstab-{}", std::process::id()));
        fs::create_dir(&dir).unwrap();
        let root = dir.join("root");
        let esp = dir.join("esp");
        fs::write(&root, b"").unwrap();
        fs::write(&esp, b"").unwrap();
        let fstab = format!(
            "# heading\n{} / ext4 defaults 0 1\n{} /boot vfat umask=0077 0 2\n",
            root.display(),
            esp.display()
        );
        validate_fstab(&fstab, &root, &esp).unwrap();
        assert!(validate_fstab(&fstab.replace("vfat", "ext4"), &root, &esp).is_err());
        assert!(validate_fstab(
            &fstab.replace(&esp.display().to_string(), &root.display().to_string()),
            &root,
            &esp
        )
        .is_err());
        assert!(validate_fstab(
            &format!("{fstab}{} /boot vfat defaults 0 2\n", esp.display()),
            &root,
            &esp
        )
        .is_err());
        assert!(validate_fstab(
            &format!("{} / ext4 defaults 0 1\n", root.display()),
            &root,
            &esp
        )
        .is_err());
        fs::remove_dir_all(dir).unwrap();
    }
}
#[cfg(test)]
mod retry_tests {
    use super::*;
    #[test]
    fn explicit_rebuild_retry_keeps_other_pending_guards() {
        let c = Config {
            identity: "aurora".into(),
            compatible: "xiaomi,aurora".into(),
            controller: "ufs".into(),
            hostname: "aurora".into(),
            root_label: "ROOT".into(),
            esp_bytes: 1 << 30,
            minimum_root_bytes: 16 << 30,
            slot_metadata: "qcom-gpt".into(),
            misc_bytes: 4194304,
            recovery_avb: false,
            ..Default::default()
        };
        let root = std::env::temp_dir().join(format!("recovery-retry-{}", std::process::id()));
        fs::create_dir_all(root.join("var/lib/mobile-offline-rebuild")).unwrap();
        let marker = root.join("var/lib/mobile-offline-rebuild/pending");
        fs::write(
            &marker,
            "/nix/store/00000000000000000000000000000000-nixos-system-aurora-1",
        )
        .unwrap();
        rebuild_pending_gate(&c, &root).unwrap();
        assert!(no_pending(&root).is_err());
        fs::create_dir_all(root.join("var/lib/mobile-efi-preparation")).unwrap();
        fs::write(
            root.join("var/lib/mobile-efi-preparation/pending"),
            b"incomplete",
        )
        .unwrap();
        assert!(rebuild_pending_gate(&c, &root).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
#[cfg(test)]
mod single_tests {
    use super::*;
    use crate::daemon::gpt::{write_test_disk, LINUX};
    use std::os::unix::fs::symlink;
    struct Disk {
        name: &'static str,
        controller: &'static str,
        sector: u64,
        blocks: u64,
        removable: bool,
        parts: Vec<(&'static str, u64, u64, &'static str)>,
    }
    struct Fixture {
        base: PathBuf,
        host: Host,
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.base);
        }
    }
    fn uuid(n: usize) -> String {
        format!("{n:08x}-2222-4333-8444-555555555555")
    }
    fn fixture(tag: &str, disks: &[Disk]) -> Fixture {
        let base =
            std::env::temp_dir().join(format!("recovery-roles-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let (sys, dev) = (base.join("sys"), base.join("dev"));
        fs::create_dir_all(sys.join("class/block")).unwrap();
        fs::create_dir_all(dev.join("disk/by-partlabel")).unwrap();
        for d in disks {
            let disk = sys
                .join("devices/platform/soc")
                .join(d.controller)
                .join("host0")
                .join(d.name);
            fs::create_dir_all(disk.join("queue")).unwrap();
            fs::write(
                disk.join("removable"),
                if d.removable { "1\n" } else { "0\n" },
            )
            .unwrap();
            fs::write(
                disk.join("size"),
                format!("{}\n", d.blocks * d.sector / 512),
            )
            .unwrap();
            fs::write(
                disk.join("queue/logical_block_size"),
                format!("{}\n", d.sector),
            )
            .unwrap();
            fs::write(disk.join("uevent"), format!("DEVNAME={}\n", d.name)).unwrap();
            symlink(&disk, sys.join("class/block").join(d.name)).unwrap();
            let entries: Vec<_> = d
                .parts
                .iter()
                .map(|(name, start, end, id)| (*name, *start, *end, LINUX, *id))
                .collect();
            write_test_disk(&dev.join(d.name), d.sector, d.blocks, &entries);
            for (i, (name, start, end, _)) in d.parts.iter().enumerate() {
                let part = format!("{}{}", d.name, i + 1);
                let p = disk.join(&part);
                fs::create_dir_all(&p).unwrap();
                fs::write(
                    p.join("uevent"),
                    format!("DEVNAME={part}\nPARTNAME={name}\n"),
                )
                .unwrap();
                fs::write(p.join("partition"), format!("{}\n", i + 1)).unwrap();
                fs::write(p.join("start"), format!("{}\n", start * d.sector / 512)).unwrap();
                fs::write(
                    p.join("size"),
                    format!("{}\n", (end - start + 1) * d.sector / 512),
                )
                .unwrap();
                symlink(&p, sys.join("class/block").join(&part)).unwrap();
                fs::write(dev.join(&part), b"").unwrap();
                if !d.removable {
                    symlink(
                        format!("../../{part}"),
                        dev.join("disk/by-partlabel").join(name),
                    )
                    .unwrap();
                }
            }
        }
        Fixture {
            base,
            host: Host {
                sys,
                dev,
                block_devices: false,
            },
        }
    }
    fn role(label: &str) -> Role {
        Role {
            label: label.into(),
            ..Default::default()
        }
    }
    fn polaris(tag: &str) -> Fixture {
        // UFS LUNs: root and ESP on different disks, 4 KiB sectors.
        let u1 = Box::leak(uuid(1).into_boxed_str());
        let u2 = Box::leak(uuid(2).into_boxed_str());
        let u3 = Box::leak(uuid(3).into_boxed_str());
        let u4 = Box::leak(uuid(4).into_boxed_str());
        fixture(
            tag,
            &[
                Disk {
                    name: "sda",
                    controller: "1d84000.ufshc",
                    sector: 4096,
                    blocks: 1 << 16,
                    removable: false,
                    parts: vec![("userdata", 1024, 60000, u1)],
                },
                Disk {
                    name: "sde",
                    controller: "1d84000.ufshc",
                    sector: 4096,
                    blocks: 1 << 16,
                    removable: false,
                    parts: vec![
                        ("system", 256, 20000, u2),
                        ("boot", 20480, 36863, u3),
                        ("misc", 40000, 41023, u4),
                    ],
                },
            ],
        )
    }
    #[test]
    fn gpt_name_mode_resolves_roles_across_luns() {
        let f = polaris("luns");
        let root = resolve_role(&f.host, "1d84000.ufshc", "root", &role("userdata")).unwrap();
        let esp = resolve_role(&f.host, "1d84000.ufshc", "esp", &role("system")).unwrap();
        assert_ne!(root.disk, esp.disk);
        assert_eq!(root.node, f.host.dev.join("sda1"));
        assert_eq!(esp.node, f.host.dev.join("sde1"));
        assert_eq!(esp.entry.bytes(), (20000 - 256 + 1) * 4096);
        let misc = resolve_role(&f.host, "1d84000.ufshc", "misc", &role("misc")).unwrap();
        assert_eq!(misc.entry.bytes(), 4 << 20);
        // Missing names, another controller and an absent label fail closed.
        assert!(resolve_role(&f.host, "1d84000.ufshc", "x", &role("recovery")).is_err());
        assert!(resolve_role(&f.host, "c0c4000.sdhci", "root", &role("userdata")).is_err());
        assert!(resolve_role(&f.host, "1d84000.ufshc", "x", &role("a/b")).is_err());
    }
    #[test]
    fn measured_roles_must_match_every_field() {
        let f = polaris("measured");
        let measured = Role {
            label: "boot".into(),
            partuuid: Some(uuid(3).to_uppercase()),
            number: Some(2),
            offset: Some(20480 * 8),
            bytes: Some(16384 * 4096),
            require_measured: true,
            ..Default::default()
        };
        resolve_role(&f.host, "1d84000.ufshc", "firmware", &measured).unwrap();
        for wrong in [
            Role {
                partuuid: Some(uuid(9)),
                ..measured.clone()
            },
            Role {
                number: Some(3),
                ..measured.clone()
            },
            Role {
                offset: Some(20480),
                ..measured.clone()
            },
            Role {
                bytes: Some(4096),
                ..measured.clone()
            },
            Role {
                min_bytes: Some(1 << 40),
                ..measured.clone()
            },
            Role {
                max_bytes: Some(4096),
                ..measured.clone()
            },
            // A required measurement cannot be skipped.
            Role {
                partuuid: None,
                ..measured.clone()
            },
            Role {
                bytes: None,
                ..measured.clone()
            },
        ] {
            assert!(
                resolve_role(&f.host, "1d84000.ufshc", "firmware", &wrong).is_err(),
                "{wrong:?}"
            );
        }
    }
    #[test]
    fn kernel_geometry_and_label_links_are_cross_checked() {
        let f = polaris("geometry");
        let p = f.host.sys.join("class/block/sde2");
        fs::write(fs::canonicalize(&p).unwrap().join("start"), "1\n").unwrap();
        assert!(resolve_role(&f.host, "1d84000.ufshc", "firmware", &role("boot")).is_err());
        let link = f.host.dev.join("disk/by-partlabel/system");
        fs::remove_file(&link).unwrap();
        symlink("../../sde2", &link).unwrap();
        assert!(resolve_role(&f.host, "1d84000.ufshc", "esp", &role("system")).is_err());
    }
    #[test]
    fn emmc_512_byte_sectors_and_removable_duplicates() {
        let u1 = Box::leak(uuid(11).into_boxed_str());
        let u2 = Box::leak(uuid(12).into_boxed_str());
        let u3 = Box::leak(uuid(13).into_boxed_str());
        let mut disks = vec![Disk {
            name: "mmcblk0p",
            controller: "c0c4000.sdhci",
            sector: 512,
            blocks: 1 << 20,
            removable: false,
            parts: vec![
                ("system", 2048, 2048 + 65535, u1),
                ("userdata", 131072, 1000000, u2),
            ],
        }];
        let f = fixture("clover", &disks);
        // Clover's ESP: the unique "system" on the boot disk, within a size range.
        let esp = Role {
            min_bytes: Some(16 << 20),
            max_bytes: Some(64 << 20),
            ..role("system")
        };
        let d = resolve_role(&f.host, "c0c4000.sdhci", "esp", &esp).unwrap();
        assert_eq!((d.entry.sector, d.entry.bytes()), (512, 65536 * 512));
        let small = Role {
            min_bytes: Some(1 << 30),
            ..esp.clone()
        };
        assert!(resolve_role(&f.host, "c0c4000.sdhci", "esp", &small).is_err());
        drop(f);
        // A second "system" on a removable card makes the name ambiguous.
        disks.push(Disk {
            name: "mmcblk1p",
            controller: "c084000.sdhci",
            sector: 512,
            blocks: 1 << 16,
            removable: true,
            parts: vec![("system", 2048, 4095, u3)],
        });
        let f = fixture("clover-card", &disks);
        assert!(resolve_role(&f.host, "c0c4000.sdhci", "esp", &esp).is_err());
        drop(f);
        // A role found only on a removable disk is refused.
        disks.remove(0);
        disks[0].controller = "c0c4000.sdhci";
        let f = fixture("clover-removable", &disks);
        assert!(resolve_role(&f.host, "c0c4000.sdhci", "esp", &role("system")).is_err());
    }
    #[test]
    fn deployment_requirements_and_installed_roles() {
        let root = std::env::temp_dir().join(format!("recovery-req-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("var/lib/id")).unwrap();
        fs::create_dir_all(root.join("var/lib/snap")).unwrap();
        fs::write(root.join("var/lib/id/wifi"), "02:00:00:00:00:01\n").unwrap();
        fs::write(root.join("var/lib/snap/a"), b"data").unwrap();
        use sha2::{Digest, Sha256};
        let digest = format!("{:x}", Sha256::digest(b"data"));
        fs::write(
            root.join("var/lib/snap/SHA256SUMS"),
            format!("{digest}  a\n"),
        )
        .unwrap();
        let req = Requirements {
            mac_files: vec!["/var/lib/id/wifi".into()],
            checksum_dirs: vec!["/var/lib/snap".into()],
        };
        check_requirements(&root, &req).unwrap();
        fs::write(root.join("var/lib/snap/a"), b"changed").unwrap();
        assert!(check_requirements(&root, &req).is_err());
        fs::write(root.join("var/lib/snap/a"), b"data").unwrap();
        fs::write(root.join("var/lib/id/wifi"), "not-a-mac\n").unwrap();
        assert!(check_requirements(&root, &req).is_err());
        fs::write(root.join("var/lib/id/wifi"), "02:00:00:00:00:01\n").unwrap();
        fs::write(
            root.join("var/lib/snap/SHA256SUMS"),
            format!("{digest}  ../id/wifi\n"),
        )
        .unwrap();
        assert!(check_requirements(&root, &req).is_err());
        // Installed and recovery storage contracts must be identical.
        let roles = Roles {
            root: role("userdata"),
            esp: Role {
                fs_label: Some("NIXOS_BOOT".into()),
                ..role("system")
            },
            ..Default::default()
        };
        let s = "/nix/store/00000000000000000000000000000000-nixos-system-polaris-1";
        let dir = root.join(s.trim_start_matches('/'));
        fs::create_dir_all(&dir).unwrap();
        assert!(check_installed_roles(&root, s, &roles).is_err());
        fs::write(
            dir.join("mobile-storage-roles.json"),
            serde_json::to_vec(&roles).unwrap(),
        )
        .unwrap();
        check_installed_roles(&root, s, &roles).unwrap();
        let other = Roles {
            root: role("linux"),
            ..roles.clone()
        };
        assert!(check_installed_roles(&root, s, &other).is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn ufs_safe_mode_writes_and_verifies_controls() {
        let c = std::env::temp_dir().join(format!("recovery-ufs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&c);
        fs::create_dir_all(c.join("power")).unwrap();
        for f in ["power/control", "clkgate_enable", "clkscale_enable"] {
            fs::write(c.join(f), "auto").unwrap();
        }
        ufs_safe_mode(&c).unwrap();
        assert_eq!(fs::read_to_string(c.join("power/control")).unwrap(), "on");
        assert_eq!(fs::read_to_string(c.join("clkgate_enable")).unwrap(), "0");
        // An unwritable control fails closed.
        fs::remove_file(c.join("clkscale_enable")).unwrap();
        fs::create_dir(c.join("clkscale_enable")).unwrap();
        assert!(ufs_safe_mode(&c).is_err());
        fs::remove_dir_all(c).unwrap();
    }
    #[test]
    fn slot_models_keep_their_own_invariants() {
        let ab = Config {
            identity: "aurora".into(),
            compatible: "xiaomi,aurora".into(),
            firmware_compatible: "xiaomi,aurora".into(),
            controller: "1d84000.ufshc".into(),
            slot_model: "ab".into(),
            slot_metadata: "qcom-gpt".into(),
            boot_request: "argument".into(),
            recovery_reboot_argument: Some("recovery".into()),
            misc_bytes: 4194304,
            ..Default::default()
        };
        ab.check().unwrap();
        assert!(Config {
            roles: Some(Roles::default()),
            ..ab.clone()
        }
        .check()
        .is_err());
        assert!(Config {
            slot_metadata: "none".into(),
            ..ab.clone()
        }
        .check()
        .is_err());
        assert!(Config {
            slot_model: "abc".into(),
            ..ab.clone()
        }
        .check()
        .is_err());
        let single = Config {
            slot_model: "single".into(),
            slot_metadata: "none".into(),
            boot_request: "bcb".into(),
            recovery_reboot_argument: None,
            roles: Some(Roles::default()),
            ..ab.clone()
        };
        single.check().unwrap();
        assert!(Config {
            roles: None,
            ..single.clone()
        }
        .check()
        .is_err());
        assert!(Config {
            slot_metadata: "qcom-gpt".into(),
            ..single.clone()
        }
        .check()
        .is_err());
        assert!(Config {
            boot_request: "pon".into(),
            ..single.clone()
        }
        .check()
        .is_err());
        assert!(Config {
            recovery_avb: true,
            ..single
        }
        .check()
        .is_err());
    }
}
