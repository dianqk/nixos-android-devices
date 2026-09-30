use fontdue::Font;
use std::fs::File;
use std::io::{self, Write};
use std::path::Path;

pub(crate) const LIGHT_BLUE: u32 = 0x7ebae4;
pub(crate) const DARK_BLUE: u32 = 0x5277c3;
pub(crate) const BACKGROUND: u32 = 0x000000;

pub(crate) struct Canvas {
    pub w: usize,
    pub h: usize,
    pub pixels: Vec<u32>,
}
impl Canvas {
    pub fn new(w: usize, h: usize) -> Self {
        Self {
            w,
            h,
            pixels: vec![BACKGROUND; w * h],
        }
    }
    pub fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, color: u32) {
        for py in y.max(0)..(y + h).min(self.h as i32) {
            for px in x.max(0)..(x + w).min(self.w as i32) {
                self.pixels[py as usize * self.w + px as usize] = color;
            }
        }
    }
    fn polygon(&mut self, points: &[(f32, f32)], color: u32) {
        let first_y = points
            .iter()
            .map(|point| point.1)
            .fold(f32::INFINITY, f32::min)
            .floor() as i32;
        let last_y = points
            .iter()
            .map(|point| point.1)
            .fold(f32::NEG_INFINITY, f32::max)
            .ceil() as i32;
        for py in first_y.max(0)..last_y.min(self.h as i32) {
            let scan_y = py as f32 + 0.5;
            let mut crossings = Vec::new();
            for (a, b) in points
                .iter()
                .zip(points.iter().cycle().skip(1))
                .take(points.len())
            {
                if (a.1 <= scan_y && scan_y < b.1) || (b.1 <= scan_y && scan_y < a.1) {
                    crossings.push(a.0 + (scan_y - a.1) * (b.0 - a.0) / (b.1 - a.1));
                }
            }
            crossings.sort_by(f32::total_cmp);
            for pair in crossings.chunks_exact(2) {
                let left = (pair[0] - 0.5).ceil() as i32;
                let right = (pair[1] - 0.5).ceil() as i32;
                self.rect(left, py, right - left, 1, color);
            }
        }
    }
    pub fn nix_snowflake(&mut self, x: i32, y: i32, size: i32) {
        // Adapted from the NixOS snowflake by Simon Frankau and Tim Cuthbertson,
        // CC BY 4.0: https://github.com/NixOS/nixos-artwork/blob/master/logo/nix-snowflake-colours.svg
        // Gradients are simplified to the two documented NixOS blue colours.
        const ARM: [(f32, f32); 9] = [
            (-97.65, 5.41),
            (24.55, 217.08),
            (-31.61, 217.61),
            (-64.24, 160.74),
            (-97.10, 217.31),
            (-125.00, 217.30),
            (-139.29, 192.61),
            (-92.48, 112.12),
            (-125.71, 54.29),
        ];
        for (degrees, color) in [
            (0.0_f32, LIGHT_BLUE),
            (60.0, LIGHT_BLUE),
            (-60.0, LIGHT_BLUE),
            (180.0, LIGHT_BLUE),
            (0.0, DARK_BLUE),
            (120.0, DARK_BLUE),
            (-120.0, DARK_BLUE),
        ] {
            let (sin, cos) = degrees.to_radians().sin_cos();
            let points: Vec<_> = ARM
                .iter()
                .map(|(dx, dy)| {
                    (
                        x as f32 + size as f32 * (250.8 + dx * cos - dy * sin) / 501.6,
                        y as f32 + size as f32 * (250.8 + dx * sin + dy * cos) / 501.6,
                    )
                })
                .collect();
            self.polygon(&points, color);
        }
    }
    pub fn line(&mut self, s: &str, x: i32, baseline: i32, size: f32, color: u32, font: &Font) {
        let mut cursor = x;
        for ch in s.chars() {
            let (m, glyph) = font.rasterize(ch, size);
            let top = baseline - m.height as i32 - m.ymin;
            for gy in 0..m.height {
                for gx in 0..m.width {
                    let px = cursor + m.xmin + gx as i32;
                    let py = top + gy as i32;
                    if px < 0 || py < 0 || px >= self.w as i32 || py >= self.h as i32 {
                        continue;
                    }
                    let alpha = glyph[gy * m.width + gx] as u32;
                    let old = self.pixels[py as usize * self.w + px as usize];
                    let mut mixed = 0;
                    for shift in [0, 8, 16] {
                        let c = ((color >> shift) & 255) * alpha;
                        let b = ((old >> shift) & 255) * (255 - alpha);
                        mixed |= ((c + b) / 255) << shift;
                    }
                    self.pixels[py as usize * self.w + px as usize] = mixed;
                }
            }
            cursor += m.advance_width.round() as i32;
            if cursor >= self.w as i32 {
                break;
            }
        }
    }
    pub fn fit_line(
        &mut self,
        s: &str,
        x: i32,
        baseline: i32,
        mut size: f32,
        color: u32,
        font: &Font,
    ) {
        while s
            .chars()
            .map(|ch| font.metrics(ch, size).advance_width)
            .sum::<f32>() as i32
            > self.w as i32 - x * 2
            && size > 11.0
        {
            size -= 2.0;
        }
        self.line(s, x, baseline, size, color, font);
    }
    pub fn menu_row(
        &mut self,
        label: &str,
        x: i32,
        top: i32,
        width: i32,
        height: i32,
        inset: i32,
        mut size: f32,
        selected: bool,
        font: &Font,
    ) {
        if selected {
            self.rect(x, top, width, height, DARK_BLUE);
        }
        let text_x = x + inset;
        while label
            .chars()
            .map(|ch| font.metrics(ch, size).advance_width)
            .sum::<f32>() as i32
            > width - inset * 2
            && size > 11.0
        {
            size -= 2.0;
        }
        let (text_top, text_bottom) = text_bounds(label, font, size);
        let baseline = top + (height - (text_bottom - text_top)) / 2 - text_top;
        self.line(label, text_x, baseline, size, 0xffffff, font);
    }
    pub fn ppm(&self, path: &Path) -> io::Result<()> {
        let mut file = File::create(path)?;
        write!(file, "P6\n{} {}\n255\n", self.w, self.h)?;
        for &p in &self.pixels {
            file.write_all(&[(p >> 16) as u8, (p >> 8) as u8, p as u8])?;
        }
        Ok(())
    }
}
fn text_bounds(label: &str, font: &Font, size: f32) -> (i32, i32) {
    label.chars().fold((0, 0), |(top, bottom), ch| {
        let metrics = font.metrics(ch, size);
        (
            top.min(-(metrics.height as i32) - metrics.ymin),
            bottom.max(-metrics.ymin),
        )
    })
}
pub(crate) fn text_height(label: &str, font: &Font, size: f32) -> i32 {
    let (top, bottom) = text_bounds(label, font, size);
    bottom - top
}
