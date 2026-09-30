use crate::canvas::{text_height, Canvas, BACKGROUND, LIGHT_BLUE};
use crate::device::Profile;
use crate::menu::Menu;
use crate::status::UpdateStatus;
use fontdue::Font;

pub(crate) fn wrap_log(log: &str, columns: usize) -> Vec<String> {
    let columns = columns.max(1);
    let mut wrapped = Vec::new();
    for source in log.lines() {
        let mut row = String::new();
        let mut count = 0;
        for ch in source.chars() {
            if ch.is_control() && ch != '\t' {
                continue;
            }
            if count == columns {
                wrapped.push(row);
                row = String::new();
                count = 0;
            }
            row.push(if ch == '\t' { ' ' } else { ch });
            count += 1;
        }
        wrapped.push(row);
    }
    wrapped
}
pub(crate) fn log_tail(log: &str, columns: usize, rows: usize) -> Vec<String> {
    if rows == 0 {
        return Vec::new();
    }
    let mut visible = Vec::new();
    for source in log.lines().rev() {
        let mut wrapped = wrap_log(source, columns);
        if wrapped.len() > rows {
            wrapped = wrapped.split_off(wrapped.len() - rows);
            wrapped[0].insert_str(0, "...");
        }
        if wrapped.len() + visible.len() > rows {
            break;
        }
        wrapped.append(&mut visible);
        visible = wrapped;
    }
    visible
}
pub(crate) struct LogLayout {
    pub columns: usize,
    pub first: i32,
    pub row: i32,
    pub visible_rows: usize,
}
pub(crate) fn log_layout(
    width: i32,
    margin: i32,
    start: i32,
    footer_first: i32,
    unit: f32,
    log_size: f32,
    cell: i32,
) -> LogLayout {
    let columns = ((width - margin * 2) / cell.max(1)).max(1) as usize;
    let row = (log_size * 1.3).round().max(16.0) as i32;
    let first = start + (unit * 1.4) as i32;
    let bottom = footer_first - unit as i32;
    let visible_rows = if bottom >= first {
        ((bottom - first) / row + 1) as usize
    } else {
        0
    };
    LogLayout {
        columns,
        first,
        row,
        visible_rows,
    }
}
pub(crate) fn render(
    canvas: &mut Canvas,
    font: &Font,
    cfg: &Profile,
    menu: &Menu,
    failure: &str,
    log: &str,
    usb: &str,
    keys: bool,
    scale: f32,
    update: &UpdateStatus,
) {
    canvas.pixels.fill(BACKGROUND);
    let unit = (canvas.w.min(canvas.h) as f32 / 27.0 * scale).clamp(16.0, 76.0);
    let margin = (unit * 0.45) as i32;
    let log_margin = (unit * 0.35) as i32;
    let top = (unit * 2.1) as i32;
    canvas.line("NIXOS RECOVERY", margin, top, unit * 1.2, LIGHT_BLUE, font);
    if !menu.updates && !menu.logs && !menu.confirming && !menu.busy && !menu.error {
        let logo_size = (unit * 2.7) as i32;
        canvas.nix_snowflake(
            canvas.w as i32 - margin - logo_size,
            top - (unit * 1.2) as i32,
            logo_size,
        );
    }
    canvas.fit_line(
        &cfg.title,
        margin,
        top + (unit * 1.3) as i32,
        unit * 0.8,
        0xffffff,
        font,
    );
    canvas.rect(0, top + (unit * 1.8) as i32, canvas.w as i32, 2, 0x426470);
    canvas.fit_line(
        usb,
        margin,
        top + (unit * 2.7) as i32,
        unit * 0.65,
        0xb8c7d1,
        font,
    );
    let start = top + (unit * 4.2) as i32;
    let foot = canvas.h as i32 - (unit * 1.1) as i32;
    let footer_first = foot - (unit * 2.0) as i32;
    if menu.updates {
        canvas.line("UPDATE STATUS", margin, start, unit, LIGHT_BLUE, font);
        let stage = if update.stage.is_empty() {
            "Waiting for host transfer"
        } else {
            &update.stage
        };
        canvas.fit_line(
            stage,
            margin,
            start + (unit * 1.5) as i32,
            unit * 0.77,
            0xffffff,
            font,
        );
        let counts = if update.total_paths > 0 {
            format!("{} / {} store paths", update.done_paths, update.total_paths)
        } else {
            "No store paths reported yet".into()
        };
        canvas.fit_line(
            &counts,
            margin,
            start + (unit * 2.8) as i32,
            unit * 0.65,
            0xb8c7d1,
            font,
        );
        let bar_y = start + (unit * 3.25) as i32;
        let bar_w = canvas.w as i32;
        canvas.rect(0, bar_y, bar_w, (unit * 0.22) as i32, 0x426470);
        if update.total_paths > 0 {
            canvas.rect(
                0,
                bar_y,
                (bar_w as u64 * update.done_paths / update.total_paths) as i32,
                (unit * 0.22) as i32,
                LIGHT_BLUE,
            );
        }
        if update.path_total > 0 {
            let bytes = format!(
                "Current path: {} / {} MiB",
                update.path_bytes / 1048576,
                update.path_total / 1048576
            );
            canvas.fit_line(
                &bytes,
                margin,
                start + (unit * 4.3) as i32,
                unit * 0.6,
                0xb8c7d1,
                font,
            );
        }
        let log_size = cfg.log_font_px as f32 * scale;
        let cell = font.metrics('M', log_size).advance_width.round().max(1.0) as i32;
        let layout = log_layout(
            canvas.w as i32,
            log_margin,
            start + (unit * 4.4) as i32,
            footer_first,
            unit,
            log_size,
            cell,
        );
        let visible = log_tail(
            &update.logs.iter().cloned().collect::<Vec<_>>().join("\n"),
            layout.columns,
            layout.visible_rows,
        );
        for (i, line) in visible.iter().enumerate() {
            canvas.line(
                line,
                log_margin,
                layout.first + layout.row * i as i32,
                log_size,
                0xe0e9ed,
                font,
            );
        }
    } else if menu.logs {
        canvas.line(
            "RECOVERY LOG (WARNING+)",
            margin,
            start,
            unit,
            LIGHT_BLUE,
            font,
        );
        let log_size = cfg.log_font_px as f32 * scale;
        let cell = font.metrics('M', log_size).advance_width.round().max(1.0) as i32;
        let layout = log_layout(
            canvas.w as i32,
            log_margin,
            start,
            footer_first,
            unit,
            log_size,
            cell,
        );
        let visible = log_tail(log, layout.columns, layout.visible_rows);
        for (i, line) in visible.iter().enumerate() {
            canvas.line(
                line,
                log_margin,
                layout.first + layout.row * i as i32,
                log_size,
                0xe0e9ed,
                font,
            );
        }
    } else if menu.error || menu.busy || menu.confirming {
        let item = &cfg.items[menu.selected];
        canvas.fit_line(
            cfg.item_label(item),
            margin,
            start,
            unit * 1.1,
            0xffffff,
            font,
        );
        let message = if menu.error {
            "Action stopped"
        } else if menu.busy {
            "Running action..."
        } else {
            "Leave recovery? RAM data will be lost."
        };
        canvas.fit_line(
            message,
            margin,
            start + (unit * 2.0) as i32,
            unit * 0.8,
            0xffd18a,
            font,
        );
        if menu.error {
            canvas.fit_line(
                failure,
                margin,
                start + (unit * 3.3) as i32,
                unit * 0.68,
                0xffffff,
                font,
            );
        }
        if menu.confirming {
            let row_font = unit * 0.9;
            let row_height = 2 * ["Cancel", "Confirm"]
                .iter()
                .map(|label| text_height(label, font, row_font))
                .max()
                .unwrap_or(1);
            let row_gap = (unit * 0.25) as i32;
            for (idx, (label, selected)) in [("Cancel", !menu.yes), ("Confirm", menu.yes)]
                .into_iter()
                .enumerate()
            {
                canvas.menu_row(
                    label,
                    0,
                    start + (unit * 2.9) as i32 + idx as i32 * (row_height + row_gap),
                    canvas.w as i32,
                    row_height,
                    margin,
                    row_font,
                    selected,
                    font,
                );
            }
        }
    } else {
        let first = start;
        let log_size = cfg.log_font_px as f32 * scale;
        let log_reserve = unit * 3.0 + log_size * 1.3 * 8.0;
        let row_gap = (unit * 0.35) as i32;
        let row_budget = (((footer_first - first) as f32 - log_reserve) / cfg.items.len() as f32)
            as i32
            - row_gap;
        let mut row_font = unit * 1.35;
        let mut text_height_px = cfg
            .items
            .iter()
            .map(|item| text_height(cfg.item_label(item), font, row_font))
            .max()
            .unwrap_or(1);
        while text_height_px * 2 > row_budget && row_font > 12.0 {
            row_font -= 1.0;
            text_height_px = cfg
                .items
                .iter()
                .map(|item| text_height(cfg.item_label(item), font, row_font))
                .max()
                .unwrap_or(1);
        }
        let row_height = text_height_px * 2;
        let row = row_height + row_gap;
        for (idx, item) in cfg.items.iter().enumerate() {
            canvas.menu_row(
                cfg.item_label(item),
                0,
                first + row * idx as i32,
                canvas.w as i32,
                row_height,
                margin,
                row_font,
                idx == menu.selected,
                font,
            );
        }
        let log_top =
            first + row * (cfg.items.len() - 1) as i32 + row_height + (unit * 0.75) as i32;
        if log_top + ((unit * 3.0) as i32) < footer_first {
            let heading_y = log_top + (unit * 0.8) as i32;
            canvas.rect(
                0,
                log_top - (unit * 0.4) as i32,
                canvas.w as i32,
                2,
                0x426470,
            );
            canvas.line(
                "RECOVERY LOG",
                margin,
                heading_y,
                unit * 0.8,
                LIGHT_BLUE,
                font,
            );
            let cell = font.metrics('M', log_size).advance_width.round().max(1.0) as i32;
            let layout = log_layout(
                canvas.w as i32,
                log_margin,
                heading_y,
                footer_first,
                unit,
                log_size,
                cell,
            );
            let visible = log_tail(log, layout.columns, layout.visible_rows);
            if !visible.is_empty() {
                let last = layout.first + layout.row * (layout.visible_rows as i32 - 1);
                let first_visible = last - layout.row * (visible.len() as i32 - 1);
                for (i, line) in visible.iter().enumerate() {
                    canvas.line(
                        line,
                        log_margin,
                        first_visible + layout.row * i as i32,
                        log_size,
                        0xe0e9ed,
                        font,
                    );
                }
            }
        }
    }
    canvas.rect(
        0,
        footer_first - (unit * 0.75) as i32,
        canvas.w as i32,
        2,
        0x426470,
    );
    canvas.fit_line(
        if update.active {
            "Update in progress   Controls locked"
        } else if menu.logs || menu.updates {
            "Any key to return"
        } else {
            "Volume +/- to move   Power to select"
        },
        margin,
        footer_first,
        unit * 0.6,
        0xb8c7d1,
        font,
    );
    let input_hint = if keys {
        "SSH/ACM: recovery help".to_string()
    } else {
        "Keys unavailable; use SSH/ACM shell".into()
    };
    canvas.fit_line(
        &input_hint,
        margin,
        foot - unit as i32,
        unit * 0.6,
        0xb8c7d1,
        font,
    );
    canvas.fit_line(&cfg.warning, margin, foot, unit * 0.55, 0xffd18a, font);
}
