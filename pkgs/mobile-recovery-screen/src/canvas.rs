use std::io::{self, Write};
use std::path::Path;

// One ASCII byte per console cell. Untrusted status/log text never supplies
// terminal controls or ambiguous-width Unicode to the console output stream.
pub(crate) struct Canvas {
    pub w: usize,
    pub h: usize,
    pub cells: Vec<u8>,
}
impl Canvas {
    pub fn new(w: usize, h: usize) -> Self {
        Self {
            w,
            h,
            cells: vec![b' '; w * h],
        }
    }
    pub fn line(&mut self, y: usize, text: &str) {
        if y >= self.h {
            return;
        }
        for (x, ch) in text.chars().take(self.w).enumerate() {
            self.cells[y * self.w + x] = if ch.is_ascii() && !ch.is_control() {
                ch as u8
            } else {
                b'?'
            };
        }
    }
    pub fn text(&self) -> String {
        let mut output = String::new();
        for row in self.cells.chunks(self.w) {
            output.push_str(std::str::from_utf8(row).unwrap().trim_end());
            output.push('\n');
        }
        output
    }
    pub fn save(&self, path: &Path) -> io::Result<()> {
        std::fs::write(path, self.text())
    }
    pub fn write_changes(&self, previous: &mut [u8], output: &mut impl Write) -> io::Result<()> {
        if previous.len() != self.cells.len() {
            return Err(io::Error::other("console geometry changed"));
        }
        for (y, (row, old)) in self
            .cells
            .chunks(self.w)
            .zip(previous.chunks_mut(self.w))
            .enumerate()
        {
            let Some(left) = row.iter().zip(old.iter()).position(|(a, b)| a != b) else {
                continue;
            };
            let right = row
                .iter()
                .zip(old.iter())
                .rposition(|(a, b)| a != b)
                .unwrap()
                + 1;
            write!(output, "\x1b[{};{}H", y + 1, left + 1)?;
            output.write_all(&row[left..right])?;
            old.copy_from_slice(row);
        }
        Ok(())
    }
}
