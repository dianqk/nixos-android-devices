// SPDX-License-Identifier: GPL-2.0-only
#![cfg_attr(not(test), no_std)]
extern crate alloc;
mod authority;
#[path = "../../tools/boot-choice/context.rs"]
mod context;
#[path = "../../tools/boot-choice/avb.rs"]
mod avb;
#[path = "../../tools/boot-choice/format.rs"]
mod format;
#[path = "../../tools/boot-choice/owned.rs"]
mod owned;
mod transaction;
#[cfg(not(test))]
mod runtime {
    use core::alloc::{GlobalAlloc, Layout};
    struct Pool;
    unsafe extern "C" {
        fn bc_alloc(n: usize) -> *mut u8;
        fn bc_free(p: *mut u8);
        fn bc_abort() -> !;
    }
    unsafe impl GlobalAlloc for Pool {
        unsafe fn alloc(&self, l: Layout) -> *mut u8 {
            if l.align() > 8 {
                core::ptr::null_mut()
            } else {
                bc_alloc(l.size())
            }
        }
        unsafe fn dealloc(&self, p: *mut u8, _: Layout) {
            bc_free(p)
        }
    }
    #[global_allocator]
    static ALLOC: Pool = Pool;
    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo) -> ! {
        unsafe { bc_abort() }
    }
}
#[cfg(not(test))]
unsafe extern "C" {
    fn bc_read(lba: u64, bytes: usize, out: *mut u8) -> usize;
    fn bc_select(index: usize, geometry: *mut u64) -> usize;
}
#[cfg(not(test))]
struct Disk;
#[cfg(not(test))]
impl authority::ReadDisk for Disk {
    fn read(&mut self, lba: u64, out: &mut [u8]) -> authority::Result<()> {
        if unsafe { bc_read(lba, out.len(), out.as_mut_ptr()) } == 0 {
            Ok(())
        } else {
            Err("media read/identity")
        }
    }
}
#[cfg(not(test))]
struct Group;
#[cfg(not(test))]
impl authority::DiskGroup for Group {
    type Disk = Disk;
    fn select(&mut self, index: usize) -> authority::Result<(Disk, usize, u64)> {
        let mut geometry = [0u64; 2];
        if unsafe { bc_select(index, geometry.as_mut_ptr()) } != 0 {
            return Err("media/group changed");
        }
        Ok((Disk, geometry[0] as usize, geometry[1]))
    }
}
#[cfg(not(test))]
unsafe extern "C" {
    fn bc_error(bytes: *const u8, length: usize);
    fn bc_write(lba: u64, n: usize, bytes: *const u8) -> usize;
    fn bc_probe() -> usize;
    fn bc_flush() -> usize;
    fn bc_journal_read(bytes: *mut u8, cap: usize, length: *mut usize) -> usize;
    fn bc_journal_create(bytes: *const u8, n: usize) -> usize;
    fn bc_journal_remove() -> usize;
}
#[cfg(not(test))]
fn status(n: usize) -> authority::Result<()> {
    if n == 0 {
        Ok(())
    } else {
        Err("EFI I/O failure")
    }
}
#[cfg(not(test))]
impl transaction::Io for Disk {
    fn probe(&mut self) -> authority::Result<()> {
        status(unsafe { bc_probe() })
    }
    fn flush(&mut self) -> authority::Result<()> {
        status(unsafe { bc_flush() })
    }
    fn read(&mut self, lba: u64, bytes: &mut [u8]) -> authority::Result<()> {
        authority::ReadDisk::read(self, lba, bytes)
    }
    fn write(&mut self, lba: u64, bytes: &[u8]) -> authority::Result<()> {
        status(unsafe { bc_write(lba, bytes.len(), bytes.as_ptr()) })
    }
    fn journal_read(&mut self) -> authority::Result<Option<alloc::vec::Vec<u8>>> {
        let mut b = alloc::vec![0;transaction::JOURNAL_SIZE];
        let mut n = 0;
        match unsafe { bc_journal_read(b.as_mut_ptr(), b.len(), &mut n) } {
            0 => {
                b.truncate(n);
                Ok(Some(b))
            }
            2 => Ok(None),
            _ => Err("journal read"),
        }
    }
    fn journal_create(&mut self, b: &[u8]) -> authority::Result<()> {
        status(unsafe { bc_journal_create(b.as_ptr(), b.len()) })
    }
    fn journal_remove(&mut self) -> authority::Result<()> {
        status(unsafe { bc_journal_remove() })
    }
}
fn manual_options(bytes: &[u8]) -> authority::Result<bool> {
    if bytes.is_empty() {
        return Ok(false);
    }
    let expected = b"target=android";
    let bytes = if bytes.len() == (expected.len() + 1) * 2 && bytes[bytes.len() - 2..] == [0, 0] {
        &bytes[..bytes.len() - 2]
    } else {
        bytes
    };
    if bytes.len() != expected.len() * 2
        || !bytes
            .as_chunks::<2>()
            .0
            .iter()
            .zip(expected)
            .all(|(a, b)| *a == [*b, 0])
    {
        return Err("unknown load options");
    }
    Ok(true)
}
/// 0: chainload, 1: refuse, 2: committed Android/reset. C cannot authorize writes.
#[cfg(not(test))]
#[no_mangle]
pub unsafe extern "C" fn bc_run(
    context: *mut u8,
    count: usize,
    options: *const u8,
    length: usize,
) -> u32 {
    if context.is_null() || length > 64 || (length != 0 && options.is_null()) {
        return 1;
    }
    let opts = if length == 0 {
        &[]
    } else {
        core::slice::from_raw_parts(options, length)
    };
    let Ok(manual) = manual_options(opts) else {
        return 1;
    };
    let ctx: &mut [u8; 96] = (&mut *core::ptr::slice_from_raw_parts_mut(context, 96))
        .try_into()
        .unwrap();
    let Ok(mut t) = authority::inspect_group(&mut Group, ctx, count) else {
        return 1;
    };
    if Group.select_target(t.index).is_err() {
        return 1;
    }
    match transaction::execute(&mut Disk, &mut t, ctx, manual) {
        Ok(0) => 2,
        Ok(1) => 0,
        Err(e) => {
            bc_error(e.as_ptr(), e.len());
            1
        }
        _ => 1,
    }
}
#[cfg(not(test))]
impl Group {
    fn select_target(&mut self, index: usize) -> authority::Result<()> {
        authority::DiskGroup::select(self, index).map(|_| ())
    }
}
#[cfg(test)]
mod option_tests {
    #[test]
    fn exact_manual_option_only() {
        assert_eq!(super::manual_options(&[]), Ok(false));
        let mut b = alloc::vec::Vec::new();
        for c in b"target=android" {
            b.extend([*c, 0]);
        }
        assert_eq!(super::manual_options(&b), Ok(true));
        b.extend([0, 0]);
        assert_eq!(super::manual_options(&b), Ok(true));
        b.extend([0, 0]);
        assert!(super::manual_options(&b).is_err());
    }
}
