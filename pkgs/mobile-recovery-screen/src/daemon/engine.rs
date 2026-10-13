//! One worker owns mutations and child lifetimes. Disconnected watchers own no work.
use super::{protocol::*, storage::Config};
use anyhow::{bail, ensure, Context, Result};
use std::{
    collections::VecDeque,
    fs,
    io::{BufReader, Read},
    os::{
        fd::AsRawFd,
        unix::{
            fs::PermissionsExt,
            net::{UnixListener, UnixStream},
            process::CommandExt,
        },
    },
    process::{Command as Process, Stdio},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc, Arc, Condvar, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

struct State {
    snapshot: Snapshot,
    next: u64,
    fault: Option<String>,
    history: VecDeque<Task>,
    input: Option<(u64, String, mpsc::Sender<UnixStream>)>,
}
struct ChildGuard {
    child: std::process::Child,
    finished: bool,
}
impl std::ops::Deref for ChildGuard {
    type Target = std::process::Child;
    fn deref(&self) -> &Self::Target {
        &self.child
    }
}
impl std::ops::DerefMut for ChildGuard {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.child
    }
}
impl ChildGuard {
    fn finish(&mut self) {
        unsafe {
            libc::kill(-(self.child.id() as i32), libc::SIGKILL);
        }
        let _ = self.child.wait();
        self.finished = true;
    }
}
impl Drop for ChildGuard {
    fn drop(&mut self) {
        if !self.finished {
            self.finish();
        }
    }
}
pub struct Engine {
    state: Mutex<State>,
    changed: Condvar,
    pub config: Config,
}
#[derive(Clone)]
pub struct Job {
    pub engine: Arc<Engine>,
    pub id: u64,
}
impl Engine {
    pub fn new(config: Config) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(State {
                snapshot: Snapshot::default(),
                next: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .expect("clock before epoch")
                    .as_nanos() as u64,
                history: VecDeque::new(),
                fault: None,
                input: None,
            }),
            changed: Condvar::new(),
            config,
        })
    }
    pub fn fault(&self, reason: String) {
        let mut state = self.state.lock().unwrap();
        state.fault = Some(reason.clone());
        if let Some(task) = state.snapshot.task.as_mut() {
            task.logs.push(reason);
        }
        state.snapshot.sequence += 1;
        self.changed.notify_all();
    }
    pub fn snapshot(&self) -> Snapshot {
        self.state.lock().unwrap().snapshot.clone()
    }
    fn update(&self, id: u64, f: impl FnOnce(&mut Task)) {
        let mut s = self.state.lock().unwrap();
        if let Some(t) = s.snapshot.task.as_mut() {
            if t.id == id {
                f(t);
                s.snapshot.sequence += 1;
                self.changed.notify_all();
            }
        }
    }
    pub fn cancel(&self, id: u64) -> Result<()> {
        let mut s = self.state.lock().unwrap();
        let t = s.snapshot.task.as_mut().context("no task")?;
        ensure!(t.id == id && t.active, "task is no longer active");
        ensure!(t.cancellable, "this phase cannot be cancelled");
        t.cancelled = true;
        s.snapshot.sequence += 1;
        self.changed.notify_all();
        Ok(())
    }
    pub fn submit(self: &Arc<Self>, args: Vec<String>, input: bool) -> Result<Response> {
        super::operations::validate(&args, input)?;
        self.start(args, input, super::operations::execute)
    }
    fn start<F>(self: &Arc<Self>, args: Vec<String>, input: bool, work: F) -> Result<Response>
    where
        F: FnOnce(&Job, &[String], Option<mpsc::Receiver<UnixStream>>) -> Result<String>
            + Send
            + 'static,
    {
        let mut s = self.state.lock().unwrap();
        ensure!(s.fault.is_none(), "daemon is blocked after incomplete cleanup: {:?}; inspect mounts/children before restarting the service", s.fault);
        ensure!(
            !s.snapshot.task.as_ref().is_some_and(|t| t.active),
            "another task is active; inspect returned snapshot"
        );
        if let Some(previous) = s.snapshot.task.take() {
            s.history.push_back(previous);
            if s.history.len() > 32 {
                s.history.pop_front();
            }
        }
        let id = s.next;
        s.next += 1;
        let (tx, rx) = mpsc::channel();
        let token = if input {
            Some(
                fs::read_to_string("/proc/sys/kernel/random/uuid")?
                    .trim()
                    .to_string(),
            )
        } else {
            None
        };
        s.input = token.as_ref().map(|t| (id, t.clone(), tx));
        s.snapshot.task = Some(Task {
            id,
            operation: args[0].clone(),
            target: self.config.identity.clone(),
            phase: "Checking request".into(),
            active: true,
            cancellable: true,
            cancelled: false,
            completed: 0,
            total: None,
            logs: Vec::new(),
            result: None,
            error: None,
        });
        s.snapshot.sequence += 1;
        let reply = Response {
            version: VERSION,
            snapshot: s.snapshot.clone(),
            error: None,
            token,
            capabilities: None,
        };
        let job = Job {
            engine: self.clone(),
            id,
        };
        thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                work(&job, &args, if input { Some(rx) } else { None })
            }));
            let result = match result {
                Ok(r) => r,
                Err(_) => {
                    job.engine.fault(
                        "Worker panicked; inspect mounts and children before restarting".into(),
                    );
                    Err(anyhow::anyhow!("worker panicked"))
                }
            };
            let result = result.and_then(|value| {
                job.check()?;
                ensure!(value.len() <= 16 * 1024 * 1024, "task result exceeds limit");
                Ok(value)
            });
            job.engine.state.lock().unwrap().input = None;
            job.engine.update(id, |t| {
                t.active = false;
                t.cancellable = false;
                match result {
                    Ok(value) => {
                        t.phase = "Complete".into();
                        t.result = Some(value)
                    }
                    Err(e) => {
                        t.phase = "Failed".into();
                        t.error = Some(format!("{e:#}"));
                    }
                }
            });
        });
        Ok(reply)
    }
    fn task(&self, id: u64) -> Result<Snapshot> {
        let s = self.state.lock().unwrap();
        let task = s
            .snapshot
            .task
            .iter()
            .chain(s.history.iter())
            .find(|t| t.id == id)
            .context("task is unknown or no longer retained")?
            .clone();
        Ok(Snapshot {
            sequence: s.snapshot.sequence,
            task: Some(task),
        })
    }
    fn connect_input(&self, id: u64, token: &str, stream: UnixStream) -> Result<()> {
        let mut s = self.state.lock().unwrap();
        let (expected, secret, _) = s.input.as_ref().context("task is not waiting for input")?;
        ensure!(
            *expected == id && secret == token,
            "input task/token mismatch"
        );
        let (_, _, sender) = s.input.take().unwrap();
        sender
            .send(stream)
            .map_err(|_| anyhow::anyhow!("task stopped accepting input"))?;
        Ok(())
    }
    fn watch(&self, after: u64) -> Snapshot {
        let s = self.state.lock().unwrap();
        let (s, _) = self
            .changed
            .wait_timeout_while(s, Duration::from_secs(20), |s| s.snapshot.sequence <= after)
            .unwrap();
        s.snapshot.clone()
    }
}
impl Job {
    pub fn phase(&self, name: &str, cancellable: bool) -> Result<()> {
        let mut s = self.engine.state.lock().unwrap();
        let t = s.snapshot.task.as_mut().context("missing task")?;
        ensure!(!t.cancelled, "task cancelled");
        t.phase = name.into();
        t.cancellable = cancellable;
        t.completed = 0;
        t.total = None;
        s.snapshot.sequence += 1;
        self.engine.changed.notify_all();
        Ok(())
    }
    pub fn check(&self) -> Result<()> {
        ensure!(
            !self
                .engine
                .snapshot()
                .task
                .is_some_and(|t| t.id == self.id && t.cancelled),
            "task cancelled"
        );
        Ok(())
    }
    pub fn log(&self, line: &str) {
        self.engine.update(self.id, |t| {
            t.logs
                .push(line.chars().filter(|c| !c.is_control()).take(500).collect());
            if t.logs.len() > 80 {
                t.logs.remove(0);
            }
        });
    }
    pub fn progress(&self, done: u64, total: Option<u64>) {
        self.engine.update(self.id, |t| {
            t.completed = done;
            t.total = total;
        });
    }
    pub fn input(&self, rx: mpsc::Receiver<UnixStream>) -> Result<FramedInput> {
        self.phase("Receiving input", true)?;
        let start = Instant::now();
        loop {
            self.check()?;
            match rx.recv_timeout(Duration::from_millis(100)) {
                Ok(stream) => {
                    stream.set_read_timeout(Some(Duration::from_secs(1)))?;
                    return Ok(FramedInput {
                        stream,
                        remaining: 0,
                        ended: false,
                        job: self.clone(),
                        received: 0,
                        last: Instant::now(),
                    });
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => bail!("input channel closed"),
                Err(_) => ensure!(
                    start.elapsed() < Duration::from_secs(60),
                    "input did not connect"
                ),
            }
        }
    }
    pub fn run(&self, cmd: &mut Process, input: Option<Box<dyn Read + Send>>) -> Result<String> {
        self.run_codes(cmd, input, &[0])
    }
    pub fn run_codes(
        &self,
        cmd: &mut Process,
        input: Option<Box<dyn Read + Send>>,
        accepted: &[i32],
    ) -> Result<String> {
        self.check()?;
        let program = cmd.get_program().to_string_lossy().to_string();
        cmd.stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
        let mut child = ChildGuard {
            child: cmd.spawn().with_context(|| format!("start {program}"))?,
            finished: false,
        };
        let writer = input.map(|mut source| {
            let mut dest = child.stdin.take().unwrap();
            thread::spawn(move || -> std::io::Result<()> {
                let result = std::io::copy(&mut source, &mut dest);
                drop(dest);
                match result {
                    Ok(_) => Ok(()),
                    Err(e) => {
                        let _ = std::io::copy(&mut source, &mut std::io::sink());
                        Err(e)
                    }
                }
            })
        });
        let out = child.stdout.take().unwrap();
        let err = child.stderr.take().unwrap();
        let j = self.clone();
        let stdout = thread::spawn(move || bounded_output(out));
        let stderr = thread::spawn(move || {
            let mut r = BufReader::new(err);
            let mut b = [0u8; 4096];
            let mut tail = VecDeque::new();
            while let Ok(n) = r.read(&mut b) {
                if n == 0 {
                    break;
                }
                j.log(&String::from_utf8_lossy(&b[..n]));
                for c in &b[..n] {
                    tail.push_back(*c);
                    if tail.len() > 8192 {
                        tail.pop_front();
                    }
                }
            }
            String::from_utf8_lossy(&tail.into_iter().collect::<Vec<_>>()).into_owned()
        });
        let status = loop {
            if self.check().is_err() {
                unsafe {
                    libc::kill(-(child.id() as i32), libc::SIGKILL);
                }
            }
            if let Some(s) = child.try_wait()? {
                break s;
            }
            thread::sleep(Duration::from_millis(50));
        };
        child.finish();
        let input_result = writer
            .map(|t| {
                t.join()
                    .map_err(|_| anyhow::anyhow!("input worker panicked"))
            })
            .transpose()?
            .transpose();
        let output = stdout
            .join()
            .map_err(|_| anyhow::anyhow!("stdout worker panicked"))??;
        let error = stderr.join().unwrap_or_default();
        self.check()?;
        if !status.code().is_some_and(|code| accepted.contains(&code)) {
            let tail: String = output
                .chars()
                .rev()
                .take(8192)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect();
            bail!("{program} failed: {status}: {error}\n{tail}");
        }
        input_result?;
        Ok(output)
    }
}
fn bounded_output(mut r: impl Read) -> Result<String> {
    let mut all = Vec::new();
    let mut b = [0; 8192];
    let mut overflow = false;
    loop {
        let n = r.read(&mut b)?;
        if n == 0 {
            break;
        }
        if all.len() + n <= 16 * 1024 * 1024 {
            all.extend_from_slice(&b[..n]);
        } else {
            overflow = true;
        }
    }
    ensure!(!overflow, "command output exceeded 16 MiB");
    Ok(String::from_utf8(all)?)
}
pub struct FramedInput {
    stream: UnixStream,
    remaining: usize,
    ended: bool,
    job: Job,
    received: u64,
    last: Instant,
}
impl FramedInput {
    fn bytes(&mut self, b: &mut [u8]) -> std::io::Result<usize> {
        loop {
            self.job.check().map_err(std::io::Error::other)?;
            match self.stream.read(b) {
                Ok(n) => {
                    self.last = Instant::now();
                    return Ok(n);
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    if self.last.elapsed() > Duration::from_secs(60) {
                        return Err(std::io::Error::new(
                            std::io::ErrorKind::TimedOut,
                            "input stalled",
                        ));
                    }
                }
                Err(e) => return Err(e),
            }
        }
    }
}
impl Read for FramedInput {
    fn read(&mut self, b: &mut [u8]) -> std::io::Result<usize> {
        if b.is_empty() || self.ended {
            return Ok(0);
        }
        if self.remaining == 0 {
            let mut header = [0; 4];
            let mut n = 0;
            while n < 4 {
                let count = self.bytes(&mut header[n..])?;
                if count == 0 {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::UnexpectedEof,
                        "input disconnected before completion frame",
                    ));
                }
                n += count;
            }
            self.remaining = u32::from_be_bytes(header) as usize;
            if self.remaining == 0 {
                self.ended = true;
                return Ok(0);
            }
            if self.remaining > 65536 {
                return Err(std::io::Error::other("oversized input frame"));
            }
        }
        let size = b.len().min(self.remaining);
        let n = self.bytes(&mut b[..size])?;
        if n == 0 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "short input frame",
            ));
        }
        self.remaining -= n;
        self.received += n as u64;
        self.job.progress(self.received, None);
        Ok(n)
    }
}
pub fn serve(config: Config) -> Result<()> {
    fs::create_dir_all("/run/mobile-recovery")?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open("/run/mobile-recovery/daemon.lock")?;
    ensure!(
        unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0,
        "another daemon owns the lock"
    );
    let _ = fs::remove_file(SOCKET);
    let listener = UnixListener::bind(SOCKET)?;
    fs::set_permissions(SOCKET, fs::Permissions::from_mode(0o600))?;
    let engine = Engine::new(config);
    let count = Arc::new(AtomicUsize::new(0));
    for stream in listener.incoming() {
        let stream = stream?;
        if count.fetch_add(1, Ordering::SeqCst) >= 32 {
            count.fetch_sub(1, Ordering::SeqCst);
            continue;
        }
        let e = engine.clone();
        let c = count.clone();
        thread::spawn(move || {
            let _ = connection(e, stream);
            c.fetch_sub(1, Ordering::SeqCst);
        });
    }
    Ok(())
}
fn connection(e: Arc<Engine>, mut stream: UnixStream) -> Result<()> {
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    let mut credential: libc::ucred = unsafe { std::mem::zeroed() };
    let mut size = std::mem::size_of_val(&credential) as libc::socklen_t;
    ensure!(
        unsafe {
            libc::getsockopt(
                stream.as_raw_fd(),
                libc::SOL_SOCKET,
                libc::SO_PEERCRED,
                (&mut credential as *mut libc::ucred).cast(),
                &mut size,
            )
        } == 0
            && credential.uid == 0,
        "root client required"
    );
    // One-byte buffer prevents reading data-channel bytes beyond the JSON line.
    let request: Request = read_json(&mut BufReader::with_capacity(1, &mut stream))?;
    ensure!(request.version == VERSION, "unsupported protocol version");
    let result: Result<Response> = (|| {
        let mut r = Response {
            version: VERSION,
            snapshot: e.snapshot(),
            error: None,
            token: None,
            capabilities: None,
        };
        match request.command {
            Command::Capabilities => r.capabilities = Some(super::operations::capabilities()),
            Command::Status => {}
            Command::Task { id } => r.snapshot = e.task(id)?,
            Command::Watch { after } => r.snapshot = e.watch(after),
            Command::Cancel { id } => {
                e.cancel(id)?;
                r.snapshot = e.snapshot();
            }
            Command::Submit { args, input } => return e.submit(args, input),
            Command::Input { id, token } => {
                e.connect_input(id, &token, stream.try_clone()?)?;
            }
        }
        Ok(r)
    })();
    let reply = result.unwrap_or_else(|err| Response {
        version: VERSION,
        snapshot: e.snapshot(),
        error: Some(format!("{err:#}")),
        token: None,
        capabilities: None,
    });
    write_json(&mut stream, &reply)
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    fn engine() -> Arc<Engine> {
        Engine::new(Config {
            identity: "fixture".into(),
            compatible: "test,board".into(),
            controller: "ufs".into(),
            hostname: "fixture".into(),
            root_label: "ROOT".into(),
            esp_bytes: 1 << 30,
            minimum_root_bytes: 16 << 30,
            slot_metadata: "qcom-gpt".into(),
            misc_bytes: 4194304,
            recovery_avb: false,
            ..Default::default()
        })
    }
    fn finish(e: &Engine, id: u64) -> Task {
        let start = Instant::now();
        loop {
            let t = e.task(id).unwrap().task.unwrap();
            if !t.active {
                return t;
            }
            assert!(
                start.elapsed() < Duration::from_secs(5),
                "task did not stop"
            );
            thread::sleep(Duration::from_millis(5));
        }
    }
    #[test]
    fn tool_exit_policy_preserves_fsck_diagnostics() {
        for (code, accepted, ok) in [
            (0, vec![0], true),
            (1, vec![0], false),
            (1, vec![0, 1], true),
            (2, vec![0, 1], false),
            (4, vec![0, 1], false),
        ] {
            let e = engine();
            let r = e
                .start(vec!["test".into()], false, move |j, _, _| {
                    j.run_codes(
                        Process::new("sh")
                            .args(["-c", &format!("echo filesystem-diagnostic; exit {code}")]),
                        None,
                        &accepted,
                    )
                })
                .unwrap();
            let task = finish(&e, r.snapshot.task.unwrap().id);
            assert_eq!(task.error.is_none(), ok);
            assert!(task
                .result
                .or(task.error)
                .unwrap()
                .contains("filesystem-diagnostic"));
        }
    }
    #[test]
    fn exclusive_worker_survives_clients_and_retains_result() {
        let e = engine();
        let (tx, rx) = mpsc::channel();
        let (ready, wait) = mpsc::channel();
        let r = e
            .start(vec!["test".into()], false, move |j, _, _| {
                j.phase("Critical write", false)?;
                ready.send(()).unwrap();
                rx.recv().unwrap();
                Ok("verified".into())
            })
            .unwrap();
        let id = r.snapshot.task.unwrap().id;
        drop(r.token);
        wait.recv().unwrap();
        assert!(e
            .start(vec!["other".into()], false, |_, _, _| Ok("bad".into()))
            .is_err());
        assert!(e.cancel(id).is_err());
        let seq = e.snapshot().sequence;
        tx.send(()).unwrap();
        assert_eq!(finish(&e, id).result.as_deref(), Some("verified"));
        assert!(e.snapshot().sequence > seq);
        let next = e
            .start(vec!["other".into()], false, |_, _, _| Ok("next".into()))
            .unwrap();
        finish(&e, next.snapshot.task.unwrap().id);
        assert_eq!(
            e.task(id).unwrap().task.unwrap().result.as_deref(),
            Some("verified")
        );
    }
    #[test]
    fn child_error_and_cancel_are_observed_after_exit() {
        let e = engine();
        let r = e
            .start(vec!["fail".into()], false, |j, _, _| {
                j.run(
                    Process::new("sh").args(["-c", "echo child-error >&2; exit 7"]),
                    None,
                )
            })
            .unwrap();
        let t = finish(&e, r.snapshot.task.unwrap().id);
        assert!(t.error.unwrap().contains("child-error"));
        let (tx, rx) = mpsc::channel();
        let r = e
            .start(vec!["cancel".into()], false, move |j, _, _| {
                tx.send(()).unwrap();
                j.run(Process::new("sh").args(["-c", "sleep 30 & wait"]), None)
            })
            .unwrap();
        let id = r.snapshot.task.unwrap().id;
        rx.recv().unwrap();
        e.cancel(id).unwrap();
        assert!(finish(&e, id).error.unwrap().contains("cancelled"));
    }
    fn transfer(bytes: &[u8]) -> Task {
        let e = engine();
        let r = e
            .start(vec!["receive".into()], true, |j, _, rx| {
                let mut reader = j.input(rx.unwrap())?;
                let mut value = String::new();
                reader.read_to_string(&mut value)?;
                j.phase("Local install", false)?;
                Ok(value)
            })
            .unwrap();
        let id = r.snapshot.task.unwrap().id;
        let (mut peer, stream) = UnixStream::pair().unwrap();
        e.connect_input(id, &r.token.unwrap(), stream).unwrap();
        peer.write_all(bytes).unwrap();
        drop(peer);
        finish(&e, id)
    }
    #[test]
    fn completion_frame_distinguishes_disconnect_from_complete_input() {
        assert_eq!(
            transfer(b"\0\0\0\x03abc\0\0\0\0").result.as_deref(),
            Some("abc")
        );
        assert!(transfer(b"\0\0\0\x03abc")
            .error
            .unwrap()
            .contains("completion frame"));
        assert!(transfer(b"\0\0\0\x05abc").error.is_some());
        assert!(transfer(b"\0\x02\0\0").error.unwrap().contains("oversized"));
    }
    #[test]
    fn input_tokens_are_single_use_and_bound_to_task() {
        let e = engine();
        let r = e
            .start(vec!["receive".into()], true, |j, _, rx| {
                let mut r = j.input(rx.unwrap())?;
                std::io::copy(&mut r, &mut std::io::sink())?;
                Ok("complete".into())
            })
            .unwrap();
        let id = r.snapshot.task.unwrap().id;
        let token = r.token.unwrap();
        let (mut peer, stream) = UnixStream::pair().unwrap();
        assert!(e
            .connect_input(id + 1, &token, stream.try_clone().unwrap())
            .is_err());
        assert!(e
            .connect_input(id, "wrong", stream.try_clone().unwrap())
            .is_err());
        e.connect_input(id, &token, stream.try_clone().unwrap())
            .unwrap();
        assert!(e.connect_input(id, &token, stream).is_err());
        peer.write_all(&[0; 4]).unwrap();
        assert!(finish(&e, id).error.is_none());
    }
    #[test]
    fn bounded_logs_and_reconnect_snapshot() {
        let e = engine();
        let r = e
            .start(vec!["log".into()], false, |j, _, _| {
                for _ in 0..200 {
                    j.log(&"a".repeat(1000));
                }
                Ok("done".into())
            })
            .unwrap();
        let id = r.snapshot.task.unwrap().id;
        let t = finish(&e, id);
        assert_eq!(t.logs.len(), 80);
        assert!(t.logs.iter().all(|s| s.len() == 500));
        let snapshot = e.watch(0);
        assert_eq!(snapshot.task.unwrap().id, id);
    }
}
