use crate::canvas::Canvas;
use crate::device;
use crate::display::{font_width, VarScreen};
use crate::input::{poll_inputs, Input, InputEvent, EV_KEY};
use crate::menu::{KeyResult, Menu, KEY_POWER, KEY_VOLUMEDOWN, KEY_VOLUMEUP};
use crate::render::{log_tail, render, wrap_log};
use crate::status::UpdateStatus;
use std::fs::File;
use std::mem::{size_of, zeroed};
use std::os::fd::{AsRawFd, FromRawFd};
use std::path::PathBuf;
use std::time::{Duration, Instant};

fn press(m: &mut Menu, key: u16, count: usize) -> Option<usize> {
    let start = Instant::now();
    m.key(key, 1, start, count, false, false);
    match m.key(
        key,
        0,
        start + Duration::from_millis(100),
        count,
        false,
        false,
    ) {
        KeyResult::Action(index) => Some(index),
        _ => None,
    }
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
fn choice_item_asks_for_a_size_before_confirming() {
    let mut m = Menu {
        choice_item: Some(2),
        ..Default::default()
    };
    press(&mut m, KEY_VOLUMEDOWN, 4);
    press(&mut m, KEY_VOLUMEDOWN, 4);
    assert_eq!(press(&mut m, KEY_POWER, 4), None);
    assert!(m.choosing && !m.confirming && m.choices.is_empty());
    m.choices = vec!["64G".into(), "128G".into()];
    // Cancel leaves the picker without an action.
    press(&mut m, KEY_VOLUMEUP, 4);
    assert_eq!(m.choice, 2);
    press(&mut m, KEY_POWER, 4);
    assert!(!m.choosing && !m.confirming);
    press(&mut m, KEY_POWER, 4);
    m.choices = vec!["64G".into(), "128G".into()];
    press(&mut m, KEY_VOLUMEDOWN, 4);
    assert_eq!(press(&mut m, KEY_POWER, 4), None);
    assert!(m.confirming && !m.yes);
    assert_eq!(m.chosen(), Some("128G"));
    // Declining the destructive confirmation returns to the menu.
    press(&mut m, KEY_POWER, 4);
    assert!(!m.choosing && !m.confirming && m.chosen().is_none());
    press(&mut m, KEY_POWER, 4);
    m.choices = vec!["64G".into(), "128G".into()];
    press(&mut m, KEY_POWER, 4);
    press(&mut m, KEY_VOLUMEUP, 4);
    assert_eq!(press(&mut m, KEY_POWER, 4), Some(2));
    assert_eq!(m.chosen(), Some("64G"));
    assert!(m.busy);
}
#[test]
fn userdata_check_fills_the_picker_without_closing_it() {
    use crate::app::{parse_userdata_check, task_takes_over};
    // `recovery prepare-install --check`: result on stdout, task on stderr.
    let text = "Android userdata choices: 32G 64G 128G\n(sizes that leave the Linux ESP and root at least 64G of the 224.6 GiB userdata allocation)\nCheck only. Show the plan with prepare-install --android-userdata SIZE --check.\nRecovery task 7\n";
    let check = parse_userdata_check(text, true);
    assert_eq!(check.choices.clone().unwrap(), ["32G", "64G", "128G"]);
    assert_eq!(check.task, Some(7));
    let refused = parse_userdata_check(
        "Android userdata choices: none\nCheck only. The userdata split is refused on this disk.\nRecovery task 8\n",
        true,
    );
    assert!(refused.choices.is_err());
    let failed = parse_userdata_check(
        "Recovery task 9\nrecovery: task 9: unmount all block filesystems first\n",
        false,
    );
    assert_eq!(
        failed.choices.unwrap_err(),
        "recovery: task 9: unmount all block filesystems first"
    );
    // The picker is open; the status watch then reports the check's own
    // task. That must not switch to the update view and close the picker.
    let mut m = Menu {
        choice_item: Some(2),
        ..Default::default()
    };
    press(&mut m, KEY_VOLUMEDOWN, 4);
    press(&mut m, KEY_VOLUMEDOWN, 4);
    press(&mut m, KEY_POWER, 4);
    assert!(m.choosing && m.choices.is_empty());
    m.choices = check.choices.unwrap();
    assert!(!task_takes_over(7, 6, check.task));
    assert!(m.choosing && m.choices.len() == 3);
    // Any other new task (an action, a host-side operation) still takes over.
    assert!(task_takes_over(10, 7, check.task));
    assert!(!task_takes_over(7, 7, None));
}
#[test]
fn long_chord_and_repeat_do_not_act() {
    let mut m = Menu::default();
    let t = Instant::now();
    m.key(KEY_POWER, 1, t, 4, false, false);
    m.key(KEY_POWER, 2, t, 4, false, false);
    m.key(KEY_POWER, 0, t + Duration::from_secs(2), 4, false, false);
    assert!(!m.logs);
    m.key(KEY_POWER, 1, t, 4, false, false);
    m.key(KEY_VOLUMEUP, 1, t, 4, false, false);
    m.key(
        KEY_POWER,
        0,
        t + Duration::from_millis(100),
        4,
        false,
        false,
    );
    m.key(
        KEY_VOLUMEUP,
        0,
        t + Duration::from_millis(100),
        4,
        false,
        false,
    );
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
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], false, || Ok(false)).unwrap();
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
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], true, || Ok(false)).unwrap();
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
        for state in 0..10 {
            menu.logs = state == 1;
            menu.confirming = state == 2 || state == 3 || state == 9;
            menu.choosing = state >= 8;
            menu.choices = vec!["64G".into(), "128G".into()];
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
            if state == 8 {
                assert!(text.contains("> 64G") && text.contains("  128G"));
            }
            if state == 9 {
                assert!(text.contains("keep 64G for Android"));
                // The confirmation waits for the plan of the chosen size.
                assert!(text.contains("Reading the plan..."));
                menu.plan = vec!["userdata 224.6 -> 64.0 GiB (Android, erased)".into()];
                render(
                    &mut canvas,
                    cfg,
                    &menu,
                    "",
                    &log,
                    "USB link: configured",
                    true,
                    &update,
                );
                let text = canvas.text();
                assert!(text.contains("userdata 224.6 -> 64.0 GiB"));
                assert!(text.find("userdata 224.6").unwrap() < text.find("> Cancel").unwrap());
                menu.plan.clear();
                canvas
                    .write_changes(&mut previous, &mut Vec::new())
                    .unwrap();
                screen.clone_from(&canvas.cells);
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
#[test]
fn sized_check_plan_and_split_result_are_shown() {
    use crate::app::{action_result, parse_plan_check};
    // `recovery prepare-install --android-userdata 64G --check` on an A/B device.
    let text = "Android userdata choices: 32G 64G 128G\n[]\nPlan: userdata 224.6 -> 64.0 GiB (Android, erased)\nPlan: new linux-boot 1.0 GiB\nPlan: new linux 159.6 GiB\nCheck only; no partition or filesystem writes.\nRecovery task 11\n";
    let check = parse_plan_check(text, true);
    assert_eq!(check.choices.unwrap().len(), 3);
    assert_eq!(check.task, Some(11));
    let failed = parse_plan_check(
        "Recovery task 12\nrecovery: task 12: Android userdata is too small\n",
        false,
    );
    assert_eq!(
        failed.choices.unwrap_err(),
        "recovery: task 12: Android userdata is too small"
    );
    // A successful split shows its output (undo and factory reset notes).
    let done = "Recovery task 13\nPrepared ext4 root and FAT ESP.\nUndo during this recovery session: recovery restore-gpt --check, then --confirm.\nAndroid needs a factory reset (wipe data) before it boots again.\n";
    let shown = action_result(done, true, "exit status: 0");
    assert!(shown.contains("restore-gpt") && shown.contains("factory reset"));
    assert!(!shown.contains("Recovery task"));
    assert_eq!(
        action_result(
            "Recovery task 14\nrecovery: task 14: no\n",
            false,
            "exit status: 1"
        ),
        "recovery: task 14: no"
    );
    let mut m = Menu {
        error: true,
        succeeded: true,
        ..Default::default()
    };
    press(&mut m, KEY_POWER, 4);
    assert!(!m.error && !m.succeeded);
}

#[test]
fn power_wakes_without_confirming_and_next_visible_press_selects() {
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        ..Menu::default()
    };
    let now = Instant::now();
    assert_eq!(menu.key(KEY_POWER, 1, now, 4, true, false), KeyResult::None);
    // An external unblank before release must not turn this into confirmation.
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            false,
            false
        ),
        KeyResult::Wake
    );
    assert!(menu.confirming && menu.yes && !menu.busy);
    assert_eq!(press(&mut menu, KEY_POWER, 4), Some(1));
}

#[test]
fn power_wake_survives_busy_and_status_transition() {
    let mut menu = Menu {
        busy: true,
        ..Menu::default()
    };
    let now = Instant::now();
    menu.key(KEY_POWER, 1, now, 4, true, true);
    menu.suppress_actions();
    assert_eq!(menu.key(KEY_POWER, 2, now, 4, true, true), KeyResult::None);
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            true,
            true
        ),
        KeyResult::Wake
    );
    assert!(menu.busy && !menu.logs);
}

#[test]
fn locked_press_cannot_select_after_unlock() {
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        ..Menu::default()
    };
    let now = Instant::now();
    menu.key(KEY_POWER, 1, now, 4, false, true);
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            false,
            false
        ),
        KeyResult::None
    );
    assert!(!menu.busy && menu.confirming && menu.yes);
}

#[test]
fn wake_rejects_chords_long_press_and_dropped_state() {
    let mut menu = Menu::default();
    let now = Instant::now();
    menu.key(KEY_POWER, 1, now, 4, true, false);
    menu.key(KEY_VOLUMEDOWN, 1, now, 4, true, false);
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            true,
            false
        ),
        KeyResult::None
    );
    menu.key(
        KEY_VOLUMEDOWN,
        0,
        now + Duration::from_millis(100),
        4,
        true,
        false,
    );
    menu.key(KEY_POWER, 1, now, 4, true, false);
    assert_eq!(
        menu.key(KEY_POWER, 0, now + Duration::from_secs(2), 4, true, false),
        KeyResult::None
    );
    menu.key(KEY_POWER, 1, now, 4, true, false);
    menu.reset_keys(); // SYN_DROPPED/device loss cancels every pending gesture.
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            true,
            false
        ),
        KeyResult::None
    );
}

fn input_pipe(events: &[(u16, u16, i32)]) -> (Vec<Input>, File) {
    let mut pipe = [0; 2];
    assert_eq!(
        unsafe { libc::pipe2(pipe.as_mut_ptr(), libc::O_NONBLOCK) },
        0
    );
    let input = unsafe { File::from_raw_fd(pipe[0]) };
    let output = unsafe { File::from_raw_fd(pipe[1]) };
    for &(kind, code, value) in events {
        let event = InputEvent {
            time: unsafe { zeroed() },
            kind,
            code,
            value,
        };
        assert_eq!(
            unsafe {
                libc::write(
                    output.as_raw_fd(),
                    (&event as *const InputEvent).cast(),
                    size_of::<InputEvent>(),
                )
            },
            size_of::<InputEvent>() as isize
        );
    }
    (
        vec![Input {
            file: input,
            path: PathBuf::from("test-input"),
            dropped: false,
        }],
        output,
    )
}

#[test]
fn busy_poll_keeps_wake_and_blocks_later_actions_in_same_batch() {
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        ..Menu::default()
    };
    menu.key(
        KEY_POWER,
        1,
        Instant::now() - Duration::from_millis(100),
        4,
        true,
        true,
    );
    let (mut inputs, _writer) = input_pipe(&[
        (EV_KEY, KEY_POWER, 0),
        (EV_KEY, KEY_VOLUMEDOWN, 1),
        (EV_KEY, KEY_VOLUMEDOWN, 0),
    ]);
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], true, || Ok(true)).unwrap();
    assert!(result.wake && result.action.is_none());
    assert_eq!(menu.selected, 1);
    assert!(menu.confirming && menu.yes && !menu.busy);
}

#[test]
fn poll_dropped_events_cancel_pending_wake() {
    let mut menu = Menu::default();
    menu.key(
        KEY_POWER,
        1,
        Instant::now() - Duration::from_millis(100),
        4,
        true,
        false,
    );
    let (mut inputs, _writer) = input_pipe(&[
        (0, 3, 0),
        (EV_KEY, KEY_POWER, 0),
        (0, 0, 0),
        (EV_KEY, KEY_POWER, 0),
    ]);
    let result = poll_inputs(&mut inputs, &mut menu, 4, 0, &[], false, || Ok(true)).unwrap();
    assert!(!result.wake && result.action.is_none());
}

#[test]
fn blank_state_error_cannot_confirm() {
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        ..Menu::default()
    };
    menu.key(
        KEY_POWER,
        1,
        Instant::now() - Duration::from_millis(100),
        4,
        false,
        false,
    );
    let (mut inputs, _writer) = input_pipe(&[(EV_KEY, KEY_POWER, 0)]);
    assert!(
        poll_inputs(&mut inputs, &mut menu, 4, 0, &[], false, || Err(
            std::io::Error::other("VT unavailable")
        ))
        .is_err()
    );
    assert!(!menu.busy);
}

#[test]
fn lock_without_events_invalidates_an_existing_confirmation_press() {
    let mut menu = Menu {
        selected: 1,
        confirming: true,
        yes: true,
        ..Menu::default()
    };
    let now = Instant::now();
    menu.key(KEY_POWER, 1, now, 4, false, false);
    poll_inputs(&mut Vec::new(), &mut menu, 4, 0, &[], true, || Ok(false)).unwrap();
    assert_eq!(
        menu.key(
            KEY_POWER,
            0,
            now + Duration::from_millis(100),
            4,
            false,
            false
        ),
        KeyResult::None
    );
    assert!(!menu.busy && menu.confirming && menu.yes);
}

#[test]
fn linux_only_screen_uses_the_daemon_plan_and_explicit_erase() {
    use crate::app::{parse_plan_check, parse_userdata_check, prepare_args, LINUX_ONLY_CHOICE};
    let output = "Linux-only layout: entire userdata\nPlan: Replace all Android userdata with a Linux ESP and root\nRecovery task 12";
    let check = parse_userdata_check(output, true);
    assert_eq!(check.choices.unwrap(), vec![LINUX_ONLY_CHOICE]);
    assert_eq!(check.task, Some(12));
    assert!(parse_userdata_check(output, false).choices.is_err());
    assert!(!parse_plan_check(output, true).choices.unwrap().is_empty());
    assert_eq!(
        prepare_args(LINUX_ONLY_CHOICE, false),
        vec!["prepare-install", "--check"]
    );
    assert_eq!(
        prepare_args(LINUX_ONLY_CHOICE, true),
        vec!["prepare-install", "--confirm-erase-userdata"]
    );
    assert_eq!(
        prepare_args("64G", true),
        vec![
            "prepare-install",
            "--android-userdata",
            "64G",
            "--confirm-erase-userdata"
        ]
    );
}
