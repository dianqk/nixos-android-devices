//! UI subscribes to daemon snapshots. It never binds a status socket.
use mobile_recovery_screen::daemon::{
    client,
    protocol::{Command, Snapshot},
};
use std::{
    collections::VecDeque,
    io,
    os::fd::RawFd,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};
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
pub struct StatusSocket {
    shared: Arc<Mutex<Option<Snapshot>>>,
    pub status: UpdateStatus,
}
impl StatusSocket {
    pub fn open() -> io::Result<Self> {
        let shared = Arc::new(Mutex::new(None));
        let target = shared.clone();
        thread::spawn(move || {
            let mut after = 0;
            loop {
                match client::request(Command::Watch { after }) {
                    Ok(reply) => {
                        after = reply.snapshot.sequence;
                        *target.lock().unwrap() = Some(reply.snapshot);
                    }
                    Err(_) => {
                        after = 0;
                        thread::sleep(Duration::from_secs(1));
                    }
                }
            }
        });
        Ok(Self {
            shared,
            status: UpdateStatus::default(),
        })
    }
    pub fn fds(&self) -> Vec<RawFd> {
        Vec::new()
    }
    pub fn handle(&mut self, _ready: &[RawFd]) -> io::Result<bool> {
        let Some(s) = self.shared.lock().unwrap().take() else {
            return Ok(false);
        };
        if self.status.generation == s.sequence {
            return Ok(false);
        }
        self.status.generation = s.sequence;
        if let Some(t) = s.task {
            self.status.session_id = t.id;
            self.status.stage = format!("#{} {}", t.id, t.phase);
            self.status.active = t.active;
            self.status.finished = !t.active && t.error.is_none();
            self.status.failed = t.error.is_some();
            self.status.done_paths = t.completed;
            self.status.total_paths = t.total.unwrap_or(0);
            self.status.logs = t.logs.into();
            if let Some(e) = t.error {
                self.status.logs.push_back(e)
            }
            if let Some(r) = t.result {
                self.status.logs.push_back(r)
            }
        }
        Ok(true)
    }
}
