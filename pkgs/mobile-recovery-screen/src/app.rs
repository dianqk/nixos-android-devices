use crate::canvas::Canvas;
use crate::device;
use crate::device::Profile;
#[cfg(feature = "backlight-control")]
use crate::display::Backlight;
use crate::display::Framebuffer;
use crate::input::{discover_inputs, poll_inputs};
use crate::menu::Menu;
use crate::render::render;
use crate::status::{StatusSocket, UpdateStatus};
use fontdue::{Font, FontSettings};
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
    let value =
        std::env::var("MOBILE_RECOVERY_PREVIEW_SIZE").unwrap_or_else(|_| "1080x2160".into());
    let (width, height) = value
        .split_once('x')
        .ok_or_else(|| io::Error::other("preview size must be WIDTHxHEIGHT"))?;
    let width: usize = width
        .parse()
        .map_err(|_| io::Error::other("invalid preview width"))?;
    let height: usize = height
        .parse()
        .map_err(|_| io::Error::other("invalid preview height"))?;
    if !(320..=4096).contains(&width) || !(320..=4096).contains(&height) {
        return Err(io::Error::other(
            "preview size must be 320..4096 on each axis",
        ));
    }
    Ok((width, height))
}
fn start_action(cfg: &Profile, action: &str, id: u64) -> io::Result<(Child, PathBuf)> {
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
    let child = Command::new("/bin/recovery")
        .arg(action)
        .arg("--confirm")
        .stdout(Stdio::from(output.try_clone()?))
        .stderr(Stdio::from(output))
        .spawn()?;
    Ok((child, path))
}
pub(crate) fn run() -> io::Result<()> {
    let args: Vec<_> = std::env::args_os().collect();
    let preview = args.get(1).is_some_and(|s| s == "--preview");
    let (font_path, output) = if preview && args.len() == 4 {
        (Path::new(&args[2]), Some(Path::new(&args[3])))
    } else if !preview && args.len() == 2 {
        (Path::new(&args[1]), None)
    } else {
        return Err(io::Error::other(
            "usage: mobile-recovery-screen [--preview] FONT [OUTPUT.ppm]",
        ));
    };
    let cfg = device::profile();
    let font = Font::from_bytes(fs::read(font_path)?, FontSettings::default())
        .map_err(io::Error::other)?;
    let percent = std::env::var("MOBILE_RECOVERY_FONT_PERCENT")
        .unwrap_or_else(|_| "100".into())
        .parse::<u32>()
        .map_err(|_| io::Error::other("font percent must be 75..150"))?;
    if !(75..=150).contains(&percent) {
        return Err(io::Error::other("font percent must be 75..150"));
    }
    let mut menu = Menu::default();
    if preview {
        match std::env::var("MOBILE_RECOVERY_PREVIEW_STATE").as_deref() {
            Ok("confirm") => {
                menu.selected = 1.min(cfg.items.len() - 1);
                menu.confirming = true;
            }
            Ok("error") => menu.error = true,
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
            &font,
            cfg,
            &menu,
            "ERROR: action failed",
            &preview_log,
            "USB link: configured",
            true,
            percent as f32 / 100.0,
            &preview_update,
        );
        return canvas.ppm(output.unwrap());
    }
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .open("/tmp/mobile-recovery-screen.lock")?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } < 0 {
        return Err(io::Error::other("screen already running"));
    }
    unsafe {
        libc::signal(libc::SIGTERM, stop as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, stop as *const () as libc::sighandler_t);
    }
    let mut fb = Framebuffer::open()?;
    let mut canvas = Canvas::new(fb.var.xres as usize, fb.var.yres as usize);
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
                &font,
                cfg,
                &menu,
                &failure,
                log_cache.as_deref().unwrap_or(""),
                &usb,
                !inputs.is_empty(),
                percent as f32 / 100.0,
                &status_socket.status,
            );
            fb.show(&canvas);
            #[cfg(feature = "refresh-panel")]
            if !refreshed {
                fb.force_refresh()?;
                // Some DSI fbdev scanout paths discard the first frame while
                // the blank cycle restores the panel. Submit it again after
                // the forced modeset so the visible buffer contains this UI.
                fb.show(&canvas);
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
        );
        redraw |= event.redraw;
        redraw |= status_socket.handle(&event.extra_ready)?;
        if status_socket.status.session_id != last_update_session {
            menu.updates = true;
            menu.logs = false;
            menu.confirming = false;
            menu.yes = false;
            menu.error = false;
            menu.reset_keys();
            last_update_session = status_socket.status.session_id;
        }
        if let Some(index) = event.action {
            if let Some(action) = cfg.items[index].action {
                action_id += 1;
                match start_action(cfg, action, action_id) {
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
                failure = format!("Action returned: {status}");
                if let Ok(contents) = fs::read_to_string(path) {
                    if let Some(line) = contents
                        .lines()
                        .rev()
                        .find(|line| line.starts_with("ERROR:"))
                    {
                        failure = line.into();
                    }
                }
                child = None;
                menu.busy = false;
                menu.error = true;
                menu.reset_keys();
                redraw = true;
            }
        }
    }
    Ok(())
}
