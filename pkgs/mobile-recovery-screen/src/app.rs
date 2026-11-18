use crate::canvas::Canvas;
use crate::device;
use crate::device::Profile;
#[cfg(feature = "backlight-control")]
use crate::display::Backlight;
use crate::display::Console;
use crate::input::{discover_inputs, poll_inputs};
use crate::menu::Menu;
use crate::render::render;
use crate::status::{StatusSocket, UpdateStatus};
use std::fs::{self, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

fn usb_state() -> String {
    let Ok(entries) = fs::read_dir("/sys/class/udc") else {
        return "USB: controller unavailable".into();
    };
    for entry in entries.flatten() {
        if let Ok(state) = fs::read_to_string(entry.path().join("state")) {
            let status = format!("USB link: {}", state.trim());
            #[cfg(feature = "ab-partitions")]
            if let Some(slot) = crate::capabilities::ab::running_slot() {
                return format!("{status}   Boot slot: {slot}");
            }
            return status;
        }
    }
    "USB: waiting for controller".into()
}
fn journal_log() -> String {
    match Command::new("/bin/journalctl")
        .args([
            "-b",
            "-p",
            "warning",
            "-n",
            "80",
            "--no-pager",
            "-o",
            "short-monotonic",
        ])
        .output()
    {
        Ok(output) if output.status.success() => {
            let log = String::from_utf8_lossy(&output.stdout).into_owned();
            if log.trim().is_empty() {
                "No warning or more severe messages".into()
            } else {
                log
            }
        }
        Ok(output) => format!("Could not read journal: {}", output.status),
        Err(error) => format!("Could not read journal: {error}"),
    }
}
fn preview_dimensions() -> io::Result<(usize, usize)> {
    let value = std::env::var("MOBILE_RECOVERY_PREVIEW_SIZE").unwrap_or_else(|_| "50x40".into());
    let (width, height) = value
        .split_once('x')
        .ok_or_else(|| io::Error::other("preview size must be WIDTHxHEIGHT"))?;
    let width: usize = width
        .parse()
        .map_err(|_| io::Error::other("invalid preview width"))?;
    let height: usize = height
        .parse()
        .map_err(|_| io::Error::other("invalid preview height"))?;
    if !(40..=240).contains(&width) || !(32..=160).contains(&height) {
        return Err(io::Error::other(
            "preview size must be 40..240 columns and 32..160 rows",
        ));
    }
    Ok((width, height))
}
/// The result of the read-only `prepare-install --check` the screen runs to
/// list the Android userdata sizes.
pub(crate) const LINUX_ONLY_CHOICE: &str = "All userdata (erase Android)";

pub(crate) struct UserdataCheck {
    pub choices: Result<Vec<String>, String>,
    /// The daemon task of the check ("Recovery task N" on stderr).
    pub task: Option<u64>,
}
/// The daemon task of a client run ("Recovery task N" on stderr).
fn client_task(text: &str) -> Option<u64> {
    text.lines()
        .find_map(|l| l.strip_prefix("Recovery task "))
        .and_then(|id| id.trim().parse().ok())
}
/// The last error line of a client run.
fn client_error(text: &str) -> Option<&str> {
    text.lines()
        .rev()
        .find(|l| l.starts_with("ERROR:") || l.starts_with("recovery:"))
}
/// Android userdata sizes the daemon offers for this disk
/// ("Android userdata choices: 64G 128G", or "none").
pub(crate) fn parse_userdata_check(text: &str, success: bool) -> UserdataCheck {
    let task = client_task(text);
    let mut choices: Vec<String> = text
        .lines()
        .find_map(|l| l.strip_prefix("Android userdata choices:"))
        .map(|l| {
            l.split_whitespace()
                .filter(|c| *c != "none")
                .map(String::from)
                .collect()
        })
        .unwrap_or_default();
    if text
        .lines()
        .any(|l| l == "Linux-only layout: entire userdata")
    {
        choices = vec![LINUX_ONLY_CHOICE.into()];
    }
    let choices = if success && !choices.is_empty() {
        Ok(choices)
    } else {
        Err(client_error(text)
            .unwrap_or("No Android userdata size is available")
            .into())
    };
    UserdataCheck { choices, task }
}
/// The plan of the chosen size from `prepare-install --android-userdata
/// SIZE --check` (its "Plan: " lines), shown before the final confirmation.
pub(crate) fn parse_plan_check(text: &str, success: bool) -> UserdataCheck {
    let plan: Vec<String> = text
        .lines()
        .filter_map(|l| l.strip_prefix("Plan: "))
        .map(String::from)
        .collect();
    UserdataCheck {
        choices: if success && !plan.is_empty() {
            Ok(plan)
        } else {
            Err(client_error(text)
                .unwrap_or("The recovery did not report a plan for this size")
                .into())
        },
        task: client_task(text),
    }
}
fn run_check(args: &[&str], parse: fn(&str, bool) -> UserdataCheck) -> UserdataCheck {
    match Command::new("/bin/recovery").args(args).output() {
        Ok(output) => parse(
            &(String::from_utf8_lossy(&output.stdout).into_owned()
                + &String::from_utf8_lossy(&output.stderr)),
            output.status.success(),
        ),
        Err(e) => UserdataCheck {
            choices: Err(e.to_string()),
            task: None,
        },
    }
}
/// What the result view shows after an action exits: its output tail on
/// success (the next steps), else its error line.
pub(crate) fn action_result(contents: &str, success: bool, status: &str) -> String {
    if success {
        let lines: Vec<&str> = contents
            .lines()
            .filter(|l| !l.starts_with("Recovery task ") && !l.trim().is_empty())
            .collect();
        if lines.is_empty() {
            format!("Action returned: {status}")
        } else {
            lines.join("\n")
        }
    } else {
        client_error(contents)
            .map(String::from)
            .unwrap_or_else(|| format!("Action returned: {status}"))
    }
}
/// Whether a daemon task shown by the status watch takes over the screen
/// (the update view, cancelling a pending choice or confirmation). The
/// screen's own read-only size check is a daemon task too; it must not
/// close the size picker it is filling.
pub(crate) fn task_takes_over(session: u64, last: u64, own_check: Option<u64>) -> bool {
    session != last && Some(session) != own_check
}
pub(crate) fn prepare_args(chosen: &str, confirm: bool) -> Vec<&str> {
    let flag = if confirm {
        "--confirm-erase-userdata"
    } else {
        "--check"
    };
    if chosen == LINUX_ONLY_CHOICE {
        vec![device::PREPARE_INSTALL, flag]
    } else {
        vec![device::PREPARE_INSTALL, "--android-userdata", chosen, flag]
    }
}
fn start_action(
    cfg: &Profile,
    action: &str,
    chosen: Option<&str>,
    id: u64,
) -> io::Result<(Child, PathBuf)> {
    let path = PathBuf::from(format!(
        "/tmp/{}-recovery-action.{}.{}",
        cfg.id,
        std::process::id(),
        id
    ));
    let output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)?;
    let mut command = Command::new("/bin/recovery");
    command.arg(action);
    if action == device::PREPARE_INSTALL {
        let size = chosen.ok_or_else(|| io::Error::other("no Android userdata size chosen"))?;
        command.args(&prepare_args(size, true)[1..]);
    } else {
        command.arg("--confirm");
    }
    let child = command
        .stdout(Stdio::from(output.try_clone()?))
        .stderr(Stdio::from(output))
        .spawn()?;
    Ok((child, path))
}
pub(crate) fn run() -> io::Result<()> {
    let args: Vec<_> = std::env::args_os().collect();
    let preview = args.get(1).is_some_and(|s| s == "--preview");
    let output = if preview && args.len() == 3 {
        Some(Path::new(&args[2]))
    } else if !preview && args.len() == 1 {
        None
    } else {
        return Err(io::Error::other(
            "usage: mobile-recovery-screen [--preview OUTPUT.txt]",
        ));
    };
    let cfg = device::profile();
    let mut menu = Menu {
        choice_item: cfg
            .items
            .iter()
            .position(|i| i.action == Some(device::PREPARE_INSTALL)),
        ..Default::default()
    };
    if preview {
        match std::env::var("MOBILE_RECOVERY_PREVIEW_STATE").as_deref() {
            Ok("confirm") => {
                menu.selected = 1.min(cfg.items.len() - 1);
                menu.confirming = true;
            }
            Ok(state @ ("choose" | "confirm-choice")) if menu.choice_item.is_some() => {
                menu.selected = menu.choice_item.unwrap();
                menu.choosing = true;
                menu.choices = vec!["64G".into(), "128G".into()];
                menu.confirming = state == "confirm-choice";
                if menu.confirming {
                    menu.plan = vec![
                        "userdata 224.6 -> 64.0 GiB (Android, erased)".into(),
                        "new linux-boot 1.0 GiB".into(),
                        "new linux 159.6 GiB".into(),
                    ];
                }
            }
            Ok("error") => menu.error = true,
            Ok("done") => {
                menu.error = true;
                menu.succeeded = true;
            }
            Ok("log") => menu.logs = true,
            Ok("update") => menu.updates = true,
            _ => {}
        }
        let (width, height) = preview_dimensions()?;
        let mut canvas = Canvas::new(width, height);
        let preview_log = std::env::var_os("MOBILE_RECOVERY_PREVIEW_LOG")
            .map(fs::read_to_string)
            .transpose()?
            .unwrap_or_else(|| "Preview warning: USB ready".into());
        let mut preview_update = UpdateStatus::default();
        if menu.updates {
            preview_update.active = true;
            preview_update.stage = "Copying Nix store".into();
            preview_update.done_paths = 37;
            preview_update.total_paths = 124;
            preview_update.path_bytes = 12 * 1048576;
            preview_update.path_total = 128 * 1048576;
            preview_update.logs = (0..80)
                .map(|i| format!("Copying path {i}: /nix/store/example-package-with-a-long-name"))
                .collect();
        }
        render(
            &mut canvas,
            cfg,
            &menu,
            "ERROR: action failed",
            &preview_log,
            "USB link: configured",
            true,
            &preview_update,
        );
        return canvas.save(output.unwrap());
    }
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open("/tmp/mobile-recovery-screen.lock")?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } < 0 {
        return Err(io::Error::other("screen already running"));
    }
    unsafe {
        libc::signal(libc::SIGTERM, stop as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, stop as *const () as libc::sighandler_t);
    }
    let mut console = Console::open()?;
    let mut canvas = Canvas::new(console.columns, console.rows);
    let mut inputs = Vec::new();
    let mut child: Option<(Child, PathBuf)> = None;
    let mut action_id = 0u64;
    let mut failure = String::new();
    #[cfg(feature = "refresh-panel")]
    let mut refreshed = false;
    #[cfg(feature = "backlight-control")]
    let mut backlight = None;
    let mut log_cache = Some(journal_log());
    let mut last_log_refresh = Instant::now();
    let mut usb = String::new();
    let mut redraw = true;
    let mut status_socket = StatusSocket::open()?;
    let mut last_update_session = status_socket.status.session_id;
    let mut own_check = None;
    while !STOP.load(Ordering::Relaxed) {
        redraw |= discover_inputs(&mut inputs);
        let current_usb = usb_state();
        if current_usb != usb {
            usb = current_usb;
            redraw = true;
        }
        if last_log_refresh.elapsed() >= Duration::from_secs(10) {
            let current_log = journal_log();
            if log_cache.as_deref() != Some(current_log.as_str()) {
                log_cache = Some(current_log);
                redraw = true;
            }
            last_log_refresh = Instant::now();
        }
        if redraw {
            render(
                &mut canvas,
                cfg,
                &menu,
                &failure,
                log_cache.as_deref().unwrap_or(""),
                &usb,
                !inputs.is_empty(),
                &status_socket.status,
            );
            console.show(&canvas)?;
            #[cfg(feature = "refresh-panel")]
            if !refreshed {
                console.force_refresh()?;
                // Some DSI fbdev scanout paths discard the first frame while
                // the blank cycle restores the panel. Submit it again after
                // the forced modeset so the visible buffer contains this UI.
                console.show(&canvas)?;
                refreshed = true;
            }
            #[cfg(feature = "backlight-control")]
            if backlight.is_none() {
                if let Some(setting) = &cfg.backlight {
                    backlight = Some(Backlight::enable(Path::new(setting.path), setting.level)?);
                }
            }
            redraw = false;
        }
        let event = poll_inputs(
            &mut inputs,
            &mut menu,
            cfg.items.len(),
            if child.is_some() { 100 } else { 1000 },
            &status_socket.fds(),
            status_socket.status.active,
            || console.blanked(),
        )?;
        if event.wake {
            console.unblank()?;
            redraw = true;
        }
        redraw |= event.redraw;
        redraw |= status_socket.handle(&event.extra_ready)?;
        if task_takes_over(
            status_socket.status.session_id,
            last_update_session,
            own_check,
        ) {
            menu.updates = true;
            menu.logs = false;
            menu.confirming = false;
            menu.choosing = false;
            menu.yes = false;
            menu.error = false;
            menu.suppress_actions();
        }
        last_update_session = status_socket.status.session_id;
        if menu.choosing && menu.choices.is_empty() && !menu.error {
            let check = run_check(&[device::PREPARE_INSTALL, "--check"], parse_userdata_check);
            own_check = check.task.or(own_check);
            match check.choices {
                Ok(choices) => menu.choices = choices,
                Err(err) => {
                    failure = err;
                    menu.choosing = false;
                    menu.error = true;
                }
            }
            redraw = true;
        }
        if !menu.confirming {
            menu.plan.clear();
        }
        if let Some(size) = menu.chosen().map(String::from) {
            if menu.plan.is_empty() && !menu.error {
                let check = run_check(&prepare_args(&size, false), parse_plan_check);
                own_check = check.task.or(own_check);
                match check.choices {
                    Ok(plan) => menu.plan = plan,
                    Err(err) => {
                        failure = err;
                        menu.choosing = false;
                        menu.confirming = false;
                        menu.error = true;
                    }
                }
                redraw = true;
            }
        }
        if let Some(index) = event.action {
            if let Some(action) = cfg.items[index].action {
                action_id += 1;
                let chosen = menu.chosen().map(String::from);
                menu.choosing = false;
                match start_action(cfg, action, chosen.as_deref(), action_id) {
                    Ok(started) => child = Some(started),
                    Err(err) => {
                        failure = err.to_string();
                        menu.busy = false;
                        menu.error = true;
                    }
                }
            }
            redraw = true;
        }
        if let Some((running, path)) = child.as_mut() {
            if let Some(status) = running.try_wait()? {
                failure = action_result(
                    &fs::read_to_string(path).unwrap_or_default(),
                    status.success(),
                    &status.to_string(),
                );
                child = None;
                menu.busy = false;
                menu.error = true;
                menu.succeeded = status.success();
                menu.suppress_actions();
                redraw = true;
            }
        }
    }
    Ok(())
}
