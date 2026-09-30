use crate::menu::{Menu, KEY_POWER, KEY_VOLUMEDOWN, KEY_VOLUMEUP};
use std::fs::{self, File, OpenOptions};
use std::mem::{size_of, zeroed};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::time::Instant;

pub(crate) const EV_KEY: u16 = 1;
const SYN_DROPPED: u16 = 3;
const SYN_REPORT: u16 = 0;
const EVIOCGRAB: libc::c_ulong = 0x40044590;

#[repr(C)]
#[derive(Clone, Copy)]
pub(crate) struct InputEvent {
    pub time: libc::timeval,
    pub kind: u16,
    pub code: u16,
    pub value: i32,
}

pub(crate) struct Input {
    pub file: File,
    pub path: PathBuf,
    pub dropped: bool,
}
fn event_bits_request() -> libc::c_ulong {
    (2 << 30) | (96 << 16) | (b'E' as libc::c_ulong) << 8 | 0x21
}
pub(crate) fn discover_inputs(inputs: &mut Vec<Input>) -> bool {
    let Ok(entries) = fs::read_dir("/dev/input") else {
        return false;
    };
    let mut changed = false;
    for entry in entries.flatten() {
        let path = entry.path();
        if !entry.file_name().to_string_lossy().starts_with("event")
            || inputs.iter().any(|i| i.path == path)
            || inputs.len() >= 16
        {
            continue;
        }
        let Ok(file) = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
            .open(&path)
        else {
            continue;
        };
        let mut bits = [0u8; 96];
        if unsafe { libc::ioctl(file.as_raw_fd(), event_bits_request(), bits.as_mut_ptr()) } < 0 {
            continue;
        }
        if [KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_POWER]
            .iter()
            .all(|key| bits[*key as usize / 8] & (1 << (*key % 8)) == 0)
        {
            continue;
        }
        if unsafe { libc::ioctl(file.as_raw_fd(), EVIOCGRAB, 1) } < 0 {
            continue;
        }
        drain_input(file.as_raw_fd());
        inputs.push(Input {
            file,
            path,
            dropped: false,
        });
        changed = true;
    }
    changed
}
fn drain_input(fd: RawFd) {
    let mut event: InputEvent = unsafe { zeroed() };
    while unsafe {
        libc::read(
            fd,
            (&mut event as *mut InputEvent).cast(),
            size_of::<InputEvent>(),
        )
    } == size_of::<InputEvent>() as isize
    {}
}
pub(crate) struct PollResult {
    pub redraw: bool,
    pub action: Option<usize>,
    pub extra_ready: Vec<RawFd>,
}
pub(crate) fn poll_inputs(
    inputs: &mut Vec<Input>,
    menu: &mut Menu,
    len: usize,
    timeout_ms: i32,
    extra_fds: &[RawFd],
    input_locked: bool,
) -> PollResult {
    let before = (
        menu.selected,
        menu.confirming,
        menu.yes,
        menu.busy,
        menu.error,
        menu.logs,
        menu.updates,
    );
    let mut polls: Vec<libc::pollfd> = inputs
        .iter()
        .map(|i| libc::pollfd {
            fd: i.file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        })
        .collect();
    polls.extend(extra_fds.iter().map(|fd| libc::pollfd {
        fd: *fd,
        events: libc::POLLIN,
        revents: 0,
    }));
    unsafe {
        libc::poll(polls.as_mut_ptr(), polls.len() as libc::nfds_t, timeout_ms);
    }
    let mut result = PollResult {
        redraw: false,
        action: None,
        extra_ready: polls[inputs.len()..]
            .iter()
            .filter(|poll| poll.revents != 0)
            .map(|poll| poll.fd)
            .collect(),
    };
    // A status start can arrive in the same poll as a key release. Give the
    // transfer event priority so a pending confirmation cannot launch an action.
    let input_locked = input_locked || !result.extra_ready.is_empty();
    if input_locked {
        menu.reset_keys();
    }
    for idx in (0..inputs.len()).rev() {
        if polls[idx].revents & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0 {
            inputs.remove(idx);
            menu.reset_keys();
            result.redraw = true;
            continue;
        }
        if polls[idx].revents & libc::POLLIN == 0 {
            continue;
        }
        if input_locked {
            drain_input(inputs[idx].file.as_raw_fd());
            continue;
        }
        loop {
            let mut event: InputEvent = unsafe { zeroed() };
            if unsafe {
                libc::read(
                    inputs[idx].file.as_raw_fd(),
                    (&mut event as *mut InputEvent).cast(),
                    size_of::<InputEvent>(),
                )
            } != size_of::<InputEvent>() as isize
            {
                break;
            }
            if event.kind == 0 && event.code == SYN_DROPPED {
                inputs[idx].dropped = true;
                menu.reset_keys();
                continue;
            }
            if inputs[idx].dropped {
                if event.kind == 0 && event.code == SYN_REPORT {
                    inputs[idx].dropped = false;
                }
                continue;
            }
            if event.kind == EV_KEY {
                if let Some(action) = menu.key(event.code, event.value, Instant::now(), len) {
                    result.action = Some(action);
                }
            }
        }
    }
    result.redraw |= before
        != (
            menu.selected,
            menu.confirming,
            menu.yes,
            menu.busy,
            menu.error,
            menu.logs,
            menu.updates,
        );
    result
}
