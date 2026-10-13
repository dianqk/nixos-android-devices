use crate::canvas::Canvas;
use crate::device;
use crate::display::{font_width, VarScreen};
use crate::input::{poll_inputs, Input, InputEvent, EV_KEY};
use crate::menu::{Menu, KEY_POWER, KEY_VOLUMEDOWN, KEY_VOLUMEUP};
use crate::render::{log_tail, render, wrap_log};
use crate::status::UpdateStatus;
use std::fs::File;
use std::mem::{size_of, zeroed};
use std::os::fd::{AsRawFd, FromRawFd};
use std::path::PathBuf;
use std::time::{Duration, Instant};

fn press(m: &mut Menu, key: u16, count: usize) -> Option<usize> {
    let start = Instant::now();
    m.key(key, 1, start, count);
    m.key(key, 0, start + Duration::from_millis(100), count)
}
#[test]
fn confirmations_and_log() {
    let mut m = Menu::default();
    assert_eq!(press(&mut m, KEY_POWER, 4), None);
    assert!(m.logs);
    press(&mut m, KEY_POWER, 4);
    assert!(!m.logs);
    press(&mut m, KEY_VOLUMEDOWN, 4);
    press(&mut m, KEY_POWER, 4);
    assert!(m.confirming && !m.yes);
    press(&mut m, KEY_VOLUMEUP, 4);
    assert_eq!(press(&mut m, KEY_POWER, 4), Some(1));
    assert!(m.busy);
}
#[test]
fn long_chord_and_repeat_do_not_act() {
    let mut m = Menu::default();
    let t = Instant::now();
    m.key(KEY_POWER, 1, t, 4);
    m.key(KEY_POWER, 2, t, 4);
    m.key(KEY_POWER, 0, t + Duration::from_secs(2), 4);
    assert!(!m.logs);
    m.key(KEY_POWER, 1, t, 4);
    m.key(KEY_VOLUMEUP, 1, t, 4);
    m.key(KEY_POWER, 0, t + Duration::from_millis(100), 4);
    m.key(KEY_VOLUMEUP, 0, t + Duration::from_millis(100), 4);
    assert!(!m.logs && m.selected == 0);
}

#[test]
fn linux_framebuffer_and_input_layout() {
    assert_eq!(size_of::<VarScreen>(), 160);
    assert_eq!(size_of::<InputEvent>(), 24);
}

#[test]
fn device_profile_matches_compiled_feature() {
    let profile = device::profile();
    assert_eq!(profile.items[0].action, None);
    {
        assert_eq!(
            profile.item_label(&profile.items[1]),
            profile.boot_system_label
        );
        assert_eq!(profile.items[1].action, Some("reboot-system"));
    }
    assert!(profile
        .items
        .iter()
        .skip(1)
        .all(|item| item.action.is_some()));
}

#[test]
fn canvas_starts_blank() {
    let canvas = Canvas::new(8, 4);
    assert!(canvas.cells.iter().all(|cell| *cell == b' '));
}

#[test]
fn fixed_column_log_wrapping() {
    assert_eq!(
        wrap_log("short\nABCDEFGHIJKLM\n\txyz", 5),
        ["short", "ABCDE", "FGHIJ", "KLM", " xyz"]
    );
    assert_eq!(
        log_tail("first message\nsecond line", 6, 3),
        ["e", "second", " line"]
    );
}

#[test]
fn idle_input_does_not_request_a_redraw() {
    let mut inputs = Vec::new();
    let mut menu = Menu::default();
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], false);
    assert!(!result.redraw);
    assert!(result.action.is_none());
}

#[test]
fn active_update_discards_pending_confirmation_key() {
    let mut pipe = [0; 2];
    assert_eq!(
        unsafe { libc::pipe2(pipe.as_mut_ptr(), libc::O_NONBLOCK) },
        0
    );
    let input = unsafe { File::from_raw_fd(pipe[0]) };
    let output = unsafe { File::from_raw_fd(pipe[1]) };
    let mut inputs = vec![Input {
        file: input,
        path: PathBuf::from("test-input"),
        dropped: false,
    }];
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        held: 1 << 2,
        ..Menu::default()
    };
    menu.pressed[2] = Some(Instant::now() - Duration::from_millis(100));
    let release = InputEvent {
        time: unsafe { zeroed() },
        kind: EV_KEY,
        code: KEY_POWER,
        value: 0,
    };
    assert_eq!(
        unsafe {
            libc::write(
                output.as_raw_fd(),
                (&release as *const InputEvent).cast(),
                size_of::<InputEvent>(),
            )
        },
        size_of::<InputEvent>() as isize
    );
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], true);
    assert!(result.action.is_none());
    assert!(!menu.busy);
    assert_eq!(menu.held, 0);
}

// Reconstruct actual emitted VT writes, checking coordinates and controls.
fn apply_output(screen: &mut [u8], width: usize, output: &[u8]) {
    let mut offset = 0;
    let mut pos = 0;
    while offset < output.len() {
        if output[offset] == 27 {
            assert_eq!(output[offset + 1], b'[');
            let end = offset + output[offset..].iter().position(|b| *b == b'H').unwrap();
            let coords = std::str::from_utf8(&output[offset + 2..end]).unwrap();
            let (y, x) = coords.split_once(';').unwrap();
            let (y, x): (usize, usize) = (y.parse().unwrap(), x.parse().unwrap());
            assert!(y >= 1 && y <= screen.len() / width);
            assert!(x >= 1 && x <= width);
            pos = (y - 1) * width + x - 1;
            offset = end + 1;
        } else {
            assert!((32..=126).contains(&output[offset]));
            screen[pos] = output[offset];
            pos += 1;
            offset += 1;
        }
    }
}
#[test]
fn console_geometry_covers_devices() {
    for (width, height) in [(1600, 2560), (3048, 2032), (1200, 1920), (1080, 2160)] {
        let font = font_width(width, height).unwrap();
        assert!((40..=240).contains(&(width / font)));
        assert!((32..=160).contains(&(height / (font * 2))));
    }
    assert!(font_width(0, 0).is_err());
    assert!(font_width(200, 300).is_err());
}
#[test]
fn all_pages_roundtrip_through_incremental_vt_output() {
    for (width, height) in [(40, 32), (45, 45), (50, 40), (127, 42)] {
        let mut canvas = Canvas::new(width, height);
        let mut previous = vec![0; width * height];
        let mut screen = vec![b' '; width * height];
        let cfg = device::profile();
        let mut menu = Menu::default();
        let mut update = UpdateStatus::default();
        let log = (0..80)
            .map(|i| format!("warning {i}: {}", "x".repeat(90)))
            .collect::<Vec<_>>()
            .join("\n");
        for state in 0..8 {
            menu.logs = state == 1;
            menu.confirming = state == 2 || state == 3;
            menu.yes = state == 3;
            menu.busy = state == 4;
            menu.error = state == 5;
            menu.updates = state == 6;
            menu.selected = if state == 0 || state == 7 { 0 } else { 1 };
            update.active = state == 6;
            update.total_paths = 10;
            update.done_paths = u64::MAX; // malformed progress cannot overflow or overdraw
            update.logs = log.lines().map(str::to_string).collect();
            render(
                &mut canvas,
                cfg,
                &menu,
                "ERROR: bad \x1b[2J\r\nsecond line",
                &log,
                "USB link: configured",
                true,
                &update,
            );
            let mut output = Vec::new();
            canvas.write_changes(&mut previous, &mut output).unwrap();
            apply_output(&mut screen, width, &output);
            assert_eq!(screen, canvas.cells);
            let text = canvas.text();
            assert!(text.contains("SSH/ACM: recovery help"));
            if menu.confirming {
                assert!(text.contains(if menu.yes { "> Confirm" } else { "> Cancel" }));
            }
            if update.active {
                assert!(text.contains("controls locked"));
            }
            if state == 0 || state == 7 {
                for item in cfg.items {
                    assert!(text.contains(cfg.item_label(item)));
                }
            }
            let mut idle = Vec::new();
            canvas.write_changes(&mut previous, &mut idle).unwrap();
            assert!(idle.is_empty());
        }
    }
}
#[test]
fn text_cannot_inject_terminal_commands() {
    let mut canvas = Canvas::new(40, 32);
    canvas.line(0, "USB\x1b[2J\r\t雪");
    assert!(canvas.text().starts_with("USB?[2J???"));
    assert_eq!(wrap_log("a\x1b[2J雪\t", 40), ["a?[2J? "]);
    assert!(log_tail("abc", 40, 0).is_empty());
    assert_eq!(log_tail("123456789", 4, 2), ["5678", "9"]);
}
#[test]
fn failed_console_write_can_be_retried() {
    struct Broken;
    impl std::io::Write for Broken {
        fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
            Err(std::io::Error::other("broken console"))
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut canvas = Canvas::new(40, 32);
    canvas.line(0, "recovery");
    let mut previous = vec![b' '; 40 * 32];
    assert!(canvas.write_changes(&mut previous, &mut Broken).is_err());
    assert!(previous.iter().all(|c| *c == b' '));
    let mut output = Vec::new();
    canvas.write_changes(&mut previous, &mut output).unwrap();
    assert!(output.ends_with(b"recovery"));
}
