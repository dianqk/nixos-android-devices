use crate::canvas::Canvas;
#[cfg(feature = "backlight-control")]
use std::fs;
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::mem::zeroed;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
#[cfg(feature = "backlight-control")]
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

const FBIOGET_VSCREENINFO: libc::c_ulong = 0x4600;
#[cfg(feature = "refresh-panel")]
const FBIOPAN_DISPLAY: libc::c_ulong = 0x4606;
const FBIOBLANK: libc::c_ulong = 0x4611;
const KDFONTOP: libc::c_ulong = 0x4b72;
const VT_ACTIVATE: libc::c_ulong = 0x5606;
const VT_WAITACTIVE: libc::c_ulong = 0x5607;
const KDSETMODE: libc::c_ulong = 0x4b3a;

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct Bitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub(crate) struct VarScreen {
    pub xres: u32,
    pub yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: Bitfield,
    green: Bitfield,
    blue: Bitfield,
    transp: Bitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [u32; 4],
}

#[repr(C)]
struct FontOp {
    op: u32,
    flags: u32,
    width: u32,
    height: u32,
    charcount: u32,
    data: *mut u8,
}
#[repr(C)]
#[derive(Default)]
struct VtState {
    active: u16,
    signal: u16,
    state: u16,
}
#[repr(C)]
struct ConsoleMap {
    console: u32,
    framebuffer: u32,
}

struct BitmapFont {
    width: u32,
    height: u32,
    count: u32,
    data: Vec<u8>,
}
impl BitmapFont {
    fn get(tty: &File) -> io::Result<Self> {
        let mut data = vec![0; 512 * 128 * 8];
        let mut op = FontOp {
            op: 5,
            flags: 0,
            width: 64,
            height: 128,
            charcount: 512,
            data: data.as_mut_ptr(),
        };
        ioctl_ptr(tty, KDFONTOP, &mut op)?;
        if !(1..=64).contains(&op.width)
            || !(1..=128).contains(&op.height)
            || ![256, 512].contains(&op.charcount)
        {
            return Err(io::Error::other("unsupported kernel font"));
        }
        let pitch = op.width.div_ceil(8) as usize;
        let mut packed = Vec::new();
        for glyph in 0..op.charcount as usize {
            let start = glyph * 128 * pitch;
            packed.extend_from_slice(&data[start..start + op.height as usize * pitch]);
        }
        Ok(Self {
            width: op.width,
            height: op.height,
            count: op.charcount,
            data: packed,
        })
    }
    fn scaled(&self, width: u32) -> Self {
        let height = width * 2;
        let pitch = width.div_ceil(8) as usize;
        let source_pitch = self.width.div_ceil(8) as usize;
        let mut data = vec![0; self.count as usize * height as usize * pitch];
        for g in 0..self.count as usize {
            for y in 0..height {
                for x in 0..width {
                    let sx = x * self.width / width;
                    let sy = y * self.height / height;
                    if self.data
                        [(g * self.height as usize + sy as usize) * source_pitch + sx as usize / 8]
                        & (0x80 >> (sx % 8))
                        != 0
                    {
                        data[(g * height as usize + y as usize) * pitch + x as usize / 8] |=
                            0x80 >> (x % 8);
                    }
                }
            }
        }
        Self {
            width,
            height,
            count: self.count,
            data,
        }
    }
    fn set(&mut self, tty: &File) -> io::Result<()> {
        let mut op = FontOp {
            op: 4,
            flags: 0,
            width: self.width,
            height: self.height,
            charcount: self.count,
            data: self.data.as_mut_ptr(),
        };
        ioctl_ptr(tty, KDFONTOP, &mut op).map(|_| ())
    }
}
fn ioctl_ptr<T>(file: &File, request: libc::c_ulong, arg: &mut T) -> io::Result<i32> {
    let result = unsafe { libc::ioctl(file.as_raw_fd(), request, arg as *mut T) };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(result)
    }
}
fn ioctl_value(file: &File, request: libc::c_ulong, value: i32) -> io::Result<()> {
    if unsafe { libc::ioctl(file.as_raw_fd(), request, value) } < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
pub(crate) fn font_width(width: u32, height: u32) -> io::Result<u32> {
    let preferred = height / 80;
    let choices: Vec<_> = (8..=64)
        .step_by(8)
        .filter(|w| (40..=240).contains(&(width / w)) && (32..=160).contains(&(height / (w * 2))))
        .collect();
    choices
        .iter()
        .copied()
        .rfind(|w| *w <= preferred)
        .or_else(|| choices.first().copied())
        .ok_or_else(|| io::Error::other("display too small for recovery console"))
}
pub(crate) struct Console {
    fb: File,
    #[cfg(feature = "refresh-panel")]
    var: VarScreen,
    tty: File,
    original_font: Option<BitmapFont>,
    original_palette: [u8; 48],
    original_kmsg: u8,
    original_vt: u16,
    original_mapping: ConsoleMap,
    original_termios: libc::termios,
    pub columns: usize,
    pub rows: usize,
    previous: Vec<u8>,
}
impl Console {
    pub fn open() -> io::Result<Self> {
        let mut file = None;
        for _ in 0..60 {
            if let Ok(found) = OpenOptions::new().read(true).write(true).open("/dev/fb0") {
                file = Some(found);
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
        let fb = file.ok_or_else(|| io::Error::other("no /dev/fb0; SSH/ACM remains available"))?;
        let mut var: VarScreen = unsafe { zeroed() };
        ioctl_ptr(&fb, FBIOGET_VSCREENINFO, &mut var)?;
        let width = font_width(var.xres, var.yres)?;
        let tty = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NOCTTY | libc::O_CLOEXEC)
            .open("/dev/tty2")?;
        // Allocate the log VT before redirecting printk; console=tty0 would
        // otherwise send kernel messages to the foreground menu.
        let _logs = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NOCTTY)
            .open("/dev/tty1")?;
        let mut original_palette = [0; 48];
        ioctl_ptr(&tty, 0x4b70, &mut original_palette)?; // GIO_CMAP
        let mut state = VtState::default();
        ioctl_ptr(&tty, 0x5603, &mut state)?; // VT_GETSTATE
        let mut original_kmsg = 17u8; // TIOCL_GETKMSGREDIRECT writes into the argument
        ioctl_ptr(&tty, libc::TIOCLINUX, &mut original_kmsg)?;
        let mut original_mapping = ConsoleMap {
            console: 2,
            framebuffer: 0,
        };
        ioctl_ptr(&fb, 0x460f, &mut original_mapping)?;
        let mut original_termios = unsafe { zeroed() };
        if unsafe { libc::tcgetattr(tty.as_raw_fd(), &mut original_termios) } < 0 {
            return Err(io::Error::last_os_error());
        }
        let mut console = Self {
            fb,
            tty,
            original_font: None,
            original_palette,
            original_kmsg,
            original_vt: state.active,
            original_mapping,
            original_termios,
            #[cfg(feature = "refresh-panel")]
            var,
            columns: 0,
            rows: 0,
            previous: Vec::new(),
        };
        let mut termios = original_termios;
        termios.c_lflag &= !(libc::ECHO | libc::ECHONL);
        if unsafe { libc::tcsetattr(console.tty.as_raw_fd(), libc::TCSANOW, &termios) } < 0 {
            return Err(io::Error::last_os_error());
        }
        ioctl_ptr(&console.tty, libc::TIOCLINUX, &mut [11u8, 1])?;
        let mut mapping = ConsoleMap {
            console: 2,
            framebuffer: 0,
        };
        ioctl_ptr(&console.fb, 0x4610, &mut mapping)?; // FBIOPUT_CON2FBMAP
        ioctl_ptr(&console.fb, 0x460f, &mut mapping)?; // FBIOGET_CON2FBMAP
        if mapping.framebuffer != 0 {
            return Err(io::Error::other("VT mapping failed"));
        }
        ioctl_value(&console.tty, KDSETMODE, 0)?;
        ioctl_value(&console.tty, VT_ACTIVATE, 2)?;
        ioctl_value(&console.tty, VT_WAITACTIVE, 2)?;
        // Mapping/activation must precede font access: fbcon may still be
        // deferred (notably on Sheng), leaving the dummy console without fonts.
        let original_font = BitmapFont::get(&console.tty)?;
        let mut scaled = original_font.scaled(width);
        console.original_font = Some(original_font);
        scaled.set(&console.tty)?;
        let mut palette = console.original_palette;
        palette[..3].fill(0);
        palette[21..24].fill(255);
        palette[45..48].fill(255);
        ioctl_ptr(&console.tty, 0x4b71, &mut palette)?; // PIO_CMAP
        let mut size: libc::winsize = unsafe { zeroed() };
        ioctl_ptr(&console.tty, libc::TIOCGWINSZ, &mut size)?;
        if !(40..=240).contains(&size.ws_col) || !(32..=160).contains(&size.ws_row) {
            return Err(io::Error::other("unsupported VT geometry"));
        }
        console.columns = size.ws_col as usize;
        console.rows = size.ws_row as usize;
        console.previous = vec![0; console.columns * console.rows];
        // No autowrap (including the bottom-right cell), cursor or ANSI styling
        // from log text. The recovery kernel command line disables blanking.
        console
            .tty
            .write_all(b"\x1b[0;97;40m\x1b[?25l\x1b[?7l\x1b[2J\x1b[H")?;
        ioctl_value(&console.fb, FBIOBLANK, 0)?;
        Ok(console)
    }
    pub fn show(&mut self, canvas: &Canvas) -> io::Result<()> {
        canvas.write_changes(&mut self.previous, &mut self.tty)
    }
    #[cfg(feature = "refresh-panel")]
    pub fn force_refresh(&mut self) -> io::Result<()> {
        ioctl_value(&self.fb, FBIOBLANK, 4)?;
        thread::sleep(Duration::from_millis(250));
        self.var.activate = 0x80;
        ioctl_value(&self.fb, FBIOBLANK, 0)?;
        ioctl_ptr(&self.fb, FBIOPAN_DISPLAY, &mut self.var)?;
        // Invalidate the character cache so the next show repaints every cell.
        self.previous.fill(0);
        Ok(())
    }
}
impl Drop for Console {
    fn drop(&mut self) {
        let _ = self.tty.write_all(b"\x1b[0m\x1b[?25h\x1b[?7h\x1b[2J\x1b[H");
        unsafe {
            libc::tcsetattr(self.tty.as_raw_fd(), libc::TCSANOW, &self.original_termios);
        }
        if let Some(font) = &mut self.original_font {
            let _ = font.set(&self.tty);
        }
        let _ = ioctl_ptr(&self.tty, 0x4b71, &mut self.original_palette);
        let _ = ioctl_ptr(&self.fb, 0x4610, &mut self.original_mapping);
        let _ = ioctl_ptr(&self.tty, libc::TIOCLINUX, &mut [11u8, self.original_kmsg]);
        if self.original_vt > 0 {
            let _ = ioctl_value(&self.tty, VT_ACTIVATE, self.original_vt as i32);
        }
    }
}

#[cfg(feature = "backlight-control")]
pub(crate) struct Backlight {
    path: PathBuf,
    original: String,
}
#[cfg(feature = "backlight-control")]
impl Backlight {
    pub fn enable(path: &Path, level: u32) -> io::Result<Self> {
        let max: u32 = fs::read_to_string(path.with_file_name("max_brightness"))?
            .trim()
            .parse()
            .map_err(|_| io::Error::other("invalid maximum backlight level"))?;
        if level > max {
            return Err(io::Error::other("backlight level exceeds maximum"));
        }
        let original = fs::read_to_string(path)?;
        fs::write(path, format!("{level}\n"))?;
        Ok(Self {
            path: path.to_path_buf(),
            original,
        })
    }
}
#[cfg(feature = "backlight-control")]
impl Drop for Backlight {
    fn drop(&mut self) {
        if let Err(error) = fs::write(&self.path, &self.original) {
            eprintln!("mobile-recovery-screen: restoring backlight: {error}");
        }
    }
}

#[cfg(test)]
mod font_tests {
    use super::*;
    #[test]
    fn bitmap_scaling_preserves_glyph_boundaries() {
        let font = BitmapFont {
            width: 8,
            height: 16,
            count: 2,
            data: [vec![0x81; 16], vec![0x42; 16]].concat(),
        };
        let scaled = font.scaled(16);
        assert_eq!((scaled.width, scaled.height, scaled.count), (16, 32, 2));
        assert_eq!(&scaled.data[..64], &[0xc0, 0x03].repeat(32));
        assert_eq!(&scaled.data[64..], &[0x30, 0x0c].repeat(32));
        assert_eq!(scaled.scaled(8).data, font.data);
        assert_eq!(std::mem::size_of::<FontOp>(), 32);
        assert_eq!(std::mem::size_of::<ConsoleMap>(), 8);
        assert_eq!(std::mem::size_of::<VtState>(), 6);
    }
}
