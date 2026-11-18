//! Recovery operations use Rust orchestration and upstream filesystem/Nix tools.
use super::{engine::Job, storage::*};
use anyhow::{bail, ensure, Context, Result};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::Read,
    os::unix::{
        fs::{FileExt, OpenOptionsExt, PermissionsExt},
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
    "install-initial-system",
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
    "mark-slot-successful",
    "repair-backup-gpt",
    "restore-gpt",
    "gpt-backup",
    "repair-filesystems",
    "reboot-system",
    "reboot-recovery",
    "reboot-bootloader",
    "poweroff",
];
pub fn capabilities(config: &Config) -> Vec<String> {
    ACTIONS
        .iter()
        .filter(|a| !(config.mediatek_a() && **a == "update-recovery"))
        .map(|s| s.to_string())
        .collect()
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
            ["--check", "--confirm-erase-userdata"].contains(&a[argc - 1].as_str())
                && (argc == 2
                    || (argc == 4
                        && a[1] == "--android-userdata"
                        && super::gpt::parse_gib(&a[2]).is_ok())),
            "use prepare-install [--android-userdata SIZE] --check|--confirm-erase-userdata"
        ),
        "format-root" | "prepare-boot" | "clear-boot-request" | "mark-slot-successful"
        | "repair-backup-gpt" | "restore-gpt" | "repair-filesystems" => ensure!(
            argc == 2 && ["--check", "--confirm"].contains(&a[1].as_str()),
            "use format-root|prepare-boot|clear-boot-request|mark-slot-successful|repair-backup-gpt|restore-gpt|repair-filesystems --check|--confirm"
        ),
        "install-initial-system" => ensure!(
            argc == 6 && ["--check", "--confirm", "--resume-check", "--resume-confirm"].contains(&a[5].as_str()),
            "use install-initial-system MANIFEST REGISTRATION SYSTEM MIN_BYTES --check|--confirm|--resume-check|--resume-confirm"
        ),
        "gpt-backup" => ensure!(argc == 1, "use gpt-backup"),
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
        (action == "install-initial-system" && a[5] == "--confirm") || action == "deploy-offline";
    ensure!(
        wants_input == input,
        "input channel does not match operation"
    );
    Ok(())
}
pub fn execute(j: &Job, a: &[String], input: Option<mpsc::Receiver<UnixStream>>) -> Result<String> {
    j.engine.config.identity()?;
    match a[0].as_str() {
        "prepare-install" => prepare(
            j,
            a[a.len() - 1] == "--check",
            if a.len() == 4 {
                Some(super::gpt::parse_gib(&a[2])?)
            } else {
                None
            },
        ),
        "prepare-boot" => prepare_boot(j, a[1] == "--check"),
        "safe-ufs" => safe_ufs(j),
        "format-root" => format(j, a[1] == "--check"),
        "repair-backup-gpt" => repair_backup_gpt(j, a[1] == "--check"),
        "restore-gpt" => restore_gpt(j, a[1] == "--check"),
        "gpt-backup" => gpt_backup(j),
        "repair-filesystems" => repair_filesystems(j, a[1] == "--check"),
        "install-initial-system" => initial(j, a, input),
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
        "mark-slot-successful" => mark_slot_successful(j, a[1] == "--check"),
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
/// Repair stale backup GPTs on the disks holding the firmware slot
/// (`boot_b`, MediaTek `boot_a`) and Android userdata, from their CRC-verified
/// primaries. Only the backup array/header of a disk is written.
fn repair_backup_gpt(j: &Job, check: bool) -> Result<String> {
    ab_only(j, "repair-backup-gpt")?;
    let c = config(j);
    c.ram_gate_for_backup_repair(j)?;
    let firmware = if c.mediatek_a() { "boot_a" } else { "boot_b" };
    let mut targets: Vec<Device> = Vec::new();
    for name in [firmware, if c.linux_only { "linux" } else { "userdata" }] {
        let d = c.partition_for_backup_repair(j, name)?;
        if targets.iter().all(|t| t.disk != d.disk) {
            targets.push(d);
        }
    }
    for t in &targets {
        if t.gpt.partition("linux").is_err() {
            continue;
        }
        if c.linux_only {
            t.gpt
                .check_linux_only_layout(c.esp_bytes, c.minimum_root_bytes)?;
        } else if c.mediatek_a() {
            t.gpt
                .check_userdata_layout(c.esp_size(), c.minimum_root_bytes)?;
        } else {
            t.gpt
                .check_linux_layout(c.esp_bytes, c.minimum_root_bytes)?;
        }
    }
    let mut plan = Vec::new();
    for t in &targets {
        if t.gpt.backup_needs_repair() {
            plan.push(format!(
                "Repair backup GPT on {} from its CRC-verified primary: {}.",
                t.disk.display(),
                t.gpt.backup_repair_summary()?
            ));
        }
    }
    if plan.is_empty() {
        let disks: Vec<_> = targets
            .iter()
            .map(|t| t.disk.display().to_string())
            .collect();
        return Ok(format!(
            "Both GPT copies agree on {}; no repair needed",
            disks.join(", ")
        ));
    }
    plan.push("Only stale A/B type GUIDs, slot attributes and the backup CRC may differ. Preserve primary GPT, layout, payloads and OEM padding.".into());
    let plan = plan.join("\n");
    if check {
        return Ok(plan);
    }
    c.ram_gate_for_backup_repair(j)?;
    j.phase("Repairing backup GPT; do not reboot", false)?;
    let mut evidence = Vec::new();
    for t in targets.iter().filter(|t| t.gpt.backup_needs_repair()) {
        let disk = exclusive(&t.disk)?;
        let name = t.disk.file_name().context("disk name")?.to_string_lossy();
        let dir = PathBuf::from(format!("/run/mobile-recovery/gpt-repair-{}-{name}", j.id));
        t.gpt.snapshot(&dir)?;
        t.gpt.repair_backup(&disk)?;
        evidence.push(dir.display().to_string());
    }
    Ok(format!(
        "{plan}\nReadback verified; metadata snapshots: {}",
        evidence.join(", ")
    ))
}
fn type_name(kind: &str) -> &'static str {
    use super::gpt::{ANDROID, BASIC_DATA, ESP, LINUX};
    match kind {
        k if k == ESP => "EFI system",
        k if k == LINUX => "Linux filesystem",
        k if k == BASIC_DATA => "basic data",
        k if k == ANDROID => "Android data",
        _ => "other",
    }
}
/// The exact planned table: every entry that changes or is added, the entry
/// count and what stays untouched.
fn describe_split(
    old: &super::gpt::Gpt,
    parts: &[super::gpt::Partition],
    count: usize,
    disk: &Path,
) -> Result<String> {
    use std::fmt::Write as _;
    let user = old.partition("userdata")?;
    let mib = |b: u64| b as f64 / (1u64 << 20) as f64;
    let mut out = String::new();
    writeln!(
        out,
        "Userdata split on {} (4096-byte sectors; LBA in 4 KiB units)",
        disk.display()
    )?;
    writeln!(
        out,
        "Userdata span: LBA {}-{} ({:.1} MiB); nothing outside it changes.",
        user.start,
        user.end,
        mib(user.bytes())
    )?;
    writeln!(
        out,
        "GPT entries: {} -> {} in both headers (arrays stay in their sectors).",
        old.entry_count(),
        count
    )?;
    writeln!(
        out,
        "{:>3} {:<15} {:>10} {:>10} {:>12}  {:<16} {:<36} change",
        "#", "name", "first LBA", "last LBA", "MiB", "type", "partition GUID"
    )?;
    let mut unchanged = 0;
    for p in parts {
        let change = match old.partitions.iter().find(|o| o.number == p.number) {
            Some(o) if o == p => {
                unchanged += 1;
                continue;
            }
            Some(o) => format!("end {} -> {}", o.end, p.end),
            None => "new".into(),
        };
        writeln!(
            out,
            "{:>3} {:<15} {:>10} {:>10} {:>12.1}  {:<16} {:<36} {}",
            p.number,
            p.name,
            p.start,
            p.end,
            mib(p.bytes()),
            type_name(&p.kind),
            p.uuid,
            change
        )?;
        ensure!(p.start % 256 == 0, "{} is not 1 MiB aligned", p.name);
    }
    writeln!(
        out,
        "All starts are 1 MiB aligned; {unchanged} other entries unchanged (super, misc, metadata, both slots, calibration and partitions after userdata)."
    )?;
    write!(
        out,
        "Destroys Android userdata: the new userdata is left unformatted (first 8 MiB zeroed) and metadata is untouched; wipe data from the stock recovery on slot B before using Android."
    )?;
    Ok(out)
}
/// Where the host pushes a saved original GPT for `restore-gpt`.
const GPT_RESTORE: &str = "/run/mobile-recovery/gpt-restore";
/// The original GPT saved in RAM before a userdata split (header and array
/// images of both copies). The split saves it itself; the host may copy it
/// for a permanent backup. It is lost when the recovery restarts.
const GPT_BACKUP: &str = "/run/mobile-recovery/gpt-original";
/// How the check's saved copy is used.
const CHECK_NOTE: &str = "The split itself keeps this RAM copy (restore-gpt undoes it during this recovery session); for a permanent copy, download it to the host first (mobile-device recovery prepare-install --gpt-backup DIR). restore-gpt prefers a host copy pushed to /run/mobile-recovery/gpt-restore.";
/// Save the original GPT once. An existing copy is never replaced: it is
/// kept when it still matches the disk and refused otherwise. The copy is
/// written to a temporary directory, verified against the disk and only
/// then renamed into place, so a failed save leaves no partial copy.
fn save_gpt_backup(dir: &Path, disk: &File, g: &super::gpt::Gpt) -> Result<String> {
    let current = g.capture(disk)?;
    if dir.exists() {
        let saved = super::gpt::load_snapshot(dir, g).with_context(|| {
            format!(
                "the saved original GPT ({}) cannot be read for this disk and is never overwritten; inspect it before restarting recovery",
                dir.display()
            )
        })?;
        ensure!(
            saved == current,
            "the saved original GPT ({}) differs from the disk and is never overwritten; the disk changed after it was saved (undo with restore-gpt, or copy it to the host before restarting recovery)",
            dir.display()
        );
        return describe_snapshot(dir, "Original GPT already saved in RAM (matches the disk)");
    }
    let partial = dir.with_extension("partial");
    if partial.exists() {
        fs::remove_dir_all(&partial)?;
    }
    g.snapshot(&partial)?;
    ensure!(
        super::gpt::load_snapshot(&partial, g)? == current,
        "the GPT changed while it was saved; nothing written"
    );
    fs::rename(&partial, dir)?;
    describe_snapshot(dir, "Original GPT saved in RAM")
}
/// The userdata split's GPT write: keep the original GPT in RAM (saved now
/// unless an identical copy exists; a different copy refuses the write),
/// record the evidence copy and write the planned table.
fn write_split_gpt(
    original: &Path,
    f: &File,
    g: &super::gpt::Gpt,
    evidence: &Path,
    write: impl FnOnce(&File) -> Result<()>,
) -> Result<String> {
    let saved = save_gpt_backup(original, f, g)?;
    g.snapshot(evidence)?;
    write(f)?;
    Ok(saved)
}
/// Text shown after a userdata split: how to undo it during this recovery
/// session and what Android needs.
fn split_epilogue(saved: &str) -> String {
    format!(
        "{saved}\nUndo during this recovery session: recovery restore-gpt --check, then --confirm (uses the RAM copy; lost when the recovery restarts unless copied to the host).\nAndroid needs a factory reset (wipe data) before it boots again."
    )
}
/// Short plan lines ("Plan: ...") for the recovery screen: the userdata
/// entries that change or are added.
fn plan_summary(old: &super::gpt::Gpt, parts: &[super::gpt::Partition]) -> String {
    let gib = |p: &super::gpt::Partition| p.bytes() as f64 / (1u64 << 30) as f64;
    let mut out = Vec::new();
    for p in parts {
        match old.partitions.iter().find(|o| o.number == p.number) {
            Some(o) if o == p => {}
            Some(o) if p.name == "userdata" => out.push(format!(
                "Plan: userdata {:.1} -> {:.1} GiB (Android, erased)",
                gib(o),
                gib(p)
            )),
            Some(o) => out.push(format!(
                "Plan: {} {:.1} -> {:.1} GiB",
                p.name,
                gib(o),
                gib(p)
            )),
            None => out.push(format!("Plan: new {} {:.1} GiB", p.name, gib(p))),
        }
    }
    out.join("\n")
}
/// The saved GPT `restore-gpt` writes back: a copy the host pushed, else
/// the original the split saved in RAM during this recovery session.
fn restore_source<'a>(pushed: &'a Path, original: &'a Path) -> Result<&'a Path> {
    if pushed.exists() {
        Ok(pushed)
    } else if original.exists() {
        Ok(original)
    } else {
        bail!(
            "no saved original GPT: neither a host copy pushed to {} nor the copy prepare-install saved in RAM ({}; lost when the recovery restarts)",
            pushed.display(),
            original.display()
        )
    }
}
/// What a rollback image may change: only its userdata span. Every other
/// entry of the image is unchanged on the disk, and the entries it lacks
/// are the Linux partitions of the split inside that span.
fn rollback_scope<'a>(
    image: &'a [super::gpt::Partition],
    now: &[super::gpt::Partition],
    linux_only: bool,
) -> Result<&'a super::gpt::Partition> {
    let user = image
        .iter()
        .find(|p| p.name == "userdata")
        .context("rollback image has no userdata")?;
    for old in image.iter().filter(|p| p.name != "userdata") {
        ensure!(
            now.contains(old),
            "rollback image differs from the disk outside the userdata span ({})",
            old.name
        );
    }
    if linux_only {
        ensure!(
            !now.iter().any(|p| p.name == "userdata"),
            "Linux-only disk still has userdata"
        );
        let esp = now
            .iter()
            .find(|p| p.name == "linux-boot")
            .context("missing Linux ESP")?;
        let root = now
            .iter()
            .find(|p| p.name == "linux")
            .context("missing Linux root")?;
        ensure!(
            esp.start == user.start && esp.end + 1 == root.start && root.end == user.end,
            "Linux partitions do not cover the saved userdata span"
        );
    } else {
        let current = now
            .iter()
            .find(|p| p.name == "userdata")
            .context("the disk has no userdata")?;
        ensure!(
            current.start == user.start,
            "rollback image userdata starts elsewhere than on the disk"
        );
    }
    for p in now
        .iter()
        .filter(|p| p.name != "userdata" && !image.contains(p))
    {
        ensure!(
            super::gpt::USERDATA_SPLIT.contains(&p.name.as_str())
                && p.start >= user.start
                && p.end <= user.end,
            "{} is not a Linux partition inside the saved userdata span",
            p.name
        );
    }
    Ok(user)
}
fn describe_snapshot(dir: &Path, what: &str) -> Result<String> {
    use std::fmt::Write as _;
    let mut out = format!("{what}: {}", dir.display());
    let mut names: Vec<_> = fs::read_dir(dir)?
        .map(|e| e.map(|e| e.path()))
        .collect::<std::io::Result<_>>()?;
    names.sort();
    for p in names {
        write!(out, "\n  {} SHA256 {}", p.display(), hash_file(&p)?)?;
    }
    Ok(out)
}
/// Save the current GPT (both copies, byte images) in RAM for the host,
/// in a new directory per task; the original from prepare-install is
/// left alone.
fn gpt_backup(j: &Job) -> Result<String> {
    ab_only(j, "gpt-backup")?;
    let user = config(j).partition(
        j,
        if config(j).linux_only {
            "super"
        } else {
            "userdata"
        },
    )?;
    let dir = PathBuf::from(format!("/run/mobile-recovery/gpt-current-{}", j.id));
    user.gpt.snapshot(&dir)?;
    describe_snapshot(&dir, "Current GPT saved in RAM")
}
/// Roll the userdata split back: write a saved original GPT (a host copy
/// pushed to `GPT_RESTORE`, else the RAM copy `prepare-install` saved in
/// this recovery session) byte for byte, backup copy first, verify it and
/// make the kernel re-read the table.
fn restore_gpt(j: &Job, check: bool) -> Result<String> {
    ab_only(j, "restore-gpt")?;
    config(j).ram_gate(j)?;
    let misc = config(j).partition(
        j,
        if config(j).linux_only {
            "super"
        } else {
            "userdata"
        },
    )?;
    let source = restore_source(Path::new(GPT_RESTORE), Path::new(GPT_BACKUP))?;
    let image = super::gpt::load_snapshot(source, &misc.gpt)?;
    let (count, parts) = super::gpt::image_partitions(&image, super::gpt::SECTOR)?;
    let user = rollback_scope(&parts, &misc.gpt.partitions, config(j).linux_only)?;
    let plan = format!(
        "Restore the saved GPT from {} ({count} entries, userdata LBA {}-{}) on {}; current table has {} entries. Linux partitions and their data become unreachable.",
        source.display(),
        user.start,
        user.end,
        misc.disk.display(),
        misc.gpt.entry_count()
    );
    if check {
        return Ok(format!("{plan}\nCheck only; no writes."));
    }
    j.phase("Restoring the original GPT; do not reboot", false)?;
    let disk = exclusive(&misc.disk)?;
    super::gpt::restore(&disk, &image)?;
    reread(&disk)?;
    drop(disk);
    tool(j, "udevadm", &["settle"])?;
    let now = config(j).partition(j, "userdata")?;
    ensure!(
        now.gpt.partitions == parts && now.gpt.entry_count() == count,
        "restored GPT readback differs; stay in recovery"
    );
    Ok(format!("{plan}\nRestored and verified."))
}
/// MediaTek slot-A install storage inside the userdata span.
fn prepare_userdata(j: &Job, check: bool, android: u64, offered: &str) -> Result<String> {
    let c = config(j);
    c.ram_gate(j)?;
    let user = c.partition(j, "userdata")?;
    let (parts, count) = user
        .gpt
        .split_userdata(c.esp_size(), c.minimum_root_bytes, android)?;
    let plan = format!(
        "{offered}\n{}\n{}",
        describe_split(&user.gpt, &parts, count, &user.disk)?,
        plan_summary(&user.gpt, &parts)
    );
    if check {
        let saved = save_gpt_backup(Path::new(GPT_BACKUP), &File::open(&user.disk)?, &user.gpt)?;
        return Ok(format!(
            "{plan}\nCheck only; no partition or filesystem writes.\n{saved}\n{CHECK_NOTE}"
        ));
    }
    c.ram_gate(j)?;
    j.phase("Writing GPT; do not reboot", false)?;
    let disk = exclusive(&user.disk)?;
    let evidence = PathBuf::from(format!("/run/mobile-recovery/gpt-{}", j.id));
    let saved = write_split_gpt(Path::new(GPT_BACKUP), &disk, &user.gpt, &evidence, |f| {
        user.gpt.write_plan(f, &parts, count)
    })?;
    reread(&disk)?;
    drop(disk);
    tool(j, "udevadm", &["settle"])?;
    let layout = c.layout(j, false)?;
    let user = c.partition(j, "userdata")?;
    j.phase("Clearing Android userdata and formatting Linux", false)?;
    let zeros = vec![0; 8 << 20];
    {
        let f = exclusive(&user.node)?;
        f.write_all_at(&zeros, 0)?;
        f.sync_all()?;
    }
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
            &c.root_label,
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
            &c.boot_label,
            layout.esp.node.to_str().unwrap(),
        ],
    )?;
    sync();
    c.layout(j, true)?;
    fsck(j, &layout)?;
    Ok(format!(
        "{plan}\nDone. GPT evidence: {}. Next: wipe data from the stock recovery on slot B, then install NixOS before booting Linux.\n{}",
        evidence.display(),
        split_epilogue(&saved)
    ))
}
/// Opt-in whole-userdata installation. Boot, firmware and metadata stay intact.
fn prepare_linux_only(j: &Job, check: bool) -> Result<String> {
    ab_only(j, "prepare-install; use format-root and prepare-boot")?;
    config(j).ram_gate(j)?;
    let user = config(j).partition(j, "userdata")?;
    let parts = user
        .gpt
        .linux_only(config(j).esp_bytes, config(j).minimum_root_bytes)?;
    let plan = format!("Linux-only layout: entire userdata\nPlan: Replace all Android userdata with a Linux ESP and root\n{}", describe_split(&user.gpt, &parts, user.gpt.entry_count(), &user.disk)?);
    if check {
        let saved = save_gpt_backup(Path::new(GPT_BACKUP), &File::open(&user.disk)?, &user.gpt)?;
        return Ok(format!("{plan}\nDestroys ALL Android userdata; replaces its allocation with a Linux ESP and root. Preserves boot/recovery slots, super and metadata.\nCheck only; no partition or filesystem writes.\n{saved}\n{CHECK_NOTE}"));
    }
    config(j).ram_gate(j)?;
    j.phase("Writing GPT; do not reboot", false)?;
    let disk = exclusive(&user.disk)?;
    let evidence = PathBuf::from(format!("/run/mobile-recovery/gpt-{}", j.id));
    let saved = write_split_gpt(Path::new(GPT_BACKUP), &disk, &user.gpt, &evidence, |f| {
        user.gpt.write_split(f, &parts)
    })?;
    reread(&disk)?;
    drop(disk);
    tool(j, "udevadm", &["settle"])?;
    let layout = config(j).layout(j, false)?;
    j.phase("Formatting Linux root and ESP", false)?;
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
            &config(j).boot_label,
            layout.esp.node.to_str().unwrap(),
        ],
    )?;
    sync();
    config(j).layout(j, true)?;
    fsck(j, &layout)?;
    Ok(format!("Prepared ext4 root and FAT ESP; Android userdata allocation replaced. GPT evidence: {}. Install explicitly before Linux boot.\n{}",evidence.display(), split_epilogue(&saved)))
}
/// A/B devices: the user chooses how much of the userdata allocation Android
/// keeps (32/64/128/256/512 GiB, offered when the Linux ESP and root keep at
/// least 64 GiB); Linux gets the rest.
fn prepare(j: &Job, check: bool, android: Option<u64>) -> Result<String> {
    if config(j).linux_only {
        ensure!(
            android.is_none(),
            "Linux-only installation does not retain Android userdata"
        );
        return prepare_linux_only(j, check);
    }
    use super::gpt::MINIMUM_LINUX;
    ab_only(j, "prepare-install; use format-root and prepare-boot")?;
    let c = config(j);
    c.ram_gate(j)?;
    let user = c.partition(j, "userdata")?;
    let gib = |b: u64| format!("{}G", b >> 30);
    let choices = user.gpt.android_userdata_choices()?;
    let offered = format!(
        "Android userdata choices: {}\n(sizes that leave the Linux ESP and root at least {} of the {:.1} GiB userdata allocation)",
        if choices.is_empty() {
            "none".into()
        } else {
            choices.iter().map(|b| gib(*b)).collect::<Vec<_>>().join(" ")
        },
        gib(MINIMUM_LINUX),
        user.entry.bytes() as f64 / (1u64 << 30) as f64
    );
    ensure!(
        !choices.is_empty() || check,
        "no Android userdata size leaves Linux enough space; the userdata split is refused\n{offered}"
    );
    let Some(android) = android else {
        ensure!(
            check,
            "choose the Android userdata size: prepare-install --android-userdata SIZE --confirm-erase-userdata\n{offered}"
        );
        return Ok(format!(
            "{offered}\nCheck only. {}",
            if choices.is_empty() {
                "The userdata split is refused on this disk."
            } else {
                "Show the plan with prepare-install --android-userdata SIZE --check."
            }
        ));
    };
    if c.mediatek_a() {
        return prepare_userdata(j, check, android, &offered);
    }
    let parts =
        user.gpt
            .split_keeping(config(j).esp_bytes, config(j).minimum_root_bytes, android)?;
    let plan = serde_json::to_string_pretty(&parts)?;
    let summary = plan_summary(&user.gpt, &parts);
    if check {
        let saved = save_gpt_backup(Path::new(GPT_BACKUP), &File::open(&user.disk)?, &user.gpt)?;
        return Ok(format!(
            "{offered}\n{plan}\n{summary}\nKeeps {} for Android userdata and erases it; preserves A, DTBO, super and metadata. Android requires a separate factory reset.\nCheck only; no partition or filesystem writes.\n{saved}\n{CHECK_NOTE}",
            gib(android)
        ));
    }
    config(j).ram_gate(j)?;
    j.phase("Writing GPT; do not reboot", false)?;
    let disk = exclusive(&user.disk)?;
    let evidence = PathBuf::from(format!("/run/mobile-recovery/gpt-{}", j.id));
    let saved = write_split_gpt(Path::new(GPT_BACKUP), &disk, &user.gpt, &evidence, |f| {
        user.gpt.write_split(f, &parts)
    })?;
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
            &config(j).boot_label,
            layout.esp.node.to_str().unwrap(),
        ],
    )?;
    sync();
    config(j).layout(j, true)?;
    fsck(j, &layout)?;
    Ok(format!(
        "{summary}\nPrepared ext4 root and FAT ESP; Android userdata erased. GPT evidence: {}. Install explicitly before Linux boot.\n{}",
        evidence.display(),
        split_epilogue(&saved)
    ))
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
    // An explicit ESP label is also verified later; otherwise use the
    // configured boot label.
    let label = roles
        .esp
        .fs_label
        .as_deref()
        .unwrap_or(&config(j).boot_label);
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
        fat_check(j, &l.esp.node)?;
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
    fat_check(j, &l.esp.node)?;
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
    fat_check(j, &l.esp.node)
}
/// Read-only FAT check. `fsck.fat -n` exits 1 whenever it would change
/// anything, including the FSInfo free-cluster count, which is only a hint:
/// U-Boot's FAT writer (systemd-boot's random seed, EFI variables) leaves it
/// stale and Linux recounts it. Exit 1 is accepted only when that count is
/// the sole finding; nothing is repaired here (`repair-filesystems` does).
fn fat_check(j: &Job, node: &Path) -> Result<()> {
    let output = j.run_codes(
        Command::new("/bin/fsck.fat").arg("-n").arg(node),
        None,
        &[0, 1],
    )?;
    if fat_hint_only(&output)? {
        j.log("FAT FSInfo free-cluster count is stale (a hint only); not repaired");
    }
    Ok(())
}
/// Classify `fsck.fat -n` output: Ok(false) when it found nothing to change,
/// Ok(true) when the only change is the FSInfo free-cluster count.
fn fat_hint_only(output: &str) -> Result<bool> {
    if !output
        .lines()
        .any(|l| l.trim() == "Leaving filesystem unchanged.")
    {
        return Ok(false);
    }
    let mut hint = false;
    for line in output.lines().map(str::trim).filter(|l| !l.is_empty()) {
        if line.starts_with("Free cluster summary wrong (") && line.ends_with(')') {
            hint = true;
        } else if !(line.starts_with("fsck.fat ")
            || line == "Auto-correcting."
            || line == "Leaving filesystem unchanged."
            || (line.contains(" files, ") && line.ends_with(" clusters")))
        {
            bail!("FAT filesystem check found errors; run repair-filesystems:\n{output}");
        }
    }
    ensure!(
        hint,
        "FAT filesystem check found errors; run repair-filesystems:\n{output}"
    );
    Ok(true)
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
/// Resume the same pending first installation without transferring the closure
/// again. With a selected profile it must be this system. Without one (a
/// failure after the transfer, before the profile was set), the store may hold
/// only objects of this system's manifest; the resumed run registers and
/// hashes the whole closure again before writing the profile, EFI or firmware.
fn resume_initial(root: &Path, system: &str, entries: &BTreeMap<String, String>) -> Result<()> {
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
    let profile = inside(root, "/nix/var/nix/profiles")?.join("system");
    if fs::symlink_metadata(&profile).is_err() {
        ensure!(
            inside(root, system)?.is_dir(),
            "resume requires the transferred system; format the root and install again"
        );
        for e in fs::read_dir(inside(root, "/nix/store")?)? {
            let e = e?;
            let name = e.file_name();
            let name = name.to_str().context("store object name")?;
            if nix_store_internal(name, &e.file_type()?, entries) {
                continue;
            }
            ensure!(
                entries.contains_key(&format!("/nix/store/{name}")),
                "store object {name} is not in the manifest; format the root and install again"
            );
        }
        return Ok(());
    }
    let selected = inside(root, "/nix/var/nix/profiles/system")?;
    ensure!(
        selected == inside(root, system)? && selected.is_dir(),
        "resume requires the same registered system profile"
    );
    Ok(())
}
/// Nix's own entries in /nix/store that are not store objects: the
/// hard-link deduplication directory `.links` (auto-optimise-store, filled
/// while the closure is registered) and path lock files `<object>.lock` of
/// declared objects. Symlinks or other types under these names do not count.
fn nix_store_internal(name: &str, kind: &fs::FileType, entries: &BTreeMap<String, String>) -> bool {
    if name == ".links" {
        return kind.is_dir();
    }
    name.strip_suffix(".lock").is_some_and(|object| {
        kind.is_file() && entries.contains_key(&format!("/nix/store/{object}"))
    })
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
    fsck(j, &l)?;
    let mut m = Mounts::new();
    mount_root(j, &l, root, false, &mut m)?;
    if resume {
        resume_initial(root, s, &entries)?;
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
            "{} root and FAT ESP verified",
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
        resume_initial(root, s, &entries)?;
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
    j.phase("Installing EFI generation", false)?;
    directory(root, "etc")?;
    fs::write(root.join("etc/NIXOS"), b"")?;
    mount_esp(j, &l, root, true, &mut m)?;
    activate(j, root, s, s, &l)?;
    sync();
    fs::remove_file(marker)?;
    sync();
    m.cleanup()?;
    Ok(format!(
        "Installed {s}; closure and EFI verified. Reboot explicitly."
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
    check_installed(j)
}
/// Read-only check of the selected installed system and its EFI entry.
fn check_installed(j: &Job) -> Result<String> {
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
fn validated_image(j: &Job, p: &Path, capacity: u64, recovery: bool) -> Result<Vec<u8>> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(p)?;
    let meta = file.metadata()?;
    let limit = capacity.min(256 << 20);
    ensure!(
        meta.is_file() && meta.len() > 4096 && meta.len() <= limit,
        "image size invalid"
    );
    let mut data = Vec::with_capacity(meta.len() as usize);
    file.take(limit + 1).read_to_end(&mut data)?;
    ensure!(
        data.len() as u64 == meta.len(),
        "image size changed during read"
    );
    let c = config(j);
    if c.mediatek_a() {
        ensure!(
            !recovery,
            "this slot model uses USB RAM recovery; no recovery partition"
        );
        super::image::inspect_v4_firmware(&data, &c.firmware_compatible)?;
        super::image::avb_hash_footer(&data, capacity as usize, "boot")?;
        return Ok(data);
    }
    if recovery && super::image::has_fit_ramdisk(&data) {
        // u-boot-fit: the board's U-Boot image with a RAM recovery FIT ramdisk.
        super::image::inspect_fit_recovery_image(&data, &c.firmware_compatible, &c.compatible)?;
    } else {
        super::image::inspect(
            &data,
            if recovery {
                &c.compatible
            } else {
                &c.firmware_compatible
            },
            recovery,
        )?;
    }
    if recovery && config(j).recovery_avb {
        super::image::recovery_avb(&data)?;
    }
    Ok(data)
}
fn write_image(image: &[u8], d: &Device) -> Result<()> {
    let out = exclusive(&d.node)?;
    let mut offset = image.len() as u64;
    ensure!(offset <= d.entry.bytes(), "image too large");
    out.write_all_at(image, 0)?;
    let mut expected = Sha256::new();
    expected.update(image);
    let mut b = [0; 65536];
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
    let image = validated_image(j, Path::new(&a[1]), d.entry.bytes(), recovery)?;
    let digest = format!("{:x}", Sha256::digest(&image));
    if a[2] == "--check" {
        return Ok(format!(
            "{} {} SHA256 {digest}",
            d.node.display(),
            image.len()
        ));
    }
    j.phase("Writing image and verifying readback", false)?;
    config(j).ram_gate(j)?;
    write_image(&image, &d)?;
    sync();
    Ok(format!("{} verified: {digest}", d.node.display()))
}
/// Repair for the U-Boot slot confirmation: set slot A's successful_boot in
/// the AOSP boot control (misc + 2048), keeping priority, tries and slot B.
fn mark_slot_successful(j: &Job, check: bool) -> Result<String> {
    let c = config(j);
    ensure!(
        c.mediatek_a(),
        "mark-slot-successful is only available with the MediaTek slot-A model"
    );
    c.ram_gate(j)?;
    let misc = c.partition(j, "misc")?;
    ensure!(
        misc.entry.bytes() == c.misc_bytes as u64,
        "misc capacity mismatch"
    );
    let f = if check {
        File::open(&misc.node)?
    } else {
        j.phase("Marking slot A successful", false)?;
        exclusive(&misc.node)?
    };
    let mut before = vec![0; c.misc_bytes];
    f.read_exact_at(&mut before, 0)?;
    let off = BOOT_CONTROL_OFFSET as usize;
    let block: [u8; 32] = before[off..off + 32].try_into()?;
    let slots = boot_control(&block)?;
    let Some(new) = mark_slot_a_successful(&block)? else {
        return Ok(format!("Slot A is already successful: {:?}", slots[0]));
    };
    if check {
        return Ok(format!(
            "Would mark slot A successful ({:?}); only its successful bit and the CRC change; slot B {:?} unchanged",
            slots[0], slots[1]
        ));
    }
    let evidence = format!("/run/mobile-recovery/misc-{}.before", j.id);
    fs::write(&evidence, &before)?;
    let mut expected = before.clone();
    expected[off..off + 32].copy_from_slice(&new);
    let mut readback = vec![0; before.len()];
    let result = (|| -> Result<()> {
        f.write_all_at(&new, BOOT_CONTROL_OFFSET)?;
        f.sync_all()?;
        f.read_exact_at(&mut readback, 0)?;
        ensure!(readback == expected, "boot control readback mismatch");
        Ok(())
    })();
    if let Err(e) = result {
        f.write_all_at(&block, BOOT_CONTROL_OFFSET)?;
        f.sync_all()?;
        f.read_exact_at(&mut readback, 0)?;
        ensure!(
            readback == before,
            "CRITICAL: boot control restoration failed; {e}; snapshot {evidence}"
        );
        bail!("{e}; boot control restored; snapshot {evidence}");
    }
    Ok(format!(
        "Slot A marked successful; full misc readback verified; snapshot {evidence}"
    ))
}
fn clear_bcb(j: &Job, check: bool) -> Result<String> {
    bcb(j, check, None)
}
fn bcb(j: &Job, check: bool, request: Option<&[u8]>) -> Result<String> {
    let c = config(j);
    // Qualcomm misc carries its own type GUID; MediaTek misc is a basic data
    // partition, found as the unique "misc" on the configured controller.
    let d = if c.mediatek_a() {
        c.partition(j, "misc")?
    } else {
        c.named(j, "misc")?
    };
    ensure!(
        (c.mediatek_a() || d.entry.kind == "82acc91f-357c-4a68-9c8f-689e1b1a23a1")
            && d.entry.bytes() == c.misc_bytes as u64,
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
/// Whether a restart request writes the BCB (`boot_request = "bcb"`); only
/// then are the slot and partition-table checks of the RAM gate required.
fn reboot_writes(boot_request: &str, action: &str) -> bool {
    boot_request == "bcb" && action != "poweroff"
}
fn reboot(j: &Job, action: &str) -> Result<String> {
    let c = config(j);
    let bcb_request = c.boot_request == "bcb";
    if reboot_writes(&c.boot_request, action) {
        c.ram_gate(j)?;
    } else {
        c.reboot_gate()?;
    }
    if action == "reboot-system" {
        check_installed(j)?;
    }
    j.phase("Rebooting", false)?;
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
    // Let clients see the acknowledgement before the connection drops.
    j.phase(super::protocol::RESTART_PHASE, false)?;
    std::thread::sleep(std::time::Duration::from_millis(500));
    tool(j, "systemctl", &args)?;
    Ok("Restart requested".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn open_rw(disk: &Path) -> File {
        fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(disk)
            .unwrap()
    }
    fn scratch(name: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!("recovery-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir(&base).unwrap();
        base
    }
    #[test]
    fn original_gpt_backup_is_never_overwritten() {
        use super::super::gpt::{write_t880_disk, Gpt};
        let base = scratch("gpt-original");
        let disk = base.join("disk");
        let dir = base.join("gpt-original");
        write_t880_disk(&disk, false);
        let f = open_rw(&disk);
        let size = f.metadata().unwrap().len();
        let g = Gpt::read(&f, size).unwrap();
        assert!(save_gpt_backup(&dir, &f, &g)
            .unwrap()
            .starts_with("Original GPT saved"));
        assert!(!dir.with_extension("partial").exists());
        let original = g.capture(&f).unwrap();
        assert!(save_gpt_backup(&dir, &f, &g)
            .unwrap()
            .contains("already saved"));
        let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 64 << 30).unwrap();
        g.write_plan(&f, &parts, count).unwrap();
        let split = Gpt::read(&f, size).unwrap();
        let err = format!("{:#}", save_gpt_backup(&dir, &f, &split).unwrap_err());
        assert!(err.contains("differs from the disk"), "{err}");
        assert_eq!(
            super::super::gpt::load_snapshot(&dir, &g).unwrap(),
            original
        );
        fs::remove_dir_all(&base).unwrap();
    }
    /// The confirm path of a userdata split without a prior check (the
    /// recovery screen or the on-device CLI, no host): the write saves the
    /// original GPT itself, a matching copy is reused, a different or
    /// unreadable one refuses the write and leaves the disk unchanged.
    fn confirm_path_keeps_the_original(
        name: &str,
        write_disk: impl Fn(&Path),
        split: impl Fn(&super::super::gpt::Gpt, &File) -> Result<()>,
    ) {
        use super::super::gpt::Gpt;
        let base = scratch(name);
        let disk = base.join("disk");
        let dir = base.join("gpt-original");
        write_disk(&disk);
        let f = open_rw(&disk);
        let size = f.metadata().unwrap().len();
        let g = Gpt::read(&f, size).unwrap();
        let original = g.capture(&f).unwrap();
        // No saved copy: the write saves it, then splits.
        let saved =
            write_split_gpt(&dir, &f, &g, &base.join("evidence-1"), |f| split(&g, f)).unwrap();
        assert!(saved.starts_with("Original GPT saved in RAM"), "{saved}");
        assert!(split_epilogue(&saved).contains("restore-gpt"));
        assert_eq!(
            super::super::gpt::load_snapshot(&dir, &g).unwrap(),
            original
        );
        assert_ne!(Gpt::read(&f, size).unwrap(), g);
        // The RAM copy undoes the split (restore-gpt without a host copy).
        let pushed = base.join("gpt-restore");
        assert_eq!(restore_source(&pushed, &dir).unwrap(), dir.as_path());
        let now = Gpt::read(&f, size).unwrap();
        let image = super::super::gpt::load_snapshot(&dir, &now).unwrap();
        let (_, parts) =
            super::super::gpt::image_partitions(&image, super::super::gpt::SECTOR).unwrap();
        rollback_scope(&parts, &now.partitions, false).unwrap();
        super::super::gpt::restore(&f, &image).unwrap();
        assert_eq!(Gpt::read(&f, size).unwrap(), g);
        // A matching saved copy (from a check or the host flow) is reused.
        let saved =
            write_split_gpt(&dir, &f, &g, &base.join("evidence-2"), |f| split(&g, f)).unwrap();
        assert!(saved.contains("already saved"), "{saved}");
        super::super::gpt::restore(&f, &image).unwrap();
        // A saved copy that differs from the disk refuses before any write.
        let table = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .find(|p| {
                p.file_name()
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .starts_with("table-")
            })
            .unwrap();
        let mut bytes = fs::read(&table).unwrap();
        bytes[0] ^= 1;
        fs::write(&table, &bytes).unwrap();
        let err =
            write_split_gpt(&dir, &f, &g, &base.join("evidence-3"), |f| split(&g, f)).unwrap_err();
        let err = format!("{err:#}");
        assert!(err.contains("differs from the disk"), "{err}");
        assert!(!base.join("evidence-3").exists());
        assert_eq!(g.capture(&f).unwrap(), original);
        // An incomplete copy is reported as unreadable, never as missing.
        fs::remove_file(&table).unwrap();
        let err = format!(
            "{:#}",
            write_split_gpt(&dir, &f, &g, &base.join("evidence-4"), |f| split(&g, f)).unwrap_err()
        );
        assert!(err.contains("cannot be read"), "{err}");
        assert_eq!(g.capture(&f).unwrap(), original);
        // Without any copy restore-gpt names both sources.
        fs::remove_dir_all(&dir).unwrap();
        let err = format!("{:#}", restore_source(&pushed, &dir).unwrap_err());
        assert!(err.contains("no saved original GPT"), "{err}");
        fs::create_dir(&pushed).unwrap();
        assert_eq!(restore_source(&pushed, &dir).unwrap(), pushed.as_path());
        fs::remove_dir_all(&base).unwrap();
    }
    #[test]
    fn qualcomm_ab_split_saves_the_original_gpt_without_a_check() {
        confirm_path_keeps_the_original(
            "ab-gpt",
            |p| {
                super::super::gpt::tests::write_marble_lun0(p);
            },
            |g, f| {
                let parts = g.split_keeping(1 << 30, 16 << 30, 64 << 30)?;
                let summary = plan_summary(g, &parts);
                assert!(summary.contains("Plan: userdata"), "{summary}");
                assert!(summary.contains("Plan: new linux "), "{summary}");
                g.write_split(f, &parts)
            },
        );
    }
    #[test]
    fn mediatek_split_saves_the_original_gpt_without_a_check() {
        confirm_path_keeps_the_original(
            "mediatek-gpt",
            |p| super::super::gpt::write_t880_disk(p, false),
            |g, f| {
                let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 64 << 30)?;
                let summary = plan_summary(g, &parts);
                g.write_plan(f, &parts, count)
            },
        );
    }
    #[test]
    fn linux_only_rollback_requires_the_original_userdata_span() {
        use super::super::gpt::Gpt;
        let base = scratch("linux-only-rollback");
        let disk = base.join("disk");
        super::super::gpt::tests::write_marble_lun0(&disk);
        let f = open_rw(&disk);
        let g = Gpt::read(&f, f.metadata().unwrap().len()).unwrap();
        let parts = g.linux_only(1 << 30, 16 << 30).unwrap();
        let backup = base.join("original");
        let evidence = base.join("evidence");
        write_split_gpt(&backup, &f, &g, &evidence, |f| g.write_split(f, &parts)).unwrap();
        let now = Gpt::read(&f, f.metadata().unwrap().len()).unwrap();
        rollback_scope(&g.partitions, &now.partitions, true).unwrap();
        assert!(rollback_scope(&g.partitions, &now.partitions, false).is_err());
        let mut wrong = now.partitions.clone();
        wrong
            .iter_mut()
            .find(|p| p.name == "linux-boot")
            .unwrap()
            .start += 256;
        assert!(rollback_scope(&g.partitions, &wrong, true).is_err());
        let mut foreign = now.partitions.clone();
        foreign.iter_mut().find(|p| p.name == "super").unwrap().end -= 256;
        assert!(rollback_scope(&g.partitions, &foreign, true).is_err());
        fs::remove_dir_all(&base).unwrap();
    }
    #[test]
    fn ab_rollback_scope_only_accepts_the_userdata_span() {
        use super::super::gpt::{image_partitions, load_snapshot, Gpt, SECTOR};
        let base = scratch("ab-rollback");
        let disk = base.join("disk");
        let dir = base.join("gpt-original");
        super::super::gpt::tests::write_marble_lun0(&disk);
        let f = open_rw(&disk);
        let size = f.metadata().unwrap().len();
        let g = Gpt::read(&f, size).unwrap();
        save_gpt_backup(&dir, &f, &g).unwrap();
        let parts = g.split_keeping(1 << 30, 16 << 30, 64 << 30).unwrap();
        g.write_split(&f, &parts).unwrap();
        let split = Gpt::read(&f, size).unwrap();
        let image = load_snapshot(&dir, &split).unwrap();
        let (_, original) = image_partitions(&image, SECTOR).unwrap();
        assert_eq!(original, g.partitions);
        let user = rollback_scope(&original, &split.partitions, false).unwrap();
        assert_eq!(user, g.partition("userdata").unwrap());
        let mut other = original.clone();
        other.iter_mut().find(|p| p.name == "super").unwrap().end -= 256;
        assert!(rollback_scope(&other, &split.partitions, false).is_err());
        let mut foreign = split.partitions.clone();
        foreign.iter_mut().find(|p| p.name == "linux").unwrap().name = "data2".into();
        assert!(rollback_scope(&original, &foreign, false).is_err());
        fs::remove_dir_all(&base).unwrap();
    }
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
        valid_fat_identity("BOOT", None).unwrap();
        valid_fat_identity("BOOT", Some("ABCD-1234")).unwrap();
        for (label, volume) in [
            ("", None),
            ("lowercase", None),
            ("TOO_LONG_LABEL", None),
            ("BOOT", Some("ABCD1234")),
            ("BOOT", Some("ABCD-12345")),
            ("BOOT", Some("ABCD-12G4")),
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
            vec!["prepare-install", "--android-userdata", "--check"],
            vec!["prepare-install", "--android-userdata", "64", "--check"],
            vec!["prepare-install", "--android-userdata", "64G", "--confirm"],
            vec![
                "prepare-install",
                "--size",
                "64G",
                "--confirm-erase-userdata",
            ],
            vec!["prepare-install", "--check", "--android-userdata", "64G"],
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
        for flag in ["--check", "--confirm-erase-userdata"] {
            assert!(validate(
                &["prepare-install", "--android-userdata", "128G", flag].map(String::from),
                false
            )
            .is_ok());
        }
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
            boot_label: "BOOT".into(),
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
    fn fat_check_tolerates_only_the_fsinfo_free_count() {
        let clean = "fsck.fat 4.2 (2021-01-31)\n/dev/sda34: 12 files, 3/245476 clusters\n";
        assert!(!fat_hint_only(clean).unwrap());
        // Marble t15: U-Boot's FAT writes left the FSInfo count one off.
        let hint = "fsck.fat 4.2 (2021-01-31)\nFree cluster summary wrong (245474 vs. really 245473)\n  Auto-correcting.\n\nLeaving filesystem unchanged.\n/dev/sda34: 19 files, 3/245476 clusters\n";
        assert!(fat_hint_only(hint).unwrap());
        for other in [
            "Dirty bit is set. Fs was not properly unmounted and some data may be corrupt.\n 1) Remove dirty bit\n",
            "/EFI/nixos/x.efi\n  File size is 10 bytes, cluster chain length is 0 bytes.\n  Truncating file to 0 bytes.\n",
            "There are differences between boot sector and its backup.\n",
        ] {
            let text = hint.replace("  Auto-correcting.\n", &format!("  Auto-correcting.\n{other}"));
            assert!(fat_hint_only(&text).is_err(), "{text}");
        }
        let unknown = "fsck.fat 4.2 (2021-01-31)\n\nLeaving filesystem unchanged.\n/dev/sda34: 19 files, 3/245476 clusters\n";
        assert!(fat_hint_only(unknown).is_err());
    }
    #[test]
    fn reboot_without_bcb_write_skips_the_slot_gate() {
        for action in [
            "reboot-system",
            "reboot-recovery",
            "reboot-bootloader",
            "poweroff",
        ] {
            assert!(!reboot_writes("argument", action));
            assert_eq!(reboot_writes("bcb", action), action != "poweroff");
        }
    }
    #[test]
    fn initial_resume_requires_pending_same_profile_and_no_other_job() {
        let root = std::env::temp_dir().join(format!("recovery-resume-{}", std::process::id()));
        let system = "/nix/store/00000000000000000000000000000000-nixos-system-test-1";
        let other = "/nix/store/11111111111111111111111111111111-other";
        let mut entries = BTreeMap::new();
        entries.insert(system.to_string(), String::new());
        fs::create_dir_all(root.join("nix/var/nix/profiles")).unwrap();
        fs::create_dir_all(root.join("var/lib/mobile-efi-preparation")).unwrap();
        let marker = root.join("var/lib/mobile-efi-preparation/pending");
        let resume_initial =
            |root: &Path, system: &str| super::resume_initial(root, system, &entries);
        assert!(resume_initial(&root, system).is_err());
        fs::write(&marker, "First installation incomplete\n").unwrap();
        // No profile and no transferred system.
        assert!(resume_initial(&root, system).is_err());
        fs::create_dir_all(root.join(system.trim_start_matches('/'))).unwrap();
        // No profile yet (failure after the transfer): only declared objects.
        resume_initial(&root, system).unwrap();
        // Nix's dedup directory and lock files of declared objects are not
        // store objects; a .links symlink or a foreign lock file still refuses.
        let store = root.join("nix/store");
        fs::create_dir_all(store.join(".links")).unwrap();
        fs::write(store.join(".links/0abc"), b"x").unwrap();
        fs::write(store.join(format!("{}.lock", &system[11..])), b"").unwrap();
        resume_initial(&root, system).unwrap();
        fs::write(
            store.join("11111111111111111111111111111111-other.lock"),
            b"",
        )
        .unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_file(store.join("11111111111111111111111111111111-other.lock")).unwrap();
        fs::remove_dir_all(store.join(".links")).unwrap();
        std::os::unix::fs::symlink("/", store.join(".links")).unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_file(store.join(".links")).unwrap();
        fs::create_dir(store.join(".lock")).unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_dir(store.join(".lock")).unwrap();
        fs::create_dir_all(root.join(other.trim_start_matches('/'))).unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_dir(root.join(other.trim_start_matches('/'))).unwrap();
        std::os::unix::fs::symlink(other, root.join("nix/var/nix/profiles/system")).unwrap();
        assert!(resume_initial(&root, system).is_err());
        fs::remove_file(root.join("nix/var/nix/profiles/system")).unwrap();
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
            let args = ["install-initial-system", "m", "r", system, "4096", flag].map(String::from);
            assert!(validate(&args, false).is_ok());
            assert!(validate(&args, true).is_err());
        }
        let old_args = ["install-initial", "m", "r", system, "4096", "--confirm"].map(String::from);
        assert!(validate(&old_args, true).is_err());
        let args = [
            "install-initial-system",
            "m",
            "r",
            system,
            "4096",
            "--confirm",
        ]
        .map(String::from);
        assert!(validate(&args, true).is_ok());
        assert!(validate(&args, false).is_err());
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

    #[test]
    fn ram_only_slot_model_has_no_recovery_update_capability() {
        let mediatek = Config {
            slot_model: "mediatek-a".into(),
            ..Config::default()
        };
        assert!(!capabilities(&mediatek)
            .iter()
            .any(|a| a == "update-recovery"));
        assert!(capabilities(&Config {
            slot_model: "ab".into(),
            ..Config::default()
        })
        .iter()
        .any(|a| a == "update-recovery"));
    }
    #[test]
    fn t880_check_prints_the_exact_split() {
        let path = std::env::temp_dir().join(format!("recovery-t880-plan-{}", std::process::id()));
        super::super::gpt::write_t880_disk(&path, false);
        let file = File::open(&path).unwrap();
        let g = super::super::gpt::Gpt::read(&file, file.metadata().unwrap().len()).unwrap();
        let (parts, count) = g.split_userdata(1 << 30, 16 << 30, 64 << 30).unwrap();
        let text = describe_split(&g, &parts, count, Path::new("/dev/sdc")).unwrap();
        assert!(text.contains("GPT entries: 82 -> 84"));
        assert!(text.contains("81 other entries unchanged"));
        for name in ["userdata", "linux-boot", "linux "] {
            assert!(text.contains(name), "{name}\n{text}");
        }
        assert!(text.contains("end 62410743 ->"));
        assert_eq!(text.lines().filter(|l| l.ends_with(" new")).count(), 2);
        assert!(!text.contains("super "));
        drop(file);
        let _ = fs::remove_file(&path);
    }
}
