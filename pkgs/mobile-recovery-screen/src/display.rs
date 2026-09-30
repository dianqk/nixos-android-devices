use crate::canvas::Canvas;
#[cfg(feature = "backlight-control")]
use std::fs;
use std::fs::{File, OpenOptions};
use std::io;
use std::mem::zeroed;
use std::os::fd::AsRawFd;
#[cfg(feature = "backlight-control")]
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

const FBIOGET_VSCREENINFO: libc::c_ulong = 0x4600;
const FBIOGET_FSCREENINFO: libc::c_ulong = 0x4602;
#[cfg(feature = "refresh-panel")]
const FBIOPAN_DISPLAY: libc::c_ulong = 0x4606;
const FBIOBLANK: libc::c_ulong = 0x4611;
const FB_BLANK_UNBLANK: libc::c_int = 0;
#[cfg(feature = "refresh-panel")]
const FB_BLANK_POWERDOWN: libc::c_int = 4;
const VT_ACTIVATE: libc::c_ulong = 0x5606;
const KDSETMODE: libc::c_ulong = 0x4b3a;
const KD_TEXT: libc::c_int = 0;
const KD_GRAPHICS: libc::c_int = 1;

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
#[derive(Clone, Copy, Default)]
pub(crate) struct FixScreen {
    id: [u8; 16],
    smem_start: libc::c_ulong,
    smem_len: u32,
    kind: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: libc::c_ulong,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [u16; 2],
}
pub(crate) struct Framebuffer {
    _file: File,
    pub var: VarScreen,
    fix: FixScreen,
    map: *mut u8,
    tty: File,
}
impl Framebuffer {
    pub fn open() -> io::Result<Self> {
        let mut file = None;
        for _ in 0..60 {
            if let Ok(found) = OpenOptions::new().read(true).write(true).open("/dev/fb0") {
                file = Some(found);
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
        let file = file.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no /dev/fb0"))?;
        let (mut var, mut fix): (VarScreen, FixScreen) = unsafe { (zeroed(), zeroed()) };
        if unsafe { libc::ioctl(file.as_raw_fd(), FBIOGET_VSCREENINFO, &mut var) } < 0
            || unsafe { libc::ioctl(file.as_raw_fd(), FBIOGET_FSCREENINFO, &mut fix) } < 0
        {
            return Err(io::Error::last_os_error());
        }
        let valid = var.bits_per_pixel == 32
            && fix.visual == 2
            && fix.kind == 0
            && (1..=4096).contains(&var.xres)
            && (1..=4096).contains(&var.yres)
            && [var.red, var.green, var.blue]
                .iter()
                .all(|b| b.length == 8 && b.offset <= 24 && b.msb_right == 0)
            && (var.transp.length == 0
                || (var.transp.length == 8
                    && var.transp.offset <= 24
                    && var.transp.msb_right == 0))
            && (var.xoffset as u64 + var.xres as u64) * 4 <= fix.line_length as u64
            && (var.yoffset as u64 + var.yres as u64) * fix.line_length as u64
                <= fix.smem_len as u64;
        if !valid {
            return Err(io::Error::other(
                "unsupported framebuffer layout; SSH/ACM remains available",
            ));
        }
        let map = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                fix.smem_len as usize,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                file.as_raw_fd(),
                0,
            )
        };
        if map == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }
        let tty = match OpenOptions::new().read(true).write(true).open("/dev/tty2") {
            Ok(tty) => tty,
            Err(error) => {
                unsafe {
                    libc::munmap(map, fix.smem_len as usize);
                }
                return Err(error);
            }
        };
        if unsafe { libc::ioctl(tty.as_raw_fd(), VT_ACTIVATE, 2) } < 0
            || unsafe { libc::ioctl(tty.as_raw_fd(), KDSETMODE, KD_GRAPHICS) } < 0
        {
            unsafe {
                libc::munmap(map, fix.smem_len as usize);
            }
            return Err(io::Error::last_os_error());
        }
        unsafe {
            libc::ioctl(file.as_raw_fd(), FBIOBLANK, FB_BLANK_UNBLANK);
        }
        Ok(Self {
            _file: file,
            var,
            fix,
            map: map.cast(),
            tty,
        })
    }
    pub fn show(&mut self, canvas: &Canvas) {
        for y in 0..canvas.h {
            for x in 0..canvas.w {
                let color = canvas.pixels[y * canvas.w + x];
                let pixel = ((color >> 16) & 255) << self.var.red.offset
                    | ((color >> 8) & 255) << self.var.green.offset
                    | (color & 255) << self.var.blue.offset
                    | if self.var.transp.length == 8 {
                        255 << self.var.transp.offset
                    } else {
                        0
                    };
                let offset = (y + self.var.yoffset as usize) * self.fix.line_length as usize
                    + (x + self.var.xoffset as usize) * 4;
                unsafe {
                    std::ptr::write_unaligned(self.map.add(offset).cast::<u32>(), pixel);
                }
            }
        }
    }
    #[cfg(feature = "refresh-panel")]
    pub fn force_refresh(&mut self) -> io::Result<()> {
        if unsafe { libc::ioctl(self._file.as_raw_fd(), FBIOBLANK, FB_BLANK_POWERDOWN) } < 0 {
            return Err(io::Error::last_os_error());
        }
        thread::sleep(Duration::from_millis(250));
        self.var.activate = 0x80;
        if unsafe { libc::ioctl(self._file.as_raw_fd(), FBIOBLANK, FB_BLANK_UNBLANK) } < 0
            || unsafe { libc::ioctl(self._file.as_raw_fd(), FBIOPAN_DISPLAY, &self.var) } < 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}
impl Drop for Framebuffer {
    fn drop(&mut self) {
        unsafe {
            libc::ioctl(self.tty.as_raw_fd(), KDSETMODE, KD_TEXT);
            libc::munmap(self.map.cast(), self.fix.smem_len as usize);
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
