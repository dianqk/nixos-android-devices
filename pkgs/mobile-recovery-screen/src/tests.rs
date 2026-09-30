use crate::canvas::Canvas;
use crate::device;
use crate::display::{FixScreen, VarScreen};
use crate::input::{poll_inputs, Input, InputEvent, EV_KEY};
use crate::menu::{Menu, KEY_POWER, KEY_VOLUMEDOWN, KEY_VOLUMEUP};
use crate::render::{log_layout, log_tail, wrap_log};
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
    assert_eq!(size_of::<FixScreen>(), 80);
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
fn canvas_background_is_pure_black() {
    let canvas = Canvas::new(8, 4);
    assert!(canvas.pixels.iter().all(|pixel| *pixel == 0x000000));
}

#[test]
fn fixed_column_log_wrapping() {
    assert_eq!(
        wrap_log("short\nABCDEFGHIJKLM\n\txyz", 5),
        ["short", "ABCDE", "FGHIJ", "KLM", " xyz"]
    );
    assert_eq!(
        log_tail("first message\nsecond line", 6, 3),
        ["second", " line"]
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

#[test]
fn log_rows_end_before_footer_on_each_device() {
    for (width, height, size) in [
        (1600, 2560, 32.0),
        (3048, 2032, 40.0),
        (1200, 1920, 24.0),
        (1080, 2160, 28.0),
    ] {
        let unit = (width.min(height) as f32 / 27.0).clamp(16.0, 76.0);
        let margin = (unit * 1.1) as i32;
        let start = (unit * 6.3) as i32;
        let footer_first = height - margin - (unit * 2.0) as i32;
        let cell = (size * 0.602_f32).round() as i32;
        let layout = log_layout(width, margin, start, footer_first, unit, size, cell);
        assert!(layout.columns >= 50);
        assert!(layout.visible_rows >= 20);
        let last = layout.first + layout.row * (layout.visible_rows as i32 - 1);
        assert!(last <= footer_first - unit as i32);
    }
}
