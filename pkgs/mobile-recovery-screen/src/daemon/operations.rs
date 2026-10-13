//! Recovery operations use Rust orchestration and upstream filesystem/Nix tools.
use super::{engine::Job, storage::*};
use anyhow::{bail, ensure, Context, Result};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::Read,
    os::unix::{
        fs::{FileExt, PermissionsExt},
        net::UnixStream,
    },
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
};
const ROOT: &str = "/recovery";
const MOUNT: &str = "/mnt";
const ACTIONS: &[&str] = &[
    "prepare-install",
    "prepare-boot",
    "safe-ufs",
    "format-root",
    "install-initial",
    "deploy-query",
    "deploy-offline",
    "deploy-check-boot",
    "mount-target",
    "unmount-target",
    "target-status",
    "rebuild",
    "generations",
    "select-generation",
    "update-firmware",
    "update-recovery",
    "clear-boot-request",
    "repair-backup-gpt",
    "repair-filesystems",
    "reboot-system",
    "reboot-recovery",
    "reboot-bootloader",
    "poweroff",
];
pub fn capabilities() -> Vec<String> {
    ACTIONS.iter().map(|s| s.to_string()).collect()
}
pub fn validate(a: &[String], input: bool) -> Result<()> {
    ensure!(
        !a.is_empty() && ACTIONS.contains(&a[0].as_str()),
        "unsupported operation; query capabilities"
    );
    ensure!(
        a.len() <= 128 && a.iter().all(|v| v.len() <= 4096 && !v.contains('\0')),
        "invalid arguments"
    );
    let action = a[0].as_str();
    let argc = a.len();
    match action {
        "prepare-install" => ensure!(
            argc == 2 && ["--check", "--confirm-erase-userdata"].contains(&a[1].as_str()),
            "use prepare-install --check|--confirm-erase-userdata"
        ),
        "format-root" | "prepare-boot" | "clear-boot-request" | "repair-backup-gpt"
        | "repair-filesystems" => ensure!(
            argc == 2 && ["--check", "--confirm"].contains(&a[1].as_str()),
            "use format-root|prepare-boot|clear-boot-request|repair-backup-gpt|repair-filesystems --check|--confirm"
        ),
        "install-initial" => ensure!(
            argc == 6 && ["--check", "--confirm", "--resume-check", "--resume-confirm"].contains(&a[5].as_str()),
            "use install-initial MANIFEST REGISTRATION SYSTEM MIN_BYTES --check|--confirm|--resume-check|--resume-confirm"
        ),
        "deploy-query" => ensure!(argc == 3, "use deploy-query MANIFEST SYSTEM"),
        "deploy-offline" => ensure!(
            argc == 5 && a[4] == "--confirm",
            "use deploy-offline MANIFEST SYSTEM MISSING_COUNT --confirm"
        ),
        "mount-target" => ensure!(
            argc == 1 || (argc == 2 && ["--ro", "--rw"].contains(&a[1].as_str())),
            "use mount-target --ro|--rw"
        ),
        "rebuild" => {
            ensure!(
                argc >= 2 && a[1] == "boot",
                "offline rebuild supports boot only"
            );
            for arg in &a[2..] {
                let flag = arg.split('=').next().unwrap();
                ensure!(
                    ![
                        "--target-host",
                        "--build-host",
                        "--profile-name",
                        "-p",
                        "--sudo",
                        "--use-remote-sudo",
                        "--install-bootloader",
                        "--no-reexec",
                        "--specialisation",
                        "--rollback"
                    ]
                    .contains(&flag),
                    "unsupported offline rebuild flag: {flag}; use select-generation for rollback"
                );
            }
        }
        "select-generation" => ensure!(
            argc == 3 && a[1].parse::<u64>().is_ok_and(|n| n > 0) && a[2] == "--confirm",
            "use select-generation NUMBER --confirm"
        ),
        "update-firmware" | "update-recovery" => ensure!(
            argc == 3 && ["--check", "--confirm"].contains(&a[2].as_str()),
            "use update-firmware|update-recovery IMAGE --check|--confirm"
        ),
        "reboot-system" | "reboot-recovery" | "reboot-bootloader" | "poweroff" => ensure!(
            argc == 2 && a[1] == "--confirm",
            "explicit --confirm required"
        ),
        _ => ensure!(argc == 1, "unexpected arguments"),
    }
    let wants_input =
        (action == "install-initial" && a[5] == "--confirm") || action == "deploy-offline";
    ensure!(
        wants_input == input,
        "input channel does not match operation"
    );
    Ok(())
}
pub fn execute(j: &Job, a: &[String], input: Option<mpsc::Receiver<UnixStream>>) -> Result<String> {
    j.engine.config.identity()?;
    match a[0].as_str() {
        "prepare-install" => prepare(j, a[1] == "--check"),
        "prepare-boot" => prepare_boot(j, a[1] == "--check"),
        "safe-ufs" => safe_ufs(j),
        "format-root" => format(j, a[1] == "--check"),
        "repair-backup-gpt" => repair_backup_gpt(j, a[1] == "--check"),
        "repair-filesystems" => repair_filesystems(j, a[1] == "--check"),
        "install-initial" => initial(j, a, input),
        "deploy-offline" => deploy(j, a, input.unwrap()),
        "deploy-query" => query(j, a),
        "deploy-check-boot" => check_boot(j),
        "mount-target" => mount_target(j, a.get(1).is_some_and(|s| s == "--rw")),
        "unmount-target" => unmount_target(j),
        "target-status" => target_status(j),
        "rebuild" => rebuild(j, &a[1..]),
        "generations" => generations(j),
        "select-generation" => select_generation(j, &a[1]),
        "update-firmware" | "update-recovery" => update_image(j, a),
        "clear-boot-request" => {
            config(j).ram_gate(j)?;
            clear_bcb(j, a[1] == "--check")
        }
        "reboot-system" | "reboot-recovery" | "reboot-bootloader" | "poweroff" => reboot(j, &a[0]),
        _ => bail!("unsupported operation"),
    }
}
fn tool(j: &Job, name: &str, args: &[&str]) -> Result<String> {
    j.run(Command::new(format!("/bin/{name}")).args(args), None)
}
fn config(j: &Job) -> &Config {
    &j.engine.config
}
fn ab_only(j: &Job, what: &str) -> Result<()> {
    ensure!(
        !config(j).single(),
        "{what} is only available on A/B devices"
    );
    Ok(())
}
fn safe_ufs(j: &Job) -> Result<String> {
    let c = config(j);
    let controller = c
        .ufs_safe_mode
        .as_ref()
        .context("this device has no UFS safe mode")?;
    c.identity()?;
    ufs_safe_mode(Path::new(controller))?;
    Ok("UFS clock gating and scaling disabled".into())
}
fn repair_backup_gpt(j: &Job, check: bool) -> Result<String> {
    ab_only(j, "repair-backup-gpt")?;
    config(j).ram_gate(j)?;
    let target = config(j).partition_for_backup_repair(j, "linux")?;
    target
        .gpt
        .check_linux_layout(config(j).esp_bytes, config(j).minimum_root_bytes)?;
    if !target.gpt.backup_needs_repair() {
        return Ok("Both GPT copies agree; no repair needed".into());
    }
    let plan = format!("Repair backup GPT on {} from its CRC-verified primary; only stale A/B metadata/backup CRC may differ. Preserve primary GPT, layout, payloads and OEM padding.", target.disk.display());
    if check {
        return Ok(plan);
    }
    config(j).ram_gate(j)?;
    j.phase("Repairing backup GPT; do not reboot", false)?;
    let disk = exclusive(&target.disk)?;
    let evidence = PathBuf::from(format!("/run/mobile-recovery/gpt-repair-{}", j.id));
    target.gpt.snapshot(&evidence)?;
    target.gpt.repair_backup(&disk)?;
    Ok(format!(
        "{plan}\nReadback verified; metadata snapshot: {}",
        evidence.display()
    ))
}
fn prepare(j: &Job, check: bool) -> Result<String> {
    ab_only(j, "prepare-install; use format-root and prepare-boot")?;
    config(j).ram_gate(j)?;
    let user = config(j).partition(j, "userdata")?;
    let parts = user
        .gpt
        .split(config(j).esp_bytes, config(j).minimum_root_bytes)?;
    let plan = serde_json::to_string_pretty(&parts)?;
    if check {
        return Ok(format!("{plan}\nDestroys Android userdata; preserves A, DTBO, super and metadata. Android requires a separate factory reset."));
    }
    config(j).ram_gate(j)?;
    j.phase("Writing GPT; do not reboot", false)?;
    let disk = exclusive(&user.disk)?;
    let evidence = PathBuf::from(format!("/run/mobile-recovery/gpt-{}", j.id));
    user.gpt.snapshot(&evidence)?;
    user.gpt.write_split(&disk, &parts)?;
    reread(&disk)?;
    drop(disk);
    tool(j, "udevadm", &["settle"])?;
    let layout = config(j).layout(j, false)?;
    let user = config(j).partition(j, "userdata")?;
    j.phase("Invalidating Android userdata and formatting Linux", false)?;
    let f = exclusive(&user.node)?;
    let zeros = vec![0; 8 << 20];
    f.write_all_at(&zeros, 0)?;
    f.write_all_at(&zeros, user.entry.bytes() - zeros.len() as u64)?;
    f.sync_all()?;
    drop(f);
    tool(
        j,
        "mke2fs",
        &[
            "-F",
            "-t",
            "ext4",
            "-m",
            "0",
            "-L",
            &config(j).root_label,
            layout.root.node.to_str().unwrap(),
        ],
    )?;
    tool(
        j,
        "mkfs.fat",
        &[
            "-F",
            "32",
            "-n",
            "LINUXBOOT",
            layout.esp.node.to_str().unwrap(),
        ],
    )?;
    sync();
    config(j).layout(j, true)?;
    fsck(j, &layout)?;
    Ok(format!("Prepared ext4 root and FAT ESP; Android userdata erased. GPT evidence: {}. Install explicitly before Linux boot.",evidence.display()))
}
fn format(j: &Job, check: bool) -> Result<String> {
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, false)?;
    if check {
        return Ok(format!(
            "Erase only {}: {} bytes",
            l.root.node.display(),
            l.root.entry.bytes()
        ));
    }
    j.phase("Formatting Linux root", false)?;
    let uuid = config(j)
        .roles
        .as_ref()
        .and_then(|r| r.root.fs_uuid.clone());
    let mut args = vec!["-F", "-t", "ext4", "-m", "0", "-L", &config(j).root_label];
    if let Some(uuid) = &uuid {
        args.extend(["-U", uuid.as_str()]);
    }
    args.push(l.root.node.to_str().unwrap());
    tool(j, "mke2fs", &args)?;
    sync();
    ensure!(
        probe(j, &l.root.node, "TYPE")? == "ext4"
            && probe(j, &l.root.node, "LABEL")? == config(j).root_label,
        "formatted root mismatch"
    );
    tool(j, "e2fsck", &["-fn", l.root.node.to_str().unwrap()])?;
    Ok("Linux root formatted and verified".into())
}
fn valid_fat_identity(label: &str, volume: Option<&str>) -> Result<()> {
    ensure!(
        !label.is_empty()
            && label.len() <= 11
            && label
                .bytes()
                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_'),
        "invalid FAT label"
    );
    if let Some(v) = volume {
        ensure!(
            v.len() == 9
                && v.as_bytes()[4] == b'-'
                && v.bytes()
                    .enumerate()
                    .all(|(i, b)| i == 4 || b.is_ascii_hexdigit()),
            "invalid FAT volume ID"
        );
    }
    Ok(())
}
/// Single-slot boot preparation: format the physical FAT boot partition only
/// after the root is a verified empty or self-consistent installation.
fn prepare_boot(j: &Job, check: bool) -> Result<String> {
    ensure!(
        config(j).single(),
        "prepare-boot is for single-slot devices; A/B devices use prepare-install"
    );
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, false)?;
    let roles = config(j).roles.as_ref().context("missing roles")?;
    // An explicit ESP label is also verified later; otherwise use the default.
    let label = roles.esp.fs_label.as_deref().unwrap_or("NIXOS_BOOT");
    let volume = roles.esp.fs_uuid.as_deref();
    valid_fat_identity(label, volume)?;
    ensure!(
        probe(j, &l.root.node, "TYPE")? == "ext4"
            && probe(j, &l.root.node, "LABEL")? == config(j).root_label,
        "format-root first"
    );
    tool(j, "e2fsck", &["-fn", l.root.node.to_str().unwrap()])?;
    let root = Path::new(ROOT);
    let mut m = Mounts::new();
    mount_root(j, &l, root, false, &mut m)?;
    ensure!(
        !inside(root, "/var/lib/mobile-offline-deploy/pending")?.exists(),
        "finish the pending deployment first"
    );
    if fs::symlink_metadata(inside(root, "/nix/var/nix/profiles")?.join("system")).is_ok() {
        let s = selected(config(j), root)?;
        j.phase("Verifying the installed store", true)?;
        readonly_nix(
            j,
            root,
            &s,
            "nix",
            &[
                "--extra-experimental-features",
                "nix-command",
                "store",
                "verify",
                "--all",
                "--no-trust",
            ],
            std::iter::empty(),
        )?;
    } else {
        empty_root(root)?;
    }
    m.cleanup()?;
    if probe(j, &l.esp.node, "TYPE")? == "vfat" {
        tool(j, "fsck.fat", &["-n", l.esp.node.to_str().unwrap()])?;
        return Ok("Matching FAT boot filesystem already prepared; no formatting performed".into());
    }
    let plan = format!(
        "Format FAT32 {label} on {} ({} bytes, GPT {}); GPT geometry stays unchanged",
        l.esp.node.display(),
        l.esp.entry.bytes(),
        l.esp.entry.uuid
    );
    if check {
        return Ok(format!(
            "{plan}\nCheck only; no filesystem or partition writes"
        ));
    }
    config(j).ram_gate(j)?;
    let next = config(j).layout(j, false)?;
    ensure!(
        identity(&l.root) == identity(&next.root) && identity(&l.esp) == identity(&next.esp),
        "target identity changed"
    );
    j.phase("Formatting FAT boot partition", false)?;
    mount_root(j, &l, root, true, &mut m)?;
    pending(
        root,
        "mobile-efi-preparation",
        "Install and verify EFI boot files before rebooting.\n",
    )?;
    m.cleanup()?;
    let id = volume.map(|v| v.replace('-', ""));
    let mut args = vec!["-F", "32", "-n", label];
    if let Some(id) = &id {
        args.extend(["-i", id.as_str()]);
    }
    args.push(l.esp.node.to_str().unwrap());
    tool(j, "mkfs.fat", &args)?;
    sync();
    tool(j, "fsck.fat", &["-n", l.esp.node.to_str().unwrap()])?;
    ensure!(
        probe(j, &l.esp.node, "TYPE")? == "vfat" && probe(j, &l.esp.node, "LABEL")? == label,
        "formatted FAT identity mismatch"
    );
    Ok(format!(
        "{plan}; done. Install the EFI system and firmware before rebooting."
    ))
}
fn repair_filesystems(j: &Job, check: bool) -> Result<String> {
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    if check {
        fsck(j, &l)?;
        return Ok("Root and ESP filesystem checks passed; no writes".into());
    }
    j.phase(
        "Repairing unmounted Linux filesystems; do not reboot",
        false,
    )?;
    // Verify availability, then release our claims: e2fsck acquires its own
    // exclusive claim and correctly refuses a block device held by the daemon.
    // The daemon serializes operations; SSH identity preparation finishes and
    // releases its private mount namespace before this service starts.
    drop(exclusive(&l.root.node)?);
    drop(exclusive(&l.esp.node)?);
    for (tool, flag, node) in [
        ("e2fsck", "-p", &l.root.node),
        ("fsck.fat", "-a", &l.esp.node),
    ] {
        let output = j.run_codes(
            Command::new(format!("/bin/{tool}")).arg(flag).arg(node),
            None,
            &[0, 1],
        )?;
        j.log(&output);
    }
    sync();
    fsck(j, &l)?;
    Ok("Linux ext4 root and FAT ESP repaired and independently rechecked; Android userdata untouched".into())
}
fn fsck(j: &Job, l: &Layout) -> Result<()> {
    tool(j, "e2fsck", &["-fn", l.root.node.to_str().unwrap()])?;
    tool(j, "fsck.fat", &["-n", l.esp.node.to_str().unwrap()])?;
    Ok(())
}
fn mount_root(j: &Job, l: &Layout, root: &Path, rw: bool, m: &mut Mounts) -> Result<()> {
    ensure!(
        !fs::symlink_metadata(root).is_ok_and(|m| m.file_type().is_symlink()),
        "unsafe mountpoint"
    );
    fs::create_dir_all(root)?;
    m.mount(
        j,
        &[
            "-t",
            "ext4",
            "-o",
            if rw { "rw" } else { "ro,noload" },
            l.root.node.to_str().unwrap(),
        ],
        root,
    )
}
fn mount_esp(j: &Job, l: &Layout, root: &Path, rw: bool, m: &mut Mounts) -> Result<()> {
    let p = directory(root, "boot")?;
    m.mount(
        j,
        &[
            "-t",
            "vfat",
            "-o",
            if rw { "rw,umask=0077" } else { "ro,umask=0077" },
            l.esp.node.to_str().unwrap(),
        ],
        &p,
    )
}
fn runtime(j: &Job, root: &Path, system: &str, m: &mut Mounts) -> Result<()> {
    for n in ["dev", "proc", "sys"] {
        let p = directory(root, n)?;
        m.mount(j, &["--rbind", &format!("/{n}")], &p)?;
        j.run(
            Command::new("/bin/mount").arg("--make-rslave").arg(&p),
            None,
        )?;
    }
    let p = directory(root, "run")?;
    m.mount(j, &["-t", "tmpfs", "-o", "mode=0755", "tmpfs"], &p)?;
    std::os::unix::fs::symlink(system, p.join("current-system"))?;
    Ok(())
}
fn chroot(root: &Path, program: &str, args: &[&str]) -> Command {
    let mut cmd = Command::new("/bin/chroot");
    cmd.arg(root)
        .arg(program)
        .args(args)
        .env("NIX_REMOTE", "local")
        .env("NIXOS_INSTALL_BOOTLOADER", "1")
        .env("NIXOS_REBUILD_NO_SYSTEMD_RUN", "1")
        .env("NIXOS_SWITCH_USE_DIRTY_ENV", "1")
        .env("HOME", "/root")
        .env("TMPDIR", "/tmp")
        .env("PATH", "/run/current-system/sw/bin")
        .env_remove("NIX_DAEMON_SOCKET_PATH");
    cmd
}
fn nix(j: &Job, root: &Path, s: &str, program: &str, args: &[&str]) -> Result<String> {
    j.run(
        &mut chroot(root, &format!("{s}/sw/bin/{program}"), args),
        None,
    )
}
fn manifest(c: &Config, file: &str, system: &str) -> Result<BTreeMap<String, String>> {
    system_path(c, system)?;
    let meta = fs::symlink_metadata(file)?;
    ensure!(
        meta.is_file() && meta.len() > 0 && meta.len() <= 16 << 20,
        "invalid manifest file"
    );
    let mut entries = BTreeMap::new();
    for line in fs::read_to_string(file)?.lines() {
        let f: Vec<_> = line.split_whitespace().collect();
        ensure!(f.len() == 2 && store_path(f[1]), "malformed manifest");
        let hash = f[0].strip_prefix("sha256:").context("invalid NAR hash")?;
        ensure!(
            hash.len() == 52
                && hash
                    .bytes()
                    .all(|b| b"0123456789abcdfghijklmnpqrsvwxyz".contains(&b)),
            "invalid NAR hash"
        );
        ensure!(
            entries.insert(f[1].into(), f[0].into()).is_none(),
            "duplicate manifest entry"
        );
    }
    ensure!(entries.contains_key(system), "system absent from manifest");
    Ok(entries)
}
fn verify_closure(
    j: &Job,
    root: &Path,
    trusted: &str,
    s: &str,
    entries: &BTreeMap<String, String>,
) -> Result<()> {
    j.phase("Verifying closure and NAR contents", true)?;
    let actual = nix(
        j,
        root,
        trusted,
        "nix-store",
        &["--query", "--requisites", s],
    )?;
    let mut paths: Vec<_> = actual.lines().collect();
    paths.sort_unstable();
    ensure!(
        paths == entries.keys().map(String::as_str).collect::<Vec<_>>(),
        "closure differs from manifest"
    );
    for (i, (path, expected)) in entries.iter().enumerate() {
        nix(j, root, trusted, "nix-store", &["--check-validity", path])?;
        let hash = nix(
            j,
            root,
            trusted,
            "nix",
            &[
                "--extra-experimental-features",
                "nix-command",
                "hash",
                "path",
                "--type",
                "sha256",
                "--base32",
                path,
            ],
        )?;
        ensure!(
            &format!("sha256:{}", hash.trim()) == expected,
            "NAR content mismatch: {path}"
        );
        j.progress(i as u64 + 1, Some(entries.len() as u64));
    }
    Ok(())
}
fn empty_root(root: &Path) -> Result<()> {
    fn walk(root: &Path, p: &Path) -> Result<()> {
        for e in fs::read_dir(p)? {
            let e = e?;
            let rel = e
                .path()
                .strip_prefix(root)?
                .to_str()
                .context("root name")?
                .to_owned();
            if rel == "lost+found" {
                ensure!(
                    e.file_type()?.is_dir() && fs::read_dir(e.path())?.next().is_none(),
                    "lost+found contains files"
                );
                continue;
            }
            if [
                "boot",
                "var",
                "var/lib",
                "var/lib/mobile-efi-preparation",
                "var/lib/mobile-recovery",
                "var/lib/mobile-recovery/ssh",
            ]
            .contains(&rel.as_str())
            {
                ensure!(e.file_type()?.is_dir(), "unsafe root directory");
                walk(root, &e.path())?;
            } else {
                ensure!(
                    [
                        "var/lib/mobile-efi-preparation/pending",
                        "var/lib/mobile-recovery/ssh/ssh_host_ed25519_key",
                        "var/lib/mobile-recovery/ssh/ssh_host_ed25519_key.pub",
                    ]
                    .contains(&rel.as_str())
                        && e.file_type()?.is_file(),
                    "root not empty: {rel}"
                );
            }
        }
        Ok(())
    }
    walk(root, root)
}
fn pending(root: &Path, name: &str, text: &str) -> Result<PathBuf> {
    let p = directory(root, &format!("var/lib/{name}"))?.join("pending");
    ensure!(
        !fs::symlink_metadata(&p).is_ok_and(|m| !m.is_file()),
        "unsafe pending marker"
    );
    fs::write(&p, text)?;
    File::open(&p)?.sync_all()?;
    sync();
    Ok(p)
}
fn hash_file(path: &Path) -> Result<String> {
    let mut f = File::open(path)?;
    let mut hash = Sha256::new();
    let mut b = [0; 65536];
    loop {
        let n = f.read(&mut b)?;
        if n == 0 {
            break;
        }
        hash.update(&b[..n]);
    }
    Ok(format!("{:x}", hash.finalize()))
}
fn identity(d: &Device) -> String {
    format!(
        "{}:{}:{}:{}",
        d.node.display(),
        d.entry.uuid,
        d.entry.start,
        d.entry.bytes()
    )
}
/// Resume only the EFI/finalization stage of the same explicitly selected system.
/// Earlier failures without a registered profile still require a fresh target.
fn resume_initial(root: &Path, system: &str) -> Result<()> {
    let marker = "/var/lib/mobile-efi-preparation/pending";
    let path = root.join(marker.trim_start_matches('/'));
    ensure!(
        inside(root, marker)? == path && fs::symlink_metadata(&path)?.is_file(),
        "unsafe initial-install marker"
    );
    ensure!(
        fs::read_to_string(path)? == "First installation incomplete\n",
        "unknown initial-install marker"
    );
    for name in ["mobile-offline-rebuild", "mobile-offline-deploy"] {
        ensure!(
            !inside(root, &format!("/var/lib/{name}/pending"))?.exists(),
            "another operation is pending"
        );
    }
    let selected = inside(root, "/nix/var/nix/profiles/system")?;
    ensure!(
        selected == inside(root, system)? && selected.is_dir(),
        "resume requires the same registered system profile"
    );
    Ok(())
}
fn initial(j: &Job, a: &[String], input: Option<mpsc::Receiver<UnixStream>>) -> Result<String> {
    let root = Path::new(ROOT);
    let s = &a[3];
    let entries = manifest(config(j), &a[1], s)?;
    let resume = ["--resume-check", "--resume-confirm"].contains(&a[5].as_str());
    let registration = fs::symlink_metadata(&a[2])?;
    ensure!(
        registration.is_file() && registration.len() > 0 && registration.len() < 64 << 20,
        "invalid Nix registration"
    );
    let registration = fs::read(&a[2])?;
    let bytes: u64 = a[4].parse()?;
    ensure!(bytes > 0 && bytes <= 1 << 40, "invalid closure size");
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    let boot = config(j).named(j, "firmware")?;
    let before = identity(&boot);
    let boot_hash = hash_file(&boot.node)?;
    fsck(j, &l)?;
    let mut m = Mounts::new();
    mount_root(j, &l, root, false, &mut m)?;
    if resume {
        resume_initial(root, s)?;
    } else {
        empty_root(root)?;
    }
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let c = std::ffi::CString::new(ROOT)?;
    ensure!(
        unsafe { libc::statvfs(c.as_ptr(), &mut stat) } == 0,
        "cannot measure free space"
    );
    ensure!(
        stat.f_bavail as u64 * stat.f_frsize as u64 > bytes + (1 << 30),
        "closure needs an additional 1 GiB reserve"
    );
    m.cleanup()?;
    if ["--check", "--resume-check"].contains(&a[5].as_str()) {
        return Ok(format!(
            "{} root, FAT ESP and firmware partition verified; firmware SHA256 {boot_hash}",
            if resume {
                "Pending same-system"
            } else {
                "Empty ext4"
            }
        ));
    }
    j.phase(
        if resume {
            "Rechecking pending installation"
        } else {
            "Preparing empty target"
        },
        true,
    )?;
    config(j).ram_gate(j)?;
    let next = config(j).layout(j, true)?;
    ensure!(
        identity(&l.root) == identity(&next.root) && identity(&l.esp) == identity(&next.esp),
        "target identity changed"
    );
    mount_root(j, &l, root, true, &mut m)?;
    if resume {
        resume_initial(root, s)?;
    } else {
        empty_root(root)?;
    }
    let marker = pending(
        root,
        "mobile-efi-preparation",
        "First installation incomplete\n",
    )?;
    prepare_store_access(root)?;
    directory(root, "tmp")?;
    fs::set_permissions(root.join("tmp"), fs::Permissions::from_mode(0o1777))?;
    if !resume {
        let mut stream = j.input(input.context("missing transfer")?)?;
        {
            let mut archive = tar::Archive::new(&mut stream);
            archive.set_preserve_permissions(true);
            for entry in archive.entries()? {
                j.check()?;
                let mut entry = entry?;
                let p = entry
                    .path()?
                    .to_string_lossy()
                    .trim_end_matches('/')
                    .to_string();
                let components: Vec<_> = p.split('/').collect();
                ensure!(
                    components.len() >= 3
                        && components[..2] == ["nix", "store"]
                        && store_path(&format!("/nix/store/{}", components[2]))
                        && components.iter().all(|c| *c != ".."),
                    "archive member outside Nix store"
                );
                ensure!(
                    entries.contains_key(&format!("/nix/store/{}", components[2])),
                    "archive contains an undeclared store object"
                );
                let kind = entry.header().entry_type();
                ensure!(
                    kind.is_file() || kind.is_dir() || kind.is_symlink(),
                    "archive contains a non-NAR file type"
                );
                ensure!(entry.unpack_in(root)?, "archive escaped target");
            }
        }
        std::io::copy(&mut stream, &mut std::io::sink())?; // Requires the explicit end frame, including tar padding.
    }
    j.phase("Registering initial closure", true)?;
    runtime(j, root, s, &mut m)?;
    for p in [
        "init",
        "sw/bin/nix-store",
        "sw/bin/nix-env",
        "sw/bin/nix",
        "bin/switch-to-configuration",
    ] {
        ensure!(
            fs::metadata(inside(root, &format!("{s}/{p}"))?)?
                .permissions()
                .mode()
                & 0o111
                != 0,
            "incomplete system tools"
        );
    }
    validate_system(config(j), root, s, &l)?;
    j.run(
        &mut chroot(root, &format!("{s}/sw/bin/nix-store"), &["--load-db"]),
        Some(Box::new(std::io::Cursor::new(registration))),
    )?;
    nix(j, root, s, "nix-store", &["--verify", "--check-contents"])?;
    verify_closure(j, root, s, s, &entries)?;
    let image = inside(root, &format!("{s}/mobile-boot.img"))?;
    let rel = format!(
        "/{}",
        image
            .strip_prefix(root)?
            .to_str()
            .context("firmware path")?
    );
    let object = rel.split('/').take(4).collect::<Vec<_>>().join("/");
    ensure!(
        entries.contains_key(&object),
        "firmware outside verified closure"
    );
    validate_image(j, &image, boot.entry.bytes(), false)?;
    j.phase("Installing EFI generation", false)?;
    directory(root, "etc")?;
    fs::write(root.join("etc/NIXOS"), b"")?;
    mount_esp(j, &l, root, true, &mut m)?;
    activate(j, root, s, s, &l)?;
    let after = config(j).named(j, "firmware")?;
    ensure!(
        before == identity(&after) && hash_file(&after.node)? == boot_hash,
        "firmware partition changed during install"
    );
    j.phase("Writing and verifying U-Boot", false)?;
    write_image(&image, &after)?;
    sync();
    fs::remove_file(marker)?;
    sync();
    m.cleanup()?;
    Ok(format!(
        "Installed {s}; closure, EFI and firmware readback verified. Reboot explicitly."
    ))
}
fn query(j: &Job, a: &[String]) -> Result<String> {
    let entries = manifest(config(j), &a[1], &a[2])?;
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    fsck(j, &l)?;
    let root = Path::new(ROOT);
    let mut m = Mounts::new();
    mount_root(j, &l, root, false, &mut m)?;
    no_pending(root)?;
    let s = selected(config(j), root)?;
    validate_system(config(j), root, &s, &l)?;
    let result = readonly_nix(
        j,
        root,
        &s,
        "nix-store",
        &["--check-validity", "--print-invalid"],
        entries.keys().map(String::as_str),
    )?;
    m.cleanup()?;
    Ok(result)
}
// Even read-only Nix commands need runtime files and a writable DB lock.
// Keep that state in RAM while the target filesystem remains read-only.
fn readonly_nix<'a>(
    j: &Job,
    root: &Path,
    system: &str,
    program: &str,
    args: &[&str],
    extra: impl IntoIterator<Item = &'a str>,
) -> Result<String> {
    let mut m = Mounts::new();
    runtime(j, root, system, &mut m)?;
    let scratch = PathBuf::from(format!("/run/mobile-recovery/query-{}", j.id));
    fs::create_dir(&scratch)?;
    fs::create_dir(scratch.join("temproots"))?;
    for name in ["db", "profiles"] {
        j.run(
            Command::new("/bin/cp")
                .arg("-a")
                .arg(inside(root, &format!("/nix/var/nix/{name}"))?)
                .arg(scratch.join(name)),
            None,
        )?;
    }
    let state = inside(root, "/nix/var/nix")?;
    m.mount(j, &["--bind", scratch.to_str().unwrap()], &state)?;
    let mut cmd = chroot(root, &format!("{system}/sw/bin/{program}"), args);
    cmd.args(extra)
        .env("NIX_REMOTE", "local?read-only=true")
        .env(
            "NIX_CONFIG",
            "extra-experimental-features = read-only-local-store",
        );
    let result = j.run(&mut cmd, None);
    m.cleanup()?;
    fs::remove_dir_all(scratch)?;
    result
}

fn deploy(j: &Job, a: &[String], input: mpsc::Receiver<UnixStream>) -> Result<String> {
    let entries = manifest(config(j), &a[1], &a[2])?;
    let count: usize = a[3].parse()?;
    ensure!(count <= entries.len(), "invalid missing path count");
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    fsck(j, &l)?;
    let root = Path::new(ROOT);
    let mut m = Mounts::new();
    mount_root(j, &l, root, true, &mut m)?;
    no_pending(root)?;
    let old = selected(config(j), root)?;
    validate_system(config(j), root, &old, &l)?;
    runtime(j, root, &old, &mut m)?;
    let mut stream = j.input(input)?;
    if count > 0 {
        let result = j.run(
            &mut chroot(root, &format!("{old}/sw/bin/nix-store"), &["--import"]),
            Some(Box::new(stream)),
        )?;
        ensure!(
            result.lines().count() == count,
            "imported path count differs"
        );
    } else {
        ensure!(stream.read(&mut [0u8; 1])? == 0, "unexpected import data");
    }
    verify_closure(j, root, &old, &a[2], &entries)?;
    validate_system(config(j), root, &a[2], &l)?;
    check_requirements(root, &config(j).deploy_requirements)?;
    j.phase("Installing updated EFI generation", false)?;
    mount_esp(j, &l, root, true, &mut m)?;
    let marker = pending(root, "mobile-offline-deploy", &a[2])?;
    activate(j, root, &old, &a[2], &l)?;
    sync();
    fs::remove_file(marker)?;
    sync();
    m.cleanup()?;
    Ok(format!("Installed {}; firmware unchanged", a[2]))
}
fn check_boot(j: &Job) -> Result<String> {
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    fsck(j, &l)?;
    let root = Path::new(ROOT);
    let mut m = Mounts::new();
    mount_root(j, &l, root, false, &mut m)?;
    no_pending(root)?;
    let s = selected(config(j), root)?;
    validate_system(config(j), root, &s, &l)?;
    mount_esp(j, &l, root, false, &mut m)?;
    check_service_access(j, root, &s)?;
    check_efi(root, &s)?;
    m.cleanup()?;
    Ok(s)
}
fn mounted(j: &Job, rw: bool) -> Result<Layout> {
    let l = config(j).layout(j, true)?;
    for (point, node) in [(MOUNT, &l.root.node), ("/mnt/boot", &l.esp.node)] {
        ensure!(
            tool(j, "findmnt", &["-rn", "-M", point, "-o", "SOURCE"])?.trim()
                == node.to_str().unwrap(),
            "target mount mismatch"
        );
        if rw {
            ensure!(
                tool(j, "findmnt", &["-rn", "-M", point, "-o", "OPTIONS"])?
                    .trim()
                    .split(',')
                    .any(|v| v == "rw"),
                "mount-target --rw first"
            );
        }
    }
    let record = fs::read_to_string("/run/mobile-recovery/mounted")?;
    ensure!(
        record == format!("{}\n{}\n", identity(&l.root), identity(&l.esp)),
        "mounted identity changed"
    );
    Ok(l)
}
fn mount_target(j: &Job, rw: bool) -> Result<String> {
    config(j).ram_gate(j)?;
    let l = config(j).layout(j, true)?;
    fsck(j, &l)?;
    let mut m = Mounts::new();
    mount_root(j, &l, Path::new(MOUNT), rw, &mut m)?;
    ensure!(
        Path::new("/mnt/boot").is_dir(),
        "installed boot directory missing"
    );
    mount_esp(j, &l, Path::new(MOUNT), rw, &mut m)?;
    fs::write(
        "/run/mobile-recovery/mounted",
        format!("{}\n{}\n", identity(&l.root), identity(&l.esp)),
    )?;
    m.points.clear();
    Ok(format!(
        "Mounted /mnt and /mnt/boot {}",
        if rw { "read-write" } else { "read-only" }
    ))
}
fn unmount_target(j: &Job) -> Result<String> {
    mounted(j, false)?;
    j.phase("Unmounting target", false)?;
    sync();
    tool(j, "umount", &["/mnt/boot"])?;
    tool(j, "umount", &["/mnt"])?;
    fs::remove_file("/run/mobile-recovery/mounted")?;
    Ok("Target unmounted".into())
}
fn target_status(j: &Job) -> Result<String> {
    mounted(j, false)?;
    Ok(format!(
        "{}\nSelected: {}",
        tool(j, "findmnt", &["-R", MOUNT])?,
        selected(config(j), Path::new(MOUNT))?
    ))
}
fn generations(j: &Job) -> Result<String> {
    let l = mounted(j, false)?;
    let root = Path::new(MOUNT);
    let s = selected(config(j), root)?;
    validate_system(config(j), root, &s, &l)?;
    readonly_nix(
        j,
        root,
        &s,
        "nix-env",
        &["-p", "/nix/var/nix/profiles/system", "--list-generations"],
        std::iter::empty(),
    )
}
fn rebuild(j: &Job, args: &[String]) -> Result<String> {
    let l = mounted(j, true)?;
    let root = Path::new(MOUNT);
    rebuild_pending_gate(config(j), root)?;
    let old = selected(config(j), root)?;
    validate_system(config(j), root, &old, &l)?;
    let mut m = Mounts::new();
    runtime(j, root, &old, &mut m)?;
    let temp = directory(root, "tmp")?;
    m.mount(j, &["-t", "tmpfs", "-o", "mode=1777", "tmpfs"], &temp)?;
    let marker = pending(root, "mobile-offline-rebuild", &old)?;
    // Build using standard nixos-rebuild, validate its result BEFORE boot/profile writes.
    j.phase("Building target with nixos-rebuild", false)?;
    let output = PathBuf::from(format!("/tmp/recovery-build-{}", j.id));
    let mut cmd = chroot(
        root,
        &format!("{old}/sw/bin/nixos-rebuild"),
        &[
            "--no-reexec",
            "build",
            "--out-link",
            output.to_str().unwrap(),
        ],
    );
    cmd.args(&args[1..]);
    j.run(&mut cmd, None)?;
    let built = inside(root, output.to_str().unwrap())?;
    let new = format!(
        "/{}",
        built.strip_prefix(root)?.to_str().context("build output")?
    );
    validate_system(config(j), root, &new, &l)?;
    activate(j, root, &old, &new, &l)?;
    sync();
    fs::remove_file(marker)?;
    sync();
    m.cleanup()?;
    Ok(format!("Offline boot update complete: {new}"))
}
fn select_generation(j: &Job, number: &str) -> Result<String> {
    let l = mounted(j, true)?;
    let root = Path::new(MOUNT);
    rebuild_pending_gate(config(j), root)?;
    let old = selected(config(j), root)?;
    let p = inside(root, &format!("/nix/var/nix/profiles/system-{number}-link"))?;
    let new = format!(
        "/{}",
        p.strip_prefix(root)?.to_str().context("generation path")?
    );
    validate_system(config(j), root, &new, &l)?;
    let mut m = Mounts::new();
    runtime(j, root, &old, &mut m)?;
    let marker = pending(root, "mobile-offline-rebuild", &old)?;
    activate(j, root, &old, &new, &l)?;
    sync();
    fs::remove_file(marker)?;
    sync();
    m.cleanup()?;
    Ok(format!("Selected {new}"))
}
fn check_service_access(j: &Job, root: &Path, system: &str) -> Result<()> {
    check_store_access(root)?;
    j.run(
        Command::new("/bin/chroot")
            .args(["--userspec=65534:65534", "--groups="])
            .arg(root)
            .arg(format!("{system}/sw/bin/true")),
        None,
    )?;
    Ok(())
}
fn activate(j: &Job, root: &Path, old: &str, new: &str, l: &Layout) -> Result<()> {
    validate_system(config(j), root, new, l)?;
    prepare_store_access(root)?;
    check_service_access(j, root, new)?;
    j.phase("Selecting profile and installing EFI", false)?;
    nix(
        j,
        root,
        old,
        "nix-env",
        &["-p", "/nix/var/nix/profiles/system", "--set", new],
    )?;
    j.run(
        &mut chroot(
            root,
            &format!("{new}/bin/switch-to-configuration"),
            &["boot"],
        ),
        None,
    )?;
    validate_system(config(j), root, new, l)?;
    check_efi(root, new)?;
    ensure!(
        selected(config(j), root)? == new,
        "selected profile mismatch"
    );
    Ok(())
}
fn validate_image(j: &Job, p: &Path, capacity: u64, recovery: bool) -> Result<()> {
    let meta = fs::metadata(p)?;
    ensure!(
        meta.is_file() && meta.len() > 4096 && meta.len() <= capacity && meta.len() <= 256 << 20,
        "image size invalid"
    );
    let data = fs::read(p)?;
    let c = config(j);
    super::image::inspect(
        &data,
        if recovery {
            &c.compatible
        } else {
            &c.firmware_compatible
        },
        recovery,
    )?;
    if recovery && config(j).recovery_avb {
        super::image::recovery_avb(&data)?;
    }
    Ok(())
}
fn write_image(image: &Path, d: &Device) -> Result<()> {
    let out = exclusive(&d.node)?;
    let mut input = File::open(image)?;
    let bytes = input.metadata()?.len();
    ensure!(bytes <= d.entry.bytes(), "image too large");
    let mut expected = Sha256::new();
    let mut b = [0; 65536];
    let mut offset = 0;
    while offset < bytes {
        let n = input.read(&mut b)?;
        ensure!(n > 0, "image truncated during write");
        out.write_all_at(&b[..n], offset)?;
        expected.update(&b[..n]);
        offset += n as u64;
    }
    b.fill(0);
    while offset < d.entry.bytes() {
        let n = (d.entry.bytes() - offset).min(b.len() as u64) as usize;
        out.write_all_at(&b[..n], offset)?;
        expected.update(&b[..n]);
        offset += n as u64;
    }
    out.sync_all()?;
    let mut actual = Sha256::new();
    offset = 0;
    while offset < d.entry.bytes() {
        let n = (d.entry.bytes() - offset).min(b.len() as u64) as usize;
        out.read_exact_at(&mut b[..n], offset)?;
        actual.update(&b[..n]);
        offset += n as u64;
    }
    ensure!(
        actual.finalize() == expected.finalize(),
        "CRITICAL: firmware readback mismatch; stay in recovery"
    );
    Ok(())
}
fn update_image(j: &Job, a: &[String]) -> Result<String> {
    config(j).ram_gate(j)?;
    let recovery = a[0] == "update-recovery";
    let d = config(j).named(j, if recovery { "recovery" } else { "firmware" })?;
    let image = Path::new(&a[1]);
    validate_image(j, image, d.entry.bytes(), recovery)?;
    let digest = hash_file(image)?;
    if a[2] == "--check" {
        return Ok(format!(
            "{} {} SHA256 {digest}",
            d.node.display(),
            fs::metadata(image)?.len()
        ));
    }
    j.phase("Writing image and verifying readback", false)?;
    config(j).ram_gate(j)?;
    write_image(image, &d)?;
    sync();
    Ok(format!("{} verified: {digest}", d.node.display()))
}
fn clear_bcb(j: &Job, check: bool) -> Result<String> {
    bcb(j, check, None)
}
fn bcb(j: &Job, check: bool, request: Option<&[u8]>) -> Result<String> {
    let d = config(j).named(j, "misc")?;
    ensure!(
        d.entry.kind == "82acc91f-357c-4a68-9c8f-689e1b1a23a1"
            && d.entry.bytes() == config(j).misc_bytes as u64,
        "unexpected misc partition"
    );
    let f = if check {
        File::open(&d.node)?
    } else {
        j.phase(
            if request.is_some() {
                "Requesting recovery boot"
            } else {
                "Clearing one-time boot request"
            },
            false,
        )?;
        exclusive(&d.node)?
    };
    let evidence = format!("/run/mobile-recovery/misc-{}.before", j.id);
    bcb_file(&f, config(j).misc_bytes, &evidence, check, request)
}
#[cfg(test)]
fn clear_bcb_file(f: &File, bytes: usize, evidence: &str, dry_run: bool) -> Result<String> {
    bcb_file(f, bytes, evidence, dry_run, None)
}
/// Change only the 32-byte BCB command, transactionally: refuse unknown
/// commands, verify the whole partition and restore the old command on error.
fn bcb_file(
    f: &File,
    bytes: usize,
    evidence: &str,
    dry_run: bool,
    request: Option<&[u8]>,
) -> Result<String> {
    let mut before = vec![0; bytes];
    f.read_exact_at(&mut before, 0)?;
    let command = &before[..32];
    let known =
        command.starts_with(b"boot-recovery\0") || command.starts_with(b"bootonce-bootloader\0");
    let mut new = [0u8; 32];
    if let Some(r) = request {
        ensure!(r.len() < 32 && !r.contains(&0), "invalid BCB request");
        new[..r.len()].copy_from_slice(r);
        ensure!(command[0] == 0 || known, "unknown BCB command");
        if command == new {
            return Ok("Boot request already set; misc unchanged".into());
        }
    } else {
        if command[0] == 0 {
            return Ok("No one-time boot request is set".into());
        }
        ensure!(known, "unknown BCB command");
    }
    if dry_run {
        let name = std::str::from_utf8(command.split(|b| *b == 0).next().unwrap())?;
        return Ok(match request {
            Some(r) => format!(
                "Would set {}; only the 32-byte BCB command changes",
                std::str::from_utf8(r)?
            ),
            None => format!("Would clear {name}; only the 32-byte BCB command changes"),
        });
    }
    fs::write(evidence, &before)?;
    let mut check = vec![0; before.len()];
    f.read_exact_at(&mut check, 0)?;
    ensure!(check == before, "misc changed before command write");
    let mut expected = before.clone();
    expected[..32].copy_from_slice(&new);
    let result = (|| -> Result<()> {
        f.write_all_at(&new, 0)?;
        f.sync_all()?;
        f.read_exact_at(&mut check, 0)?;
        ensure!(check == expected, "BCB readback mismatch");
        Ok(())
    })();
    if let Err(e) = result {
        f.write_all_at(&before[..32], 0)?;
        f.sync_all()?;
        f.read_exact_at(&mut check, 0)?;
        ensure!(
            check == before,
            "CRITICAL: BCB restoration failed; {e}; snapshot {evidence}"
        );
        bail!("BCB update failed, restored: {e}");
    }
    Ok(match request {
        Some(_) => format!("Recovery boot requested; full misc readback verified; snapshot {evidence}"),
        None => format!("One-time boot request cleared; full misc readback verified; snapshot {evidence}. Slot unchanged; no reboot requested"),
    })
}
fn reboot(j: &Job, action: &str) -> Result<String> {
    config(j).ram_gate(j)?;
    if action == "reboot-system" {
        check_boot(j)?;
    }
    j.phase("Rebooting", false)?;
    let c = config(j);
    let bcb_request = c.boot_request == "bcb";
    match action {
        "reboot-system" => {
            clear_bcb(j, false)?;
        }
        "reboot-recovery" if bcb_request => {
            bcb(j, false, Some(b"boot-recovery"))?;
        }
        "reboot-bootloader" if bcb_request => {
            clear_bcb(j, false)?;
        }
        _ => {}
    }
    sync();
    let mut args = vec!["--force".to_string(), "--force".to_string()];
    if action == "reboot-recovery" {
        if let Some(argument) = &c.recovery_reboot_argument {
            args.push(format!("--reboot-argument={argument}"));
        }
    }
    if action == "reboot-bootloader" {
        args.push("--reboot-argument=bootloader".into())
    }
    args.push(
        if action == "poweroff" {
            "poweroff"
        } else {
            "reboot"
        }
        .into(),
    );
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    tool(j, "systemctl", &args)?;
    Ok("Restart requested".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bcb_transaction_preserves_tail_and_rejects_unknown_requests() {
        for bytes in [1048576, 4194304] {
            let p =
                std::env::temp_dir().join(format!("recovery-bcb-{}-{bytes}", std::process::id()));
            let snapshot = p.with_extension("before");
            for (command, accepted, clear) in [
                (&b"boot-recovery"[..], true, true),
                (&b"boot-recovery\0oader"[..], true, true),
                (&b"bootonce-bootloader"[..], true, true),
                (&b"\0\0\0\0\0\0\0\0-bootloader"[..], true, false),
                (&b"unknown"[..], false, false),
                (&b"boot-recovery!!!"[..], false, false),
            ] {
                let mut before = vec![0x7b; bytes];
                before[..32].fill(0);
                before[..command.len()].copy_from_slice(command);
                fs::write(&p, &before).unwrap();
                let read_only = File::open(&p).unwrap();
                assert_eq!(
                    clear_bcb_file(&read_only, bytes, snapshot.to_str().unwrap(), true).is_ok(),
                    accepted
                );
                assert_eq!(fs::read(&p).unwrap(), before);
                let f = fs::OpenOptions::new()
                    .read(true)
                    .write(true)
                    .open(&p)
                    .unwrap();
                assert_eq!(
                    clear_bcb_file(&f, bytes, snapshot.to_str().unwrap(), false).is_ok(),
                    accepted
                );
                if clear {
                    before[..32].fill(0);
                }
                assert_eq!(fs::read(&p).unwrap(), before);
            }
            fs::remove_file(p).unwrap();
            fs::remove_file(snapshot).unwrap();
        }
    }
    #[test]
    fn bcb_recovery_request_is_transactional() {
        let p = std::env::temp_dir().join(format!("recovery-bcb-set-{}", std::process::id()));
        let snapshot = p.with_extension("before");
        for bytes in [1048576, 4194304] {
            for (command, accepted) in [
                (&b""[..], true),
                (&b"boot-recovery"[..], true),
                (&b"bootonce-bootloader"[..], true),
                (&b"unknown"[..], false),
            ] {
                let mut before = vec![0x5a; bytes];
                before[..32].fill(0);
                before[..command.len()].copy_from_slice(command);
                fs::write(&p, &before).unwrap();
                let f = fs::OpenOptions::new()
                    .read(true)
                    .write(true)
                    .open(&p)
                    .unwrap();
                assert_eq!(
                    bcb_file(
                        &f,
                        bytes,
                        snapshot.to_str().unwrap(),
                        true,
                        Some(b"boot-recovery")
                    )
                    .is_ok(),
                    accepted
                );
                assert_eq!(fs::read(&p).unwrap(), before, "dry run must not write");
                let result = bcb_file(
                    &f,
                    bytes,
                    snapshot.to_str().unwrap(),
                    false,
                    Some(b"boot-recovery"),
                );
                assert_eq!(result.is_ok(), accepted);
                let mut expected = before.clone();
                if accepted {
                    expected[..32].fill(0);
                    expected[..13].copy_from_slice(b"boot-recovery");
                }
                // Only the 32-byte command may change; the tail is preserved.
                assert_eq!(fs::read(&p).unwrap(), expected);
            }
        }
        let f = File::open(&p).unwrap();
        assert!(bcb_file(&f, 1048576, "/nonexistent", false, Some(&[b'x'; 32])).is_err());
        let _ = fs::remove_file(p);
        let _ = fs::remove_file(snapshot);
    }
    #[test]
    fn single_slot_operations_and_fat_identity() {
        for a in [
            vec!["prepare-boot"],
            vec!["prepare-boot", "--force"],
            vec!["safe-ufs", "--confirm"],
        ] {
            assert!(validate(&a.into_iter().map(String::from).collect::<Vec<_>>(), false).is_err());
        }
        for a in [
            vec!["prepare-boot", "--check"],
            vec!["prepare-boot", "--confirm"],
            vec!["safe-ufs"],
        ] {
            assert!(validate(&a.into_iter().map(String::from).collect::<Vec<_>>(), false).is_ok());
        }
        valid_fat_identity("NIXOS_BOOT", None).unwrap();
        valid_fat_identity("NIXOS_BOOT", Some("ABCD-1234")).unwrap();
        for (label, volume) in [
            ("", None),
            ("lowercase", None),
            ("TOO_LONG_LABEL", None),
            ("NIXOS_BOOT", Some("ABCD1234")),
            ("NIXOS_BOOT", Some("ABCD-12345")),
            ("NIXOS_BOOT", Some("ABCD-12G4")),
        ] {
            assert!(
                valid_fat_identity(label, volume).is_err(),
                "{label} {volume:?}"
            );
        }
    }
    #[test]
    fn explicit_confirmation_and_stream_contract() {
        for a in [
            vec!["prepare-install", "--confirm"],
            vec!["clear-boot-request"],
            vec!["clear-boot-request", "--force"],
            vec!["repair-backup-gpt"],
            vec!["repair-backup-gpt", "--force"],
            vec!["repair-filesystems"],
            vec!["repair-filesystems", "--force"],
            vec!["rebuild", "switch"],
            vec!["rebuild", "boot", "--target-host=other"],
            vec!["update-recovery", "a.img"],
            vec!["select-generation", "0", "--confirm"],
        ] {
            assert!(validate(&a.into_iter().map(String::from).collect::<Vec<_>>(), false).is_err());
        }
        for flag in ["--check", "--confirm"] {
            assert!(validate(&["clear-boot-request".into(), flag.into()], false).is_ok());
            assert!(validate(&["repair-backup-gpt".into(), flag.into()], false).is_ok());
            assert!(validate(&["repair-filesystems".into(), flag.into()], false).is_ok());
        }
        assert!(validate(
            &["prepare-install".into(), "--confirm-erase-userdata".into()],
            false
        )
        .is_ok());
        assert!(validate(
            &["deploy-offline", "m", "s", "0", "--confirm"].map(String::from),
            false
        )
        .is_err());
    }
    #[test]
    fn manifest_requires_exact_unique_hash_and_system() {
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
        let s = "/nix/store/00000000000000000000000000000000-nixos-system-aurora-1";
        let p = std::env::temp_dir().join(format!("recovery-manifest-{}", std::process::id()));
        let line = format!("sha256:{} {s}\n", "0".repeat(52));
        fs::write(&p, &line).unwrap();
        assert!(manifest(&c, p.to_str().unwrap(), s).is_ok());
        fs::write(&p, format!("{line}{line}")).unwrap();
        assert!(manifest(&c, p.to_str().unwrap(), s).is_err());
        fs::write(&p, line.replace("sha256:", "sha512:")).unwrap();
        assert!(manifest(&c, p.to_str().unwrap(), s).is_err());
        fs::remove_file(p).unwrap();
    }
    #[test]
    fn initial_resume_requires_pending_same_profile_and_no_other_job() {
        let root = std::env::temp_dir().join(format!("recovery-resume-{}", std::process::id()));
        let system = "/nix/store/00000000000000000000000000000000-nixos-system-test-1";
        fs::create_dir_all(root.join(system.trim_start_matches('/'))).unwrap();
        fs::create_dir_all(root.join("nix/var/nix/profiles")).unwrap();
        fs::create_dir_all(root.join("var/lib/mobile-efi-preparation")).unwrap();
        let marker = root.join("var/lib/mobile-efi-preparation/pending");
        assert!(resume_initial(&root, system).is_err());
        fs::write(&marker, "First installation incomplete\n").unwrap();
        assert!(resume_initial(&root, system).is_err());
        std::os::unix::fs::symlink(system, root.join("nix/var/nix/profiles/system")).unwrap();
        resume_initial(&root, system).unwrap();
        assert!(resume_initial(&root, "/nix/store/other-system").is_err());
        fs::write(&marker, "unknown").unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::write(&marker, "First installation incomplete\n").unwrap();
        fs::create_dir_all(root.join("var/lib/mobile-offline-deploy")).unwrap();
        fs::write(root.join("var/lib/mobile-offline-deploy/pending"), system).unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_file(root.join("var/lib/mobile-offline-deploy/pending")).unwrap();
        fs::rename(&marker, marker.with_extension("real")).unwrap();
        std::os::unix::fs::symlink("pending.real", &marker).unwrap();
        assert!(resume_initial(&root, system).is_err());
        for flag in ["--resume-check", "--resume-confirm"] {
            let args = ["install-initial", "m", "r", system, "4096", flag].map(String::from);
            assert!(validate(&args, false).is_ok());
            assert!(validate(&args, true).is_err());
        }
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn pending_root_is_allowed_but_previous_install_is_not() {
        let root = std::env::temp_dir().join(format!("recovery-empty-{}", std::process::id()));
        fs::create_dir(&root).unwrap();
        empty_root(&root).unwrap();
        fs::create_dir_all(root.join("var/lib/mobile-efi-preparation")).unwrap();
        fs::write(
            root.join("var/lib/mobile-efi-preparation/pending"),
            b"pending",
        )
        .unwrap();
        empty_root(&root).unwrap();
        let keys = root.join("var/lib/mobile-recovery/ssh");
        fs::create_dir_all(&keys).unwrap();
        fs::write(keys.join("ssh_host_ed25519_key"), b"key").unwrap();
        fs::write(keys.join("ssh_host_ed25519_key.pub"), b"public").unwrap();
        empty_root(&root).unwrap();
        fs::write(keys.join("unexpected"), b"data").unwrap();
        assert!(empty_root(&root).is_err());
        fs::remove_file(keys.join("unexpected")).unwrap();
        fs::remove_file(keys.join("ssh_host_ed25519_key")).unwrap();
        std::os::unix::fs::symlink(
            "ssh_host_ed25519_key.pub",
            keys.join("ssh_host_ed25519_key"),
        )
        .unwrap();
        assert!(empty_root(&root).is_err());
        fs::remove_file(keys.join("ssh_host_ed25519_key")).unwrap();
        fs::create_dir(root.join("nix")).unwrap();
        assert!(empty_root(&root).is_err());
        assert!(no_pending(&root).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
