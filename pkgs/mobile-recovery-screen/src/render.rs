use crate::canvas::Canvas;
use crate::device::Profile;
use crate::menu::Menu;
use crate::status::UpdateStatus;

pub(crate) fn wrap_log(log: &str, columns: usize) -> Vec<String> {
    let columns = columns.max(1);
    let mut wrapped = Vec::new();
    for source in log.lines() {
        let mut row = String::new();
        for ch in source.chars() {
            if row.len() == columns {
                wrapped.push(row);
                row = String::new();
            }
            row.push(if ch == '\t' {
                ' '
            } else if ch.is_ascii() && !ch.is_control() {
                ch
            } else {
                '?'
            });
        }
        wrapped.push(row);
    }
    wrapped
}
pub(crate) fn log_tail(log: &str, columns: usize, rows: usize) -> Vec<String> {
    let wrapped = wrap_log(log, columns);
    wrapped[wrapped.len().saturating_sub(rows)..].to_vec()
}
fn logs(canvas: &mut Canvas, start: usize, end: usize, log: &str) {
    for (i, line) in log_tail(log, canvas.w, end.saturating_sub(start))
        .iter()
        .enumerate()
    {
        canvas.line(start + i, line);
    }
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn render(
    canvas: &mut Canvas,
    cfg: &Profile,
    menu: &Menu,
    failure: &str,
    log: &str,
    usb: &str,
    keys: bool,
    update: &UpdateStatus,
) {
    canvas.cells.fill(b' ');
    canvas.line(0, "NIXOS RECOVERY");
    canvas.line(1, cfg.title);
    canvas.line(3, usb);
    let footer = canvas.h.saturating_sub(5);
    let separator = "-".repeat(canvas.w);
    canvas.line(4, &separator);
    if menu.updates {
        canvas.line(
            6,
            if cfg!(feature = "recovery-daemon") {
                "TASK STATUS"
            } else {
                "UPDATE STATUS"
            },
        );
        canvas.line(
            8,
            if update.stage.is_empty() {
                "Waiting for host transfer"
            } else {
                &update.stage
            },
        );
        canvas.line(
            9,
            &if cfg!(feature = "recovery-daemon") {
                if update.total_paths == 0 {
                    format!("Completed: {} (total unknown)", update.done_paths)
                } else {
                    format!("Completed: {} / {}", update.done_paths, update.total_paths)
                }
            } else {
                format!("{} / {} store paths", update.done_paths, update.total_paths)
            },
        );
        let width = canvas.w.saturating_sub(2);
        let done = if update.total_paths == 0 {
            0
        } else {
            (width as u128 * update.done_paths.min(update.total_paths) as u128
                / update.total_paths as u128) as usize
        };
        canvas.line(
            10,
            &format!("[{}{}]", "#".repeat(done), " ".repeat(width - done)),
        );
        if update.path_total > 0 {
            canvas.line(
                11,
                &format!(
                    "Current: {} / {} MiB",
                    update.path_bytes / 1048576,
                    update.path_total / 1048576
                ),
            );
        }
        logs(
            canvas,
            13,
            footer,
            &update.logs.iter().cloned().collect::<Vec<_>>().join("\n"),
        );
    } else if menu.logs {
        canvas.line(6, "RECOVERY LOG (WARNING+)");
        logs(canvas, 8, footer, log);
    } else if menu.error || menu.busy || menu.confirming {
        canvas.line(6, cfg.item_label(&cfg.items[menu.selected]));
        canvas.line(
            8,
            if menu.error {
                "Action stopped"
            } else if menu.busy {
                "Running action..."
            } else {
                "Leave recovery? RAM data will be lost."
            },
        );
        if menu.error {
            logs(canvas, 10, footer, failure);
        } else if menu.confirming {
            canvas.line(11, if menu.yes { "  Cancel" } else { "> Cancel" });
            canvas.line(13, if menu.yes { "> Confirm" } else { "  Confirm" });
        }
    } else {
        for (idx, item) in cfg.items.iter().enumerate() {
            canvas.line(
                6 + idx * 2,
                &format!(
                    "{} {}",
                    if idx == menu.selected { '>' } else { ' ' },
                    cfg.item_label(item)
                ),
            );
        }
        let heading = 7 + cfg.items.len() * 2;
        canvas.line(heading, "RECOVERY LOG (WARNING+)");
        logs(canvas, heading + 2, footer, log);
    }
    canvas.line(footer, &separator);
    canvas.line(
        footer + 1,
        if update.active {
            "Task in progress; controls locked"
        } else if menu.logs || menu.updates || menu.error {
            "Volume / Power: return"
        } else if menu.busy {
            "Please wait..."
        } else {
            "Volume +/-: move   Power: select"
        },
    );
    canvas.line(
        footer + 2,
        if keys {
            "SSH/ACM: recovery help"
        } else {
            "Keys unavailable; use SSH/ACM"
        },
    );
    for (i, line) in wrap_log(cfg.warning, canvas.w).iter().take(2).enumerate() {
        canvas.line(footer + 3 + i, line);
    }
}
