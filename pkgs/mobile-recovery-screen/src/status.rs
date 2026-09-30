use std::collections::VecDeque;
use std::fs;
use std::io::{self, Read};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;

const SOCKET: &str = "/run/mobile-recovery/status.sock";
const MAX_LINE: usize = 2048;
const MAX_LOGS: usize = 80;

#[derive(Default)]
pub struct UpdateStatus {
    pub stage: String,
    pub done_paths: u64,
    pub total_paths: u64,
    pub path_bytes: u64,
    pub path_total: u64,
    pub active: bool,
    pub finished: bool,
    pub failed: bool,
    pub logs: VecDeque<String>,
    pub generation: u64,
    pub session_id: u64,
}

impl UpdateStatus {
    fn line(&mut self, line: &str) {
        let mut fields = line.split('\t');
        let Some(command) = fields.next() else { return };
        match command {
            "start" if fields.clone().count() == 1 => {
                let generation = self.generation;
                let session_id = self.session_id;
                *self = Self::default();
                self.active = true;
                self.stage = clean(fields.next().unwrap());
                self.generation = generation;
                self.session_id = session_id.wrapping_add(1);
            }
            "stage" if self.active && fields.clone().count() == 1 => {
                self.stage = clean(fields.next().unwrap());
            }
            "progress" if self.active && fields.clone().count() == 4 => {
                let values: Option<Vec<u64>> = fields.map(|field| field.parse().ok()).collect();
                if let Some(values) = values {
                    if values[0] <= values[1] && values[2] <= values[3] {
                        self.done_paths = values[0];
                        self.total_paths = values[1];
                        self.path_bytes = values[2];
                        self.path_total = values[3];
                    }
                }
            }
            "log" if self.active && fields.clone().count() == 1 => {
                let message = clean(fields.next().unwrap());
                if !message.is_empty() {
                    self.logs.push_back(message);
                    if self.logs.len() > MAX_LOGS {
                        self.logs.pop_front();
                    }
                }
            }
            "done" if self.active && fields.next().is_none() => {
                self.active = false;
                self.finished = true;
                self.stage = "Copy complete".into();
            }
            "error" if self.active && fields.clone().count() == 1 => {
                self.active = false;
                self.failed = true;
                self.stage = "Copy failed".into();
                self.logs.push_back(clean(fields.next().unwrap()));
                if self.logs.len() > MAX_LOGS {
                    self.logs.pop_front();
                }
            }
            _ => return,
        }
        self.generation = self.generation.wrapping_add(1);
    }
    fn disconnected(&mut self) {
        if self.active {
            self.failed = true;
            self.stage = "Connection interrupted; verify transfer over SSH/ACM".into();
            self.generation = self.generation.wrapping_add(1);
        }
    }
}

fn clean(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !ch.is_control() || *ch == ' ')
        .take(180)
        .collect()
}

pub struct StatusSocket {
    listener: UnixListener,
    stream: Option<UnixStream>,
    pending: Vec<u8>,
    pub status: UpdateStatus,
}

impl StatusSocket {
    pub fn open() -> io::Result<Self> {
        fs::create_dir_all("/run/mobile-recovery")?;
        let path = Path::new(SOCKET);
        if path.exists() {
            // Only the recovery screen owns this socket. A previous process may
            // have left its pathname after a crash.
            fs::remove_file(path)?;
        }
        let listener = UnixListener::bind(path)?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        listener.set_nonblocking(true)?;
        Ok(Self {
            listener,
            stream: None,
            pending: Vec::new(),
            status: UpdateStatus::default(),
        })
    }
    pub fn fds(&self) -> Vec<RawFd> {
        let mut fds = vec![self.listener.as_raw_fd()];
        if let Some(stream) = &self.stream {
            fds.push(stream.as_raw_fd());
        }
        fds
    }
    pub fn handle(&mut self, ready: &[RawFd]) -> io::Result<bool> {
        let generation = self.status.generation;
        if ready.contains(&self.listener.as_raw_fd()) {
            while let Ok((stream, _)) = self.listener.accept() {
                if self.stream.is_none() {
                    stream.set_nonblocking(true)?;
                    self.stream = Some(stream);
                    self.pending.clear();
                }
            }
        }
        if let Some(stream) = &mut self.stream {
            if ready.contains(&stream.as_raw_fd()) {
                let mut buffer = [0u8; 4096];
                loop {
                    match stream.read(&mut buffer) {
                        Ok(0) => {
                            self.stream = None;
                            self.pending.clear();
                            self.status.disconnected();
                            break;
                        }
                        Ok(length) => {
                            self.pending.extend_from_slice(&buffer[..length]);
                            while let Some(end) =
                                self.pending.iter().position(|byte| *byte == b'\n')
                            {
                                let line: Vec<_> = self.pending.drain(..=end).collect();
                                if line.len() <= MAX_LINE {
                                    if let Ok(line) = std::str::from_utf8(&line[..line.len() - 1]) {
                                        self.status.line(line);
                                    }
                                }
                            }
                            if self.pending.len() > MAX_LINE {
                                self.stream = None;
                                self.pending.clear();
                                self.status.disconnected();
                                break;
                            }
                        }
                        Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                        Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                        Err(_) => {
                            self.stream = None;
                            self.pending.clear();
                            self.status.disconnected();
                            break;
                        }
                    }
                }
            }
        }
        Ok(self.status.generation != generation)
    }
}

impl Drop for StatusSocket {
    fn drop(&mut self) {
        let _ = fs::remove_file(SOCKET);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_and_disconnect_are_bounded() {
        let mut status = UpdateStatus::default();
        status.line("start\tPreparing copy");
        status.line("progress\t1\t3\t5\t10");
        status.line("progress\t4\t3\t20\t10");
        assert_eq!(
            (status.done_paths, status.total_paths, status.path_bytes),
            (1, 3, 5)
        );
        for _ in 0..100 {
            status.line("log\tcopying path");
        }
        assert_eq!(status.logs.len(), 80);
        status.disconnected();
        assert!(status.failed && status.active);
        status.line("start\tRetry");
        status.line("done");
        status.disconnected();
        assert!(status.finished && !status.failed);
    }
}
