// SPDX-License-Identifier: GPL-2.0-only
//! Native Linux media transport. Partition and parent-LUN page caches are
//! independent aliases: every block descriptor uses O_DIRECT, with aligned
//! bounce buffers for ALL reads/writes. No cache eviction/flush workaround.
use std::{
    alloc::{alloc_zeroed, dealloc, Layout},
    fs::File,
    io::{self, Read, Seek, SeekFrom, Write},
    os::{
        fd::AsRawFd,
        unix::fs::{FileExt, FileTypeExt},
    },
};
pub(crate) const FLAGS: i32 = libc::O_DIRECT;
fn invalid(s: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, s)
}
fn sector(f: &File) -> io::Result<usize> {
    if !f.metadata()?.file_type().is_block_device() {
        return Ok(4096);
    }
    let flags = unsafe { libc::fcntl(f.as_raw_fd(), libc::F_GETFL) };
    if flags < 0 {
        return Err(io::Error::last_os_error());
    }
    if flags & FLAGS == 0 {
        return Err(invalid("block media descriptor must use O_DIRECT"));
    }
    let mut n = 0i32;
    if unsafe { libc::ioctl(f.as_raw_fd(), 0x1268u32 as _, &mut n) } != 0 {
        return Err(io::Error::last_os_error());
    }
    if ![512, 4096].contains(&n) {
        return Err(invalid("media logical sector"));
    }
    Ok(n as usize)
}
struct Aligned {
    ptr: *mut u8,
    layout: Layout,
}
impl Aligned {
    fn new(n: usize) -> io::Result<Self> {
        if n == 0 || n > 256 * 1024 * 1024 + 4096 {
            return Err(invalid("bounded media transfer"));
        }
        let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        let alignment = if page > 0 {
            (page as usize).max(4096)
        } else {
            4096
        };
        let layout = Layout::from_size_align(n, alignment)
            .map_err(|_| invalid("media allocation layout"))?;
        let ptr = unsafe { alloc_zeroed(layout) };
        if ptr.is_null() {
            return Err(io::Error::from_raw_os_error(libc::ENOMEM));
        }
        Ok(Self { ptr, layout })
    }
    fn bytes(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.layout.size()) }
    }
    fn bytes_mut(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.layout.size()) }
    }
}
impl Drop for Aligned {
    fn drop(&mut self) {
        unsafe { dealloc(self.ptr, self.layout) }
    }
}
/// Exact requested bytes, with only the containing logical sector(s) read for
/// bounded sub-sector metadata snapshots. All production image I/O is aligned.
pub(crate) fn read_at(f: &File, out: &mut [u8], at: u64) -> io::Result<()> {
    if out.is_empty() {
        return Ok(());
    }
    let unit = sector(f)?;
    let start = at / unit as u64 * unit as u64;
    let prefix = (at - start) as usize;
    let required = prefix
        .checked_add(out.len())
        .ok_or_else(|| invalid("media range overflow"))?;
    let n = required
        .checked_add(unit - 1)
        .ok_or_else(|| invalid("media range overflow"))?
        / unit
        * unit;
    let mut buffer = Aligned::new(n)?;
    let n = loop {
        match f.read_at(buffer.bytes_mut(), start) {
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            r => break r?,
        }
    };
    if n < required {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "short fresh media read",
        ));
    }
    out.copy_from_slice(&buffer.bytes()[prefix..required]);
    Ok(())
}
/// One write call: preserve short/error outcomes for the native owner's exact
/// observed-page rollback accounting. Never retry an unknown partial write.
pub(crate) fn write_at(f: &File, bytes: &[u8], at: u64) -> io::Result<usize> {
    let unit = sector(f)?;
    if bytes.is_empty() || !bytes.len().is_multiple_of(unit) || !at.is_multiple_of(unit as u64) {
        return Err(invalid("aligned media write required"));
    }
    let mut buffer = Aligned::new(bytes.len())?;
    buffer.bytes_mut().copy_from_slice(bytes);
    f.write_at(buffer.bytes(), at)
}
/// Existing non-CLI device adapter uses the same transport, not a second cached
/// block backend. Ordinary-file journals retain their normal File transport.
pub(crate) struct Storage<'a>(pub &'a mut File);
impl Read for Storage<'_> {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        let at = self.0.stream_position()?;
        read_at(self.0, out, at)?;
        self.0.seek(SeekFrom::Start(at + out.len() as u64))?;
        Ok(out.len())
    }
}
impl Write for Storage<'_> {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        let at = self.0.stream_position()?;
        let n = write_at(self.0, b, at)?;
        self.0.seek(SeekFrom::Start(at + n as u64))?;
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.0.flush()
    }
}
impl Seek for Storage<'_> {
    fn seek(&mut self, p: SeekFrom) -> io::Result<u64> {
        self.0.seek(p)
    }
}
impl crate::Storage for Storage<'_> {
    fn sync(&mut self) -> io::Result<()> {
        self.0.sync_all()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::OpenOptions;
    use std::os::unix::fs::OpenOptionsExt;
    #[test]
    fn actual_direct_aligned_buffers_and_subsector_metadata() {
        let p = std::env::temp_dir().join(format!("bc-direct-{}", std::process::id()));
        let mut f = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .custom_flags(FLAGS)
            .open(&p)
            .unwrap();
        f.set_len(8192).unwrap();
        let data = vec![7u8; 4096];
        assert_eq!(write_at(&f, &data, 4096).unwrap(), 4096);
        f.sync_all().unwrap();
        let mut unaligned = vec![0; 4097];
        read_at(&f, &mut unaligned[1..], 4096).unwrap();
        assert_eq!(&unaligned[1..], &data);
        let mut small = [0; 64];
        read_at(&f, &mut small, 4101).unwrap();
        assert_eq!(small, [7; 64]);
        assert!(write_at(&f, &data, 1).is_err());
        assert!(write_at(&f, &data[..4095], 0).is_err());
        assert!(read_at(&f, &mut small, 8192).is_err());
        let mut adapter = Storage(&mut f);
        adapter.seek(SeekFrom::Start(4096)).unwrap();
        let mut exact = vec![0; 4096];
        adapter.read_exact(&mut exact).unwrap();
        assert_eq!(exact, data);
        adapter.seek(SeekFrom::Start(0)).unwrap();
        adapter.write_all(&data).unwrap();
        crate::Storage::sync(&mut adapter).unwrap();
        adapter.seek(SeekFrom::Start(0)).unwrap();
        adapter.read_exact(&mut exact).unwrap();
        assert_eq!(exact, data);

        std::fs::remove_file(p).unwrap();
    }
}
