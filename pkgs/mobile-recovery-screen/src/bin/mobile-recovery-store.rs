//! Serve an installed Nix store from a manually mounted recovery target.
//! This command never mounts or selects the target block device itself.
use std::ffi::CString;
use std::fs::{self, OpenOptions};
use std::io;
use std::os::fd::{AsRawFd, OwnedFd};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::net::UnixListener;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

const TARGET: &str = "/mnt";
const SOCKET: &str = "/run/mobile-recovery/recovery.sock";
const DAEMON: &str = "/nix/var/nix/profiles/system/sw/bin/nix-daemon";
static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

fn is_mounted(path: &str) -> io::Result<bool> {
    Ok(fs::read_to_string("/proc/self/mountinfo")?
        .lines()
        .any(|line| line.split_whitespace().nth(4) == Some(path)))
}

struct BindMounts(Vec<&'static str>);
impl BindMounts {
    fn add(&mut self, source: &'static str, destination: &'static str) -> io::Result<()> {
        let source = CString::new(source)?;
        let destination_c = CString::new(destination)?;
        let rc = unsafe {
            libc::mount(
                source.as_ptr(),
                destination_c.as_ptr(),
                std::ptr::null(),
                libc::MS_BIND,
                std::ptr::null(),
            )
        };
        if rc != 0 {
            return Err(io::Error::last_os_error());
        }
        self.0.push(destination);
        Ok(())
    }
}
impl Drop for BindMounts {
    fn drop(&mut self) {
        for path in self.0.iter().rev() {
            if let Ok(path) = CString::new(*path) {
                let rc = unsafe { libc::umount2(path.as_ptr(), 0) };
                if rc != 0 {
                    eprintln!(
                        "mobile-recovery-store: cannot unmount {}: {}",
                        path.to_string_lossy(),
                        io::Error::last_os_error()
                    );
                }
            }
        }
    }
}

struct SocketCleanup;
impl Drop for SocketCleanup {
    fn drop(&mut self) {
        let _ = fs::remove_file(SOCKET);
    }
}

fn run() -> io::Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        return Err(io::Error::other("must run as root"));
    }
    fs::create_dir_all("/run/mobile-recovery")?;
    let lock = OpenOptions::new()
        .write(true)
        .create(true)
        .mode(0o600)
        .open("/run/mobile-recovery/store.lock")?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err(io::Error::other("store bridge already running"));
    }
    if !is_mounted(TARGET)? {
        return Err(io::Error::other(
            "mount the validated installed root at /mnt first",
        ));
    }
    for path in [
        "/mnt/nix/store",
        "/mnt/nix/var/nix/db",
        "/mnt/nix/var/nix/profiles/system",
    ] {
        fs::symlink_metadata(path)
            .map_err(|_| io::Error::other(format!("installed root is missing {path}")))?;
    }
    for path in ["/mnt/dev", "/mnt/proc", "/mnt/tmp"] {
        if !fs::symlink_metadata(path)?.file_type().is_dir() {
            return Err(io::Error::other(format!(
                "installed root has an unsafe mountpoint {path}"
            )));
        }
    }
    // The profile symlink resolves inside the chroot, not in recovery RAM.
    let mut mounts = BindMounts(Vec::new());
    mounts.add("/dev", "/mnt/dev")?;
    mounts.add("/proc", "/mnt/proc")?;
    mounts.add("/tmp", "/mnt/tmp")?;

    if fs::symlink_metadata(SOCKET).is_ok() {
        fs::remove_file(SOCKET)?;
    }
    let listener = UnixListener::bind(SOCKET)?;
    let _cleanup = SocketCleanup;
    fs::set_permissions(SOCKET, fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;
    unsafe {
        libc::signal(libc::SIGTERM, stop as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, stop as *const () as libc::sighandler_t);
    }
    eprintln!("mobile-recovery-store: serving installed Nix store from /mnt");
    let mut clients = Vec::new();
    while !STOP.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, _)) => {
                clients.push(thread::spawn(move || -> io::Result<()> {
                    let input = Stdio::from(OwnedFd::from(stream.try_clone()?));
                    let output = Stdio::from(OwnedFd::from(stream));
                    let mut command = Command::new(DAEMON);
                    command.arg("--stdio");
                    command.env("NIX_REMOTE", "local");
                    command.stdin(input).stdout(output).stderr(Stdio::inherit());
                    let root = CString::new(TARGET).unwrap();
                    let slash = CString::new("/").unwrap();
                    unsafe {
                        command.pre_exec(move || {
                            if libc::chroot(root.as_ptr()) != 0 || libc::chdir(slash.as_ptr()) != 0
                            {
                                return Err(io::Error::last_os_error());
                            }
                            Ok(())
                        });
                    }
                    let status = command.status()?;
                    if !status.success() {
                        return Err(io::Error::other(format!("nix-daemon exited {status}")));
                    }
                    Ok(())
                }));
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error),
        }
        let mut index = 0;
        while index < clients.len() {
            if clients[index].is_finished() {
                if let Ok(Err(error)) = clients.remove(index).join() {
                    eprintln!("mobile-recovery-store: {error}");
                }
            } else {
                index += 1;
            }
        }
    }
    for client in clients {
        if let Ok(Err(error)) = client.join() {
            eprintln!("mobile-recovery-store: {error}");
        }
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("mobile-recovery-store: {error}");
        std::process::exit(1);
    }
}
