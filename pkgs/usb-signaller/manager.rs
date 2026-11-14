// SPDX-License-Identifier: GPL-3.0-or-later
// All mutations (startup, D-Bus, Type-C and shutdown) run on one worker.
use anyhow::{bail, ensure, Context, Result};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use crate::gadget::ConfigFsGadget;
use crate::sysfs::{sysfs_read, sysfs_write};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Developer,
    Charging,
    Host,
    Mtp,
    Tethering,
    HidTouch,
    MassStorage,
    Uvc,
}
impl Mode {
    pub fn parse(s: &str) -> Result<Self> {
        Ok(match s {
            "developer_mode" => Self::Developer,
            "charging_only" => Self::Charging,
            "host_mode" => Self::Host,
            "mtp_ffs_mode" => Self::Mtp,
            "tethering_mode" => Self::Tethering,
            "hid_touch_mode" => Self::HidTouch,
            "mass_storage_mode" => Self::MassStorage,
            "uvc_mode" => Self::Uvc,
            _ => bail!("Unsupported mode: {s}"),
        })
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Developer => "developer_mode",
            Self::Charging => "charging_only",
            Self::Host => "host_mode",
            Self::Mtp => "mtp_ffs_mode",
            Self::Tethering => "tethering_mode",
            Self::HidTouch => "hid_touch_mode",
            Self::MassStorage => "mass_storage_mode",
            Self::Uvc => "uvc_mode",
        }
    }
    fn gadget(self) -> Option<&'static str> {
        match self {
            Self::Developer => Some("usb-signaller-developer"),
            Self::Tethering => Some("usb-signaller-tethering"),
            Self::Mtp => Some("usb-signaller-mtp"),
            Self::HidTouch => Some("usb-signaller-touch"),
            Self::MassStorage => Some("usb-signaller-storage"),
            Self::Uvc => Some("usb-signaller-uvc"),
            _ => None,
        }
    }
    fn extra(self) -> Option<&'static str> {
        match self {
            Self::HidTouch => Some("touch"),
            Self::MassStorage => Some("storage"),
            Self::Uvc => Some("uvc"),
            _ => None,
        }
    }
}

const GADGET_MODES: [Mode; 6] = [
    Mode::Developer,
    Mode::Mtp,
    Mode::Tethering,
    Mode::HidTouch,
    Mode::MassStorage,
    Mode::Uvc,
];

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Observation {
    pub controller: String,
    pub data: String,
    pub power: String,
    pub partner: String,
    pub firmware: String,
    pub udc_state: String,
    pub actual: String,
    pub bound: bool,
    pub policy: bool,
    pub backend_ready: bool,
    pub read_only: bool,
}
impl Observation {
    fn permits_gadget(&self) -> bool {
        self.controller == "device"
            && !self.firmware.ends_with(":0")
            && (self.partner.is_empty() || self.data == "device")
    }
}

pub trait Backend {
    fn observe(&self) -> Result<Observation>;
    fn role(&mut self, mode: Mode, explicit: bool) -> Result<()>;
    fn teardown(&mut self) -> Result<()>;
    fn install(&mut self, mode: Mode) -> Result<()>;
}

pub struct Engine<B> {
    pub backend: B,
    pub desired: Mode,
    pub error: String,
}
impl<B: Backend> Engine<B> {
    // The old gadget is gone before creating anything, including a gadget with
    // the same name. A partially created gadget is also cleaned on every error.
    pub fn transition(&mut self, mode: Mode, explicit: bool) -> Result<()> {
        let before = self.backend.observe()?;
        ensure!(
            !before.read_only,
            "Connected NBD netboot keeps USB read-only"
        );
        let previous = Mode::parse(&before.actual).ok();
        self.desired = mode;
        let result = (|| {
            self.backend.teardown()?;
            self.backend.role(mode, explicit)?;
            self.backend.install(mode)
        })();
        if let Err(error) = result {
            let mut detail = format!("{error:#}");
            match self.backend.teardown() {
                Err(cleanup) => detail.push_str(&format!("; cleanup: {cleanup:#}")),
                Ok(()) => {
                    // Do not swap roles again on rollback or bind after detach,
                    // firmware restart, or a new partner replacing the old one.
                    let now = self.backend.observe()?;
                    if now.partner == before.partner
                        && now.firmware == before.firmware
                        && now.permits_gadget()
                    {
                        if let Some(old) = previous.filter(|m| m.gadget().is_some()) {
                            if let Err(rollback) = self.backend.install(old) {
                                detail.push_str(&format!("; rollback: {rollback:#}"));
                                if let Err(cleanup) = self.backend.teardown() {
                                    detail.push_str(&format!("; rollback cleanup: {cleanup:#}"));
                                }
                            }
                        }
                    }
                }
            }
            self.error = detail.clone();
            bail!("{detail}");
        }
        self.error.clear();
        Ok(())
    }
}

fn env(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.into())
}
fn read(path: impl AsRef<Path>) -> String {
    sysfs_read(path).unwrap_or_default()
}
fn extra_ready(kind: &str) -> bool {
    let identity = read(format!("/run/usb-signaller/{kind}.ready"));
    let mut fields = identity.split_whitespace();
    let Some(pid) = fields.next().and_then(|s| s.parse::<u32>().ok()) else {
        return false;
    };
    let Some(start) = fields.next() else {
        return false;
    };
    let stat = read(format!("/proc/{pid}/stat"));
    let Some((_, tail)) = stat.rsplit_once(')') else {
        return false;
    };
    let values: Vec<_> = tail.split_whitespace().collect();
    values.get(19) == Some(&start) && !matches!(values.first(), Some(&"Z" | &"X"))
}
fn selected_role(value: &str) -> String {
    value
        .split_whitespace()
        .find_map(|x| x.strip_prefix('[')?.strip_suffix(']'))
        .unwrap_or_else(|| {
            if value.split_whitespace().count() == 1 {
                value
            } else {
                "unknown"
            }
        })
        .into()
}
fn entries(path: impl AsRef<Path>) -> Vec<PathBuf> {
    fs::read_dir(path)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .collect()
}
fn run(command: &mut Command) -> Result<()> {
    let description = format!("{command:?}");
    let mut child = command
        .stdin(Stdio::null())
        .spawn()
        .with_context(|| description.clone())?;
    let until = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(status) = child.try_wait()? {
            ensure!(status.success(), "{description}: {status}");
            return Ok(());
        }
        if Instant::now() >= until {
            let _ = child.kill();
            let _ = child.wait();
            bail!("{description}: timeout (systemd cleanup may still be pending)");
        }
        thread::sleep(Duration::from_millis(20));
    }
}
fn systemctl(action: &str, unit: &str) -> Result<()> {
    run(Command::new("@systemctl@").args([action, unit]))
}

fn extra_backend(action: &str, kind: &str) -> Result<()> {
    let executable = env("USB_SIGNALLER_GADGET_BACKEND", "");
    ensure!(
        !executable.is_empty(),
        "Extra gadget backend is not configured"
    );
    run(Command::new(executable).args([action, kind]))
}

pub struct LinuxBackend {
    udc: String,
    switch: String,
    port: PathBuf,
    follow: bool,
}
impl LinuxBackend {
    pub fn new() -> Self {
        Self {
            udc: env("USB_SIGNALLER_UDC", "a600000.usb"),
            switch: env("USB_SIGNALLER_ROLE_SWITCH", "a600000.usb-role-switch"),
            port: PathBuf::from("/sys/class/typec").join(env("USB_SIGNALLER_TYPEC_PORT", "port0")),
            follow: env("USB_SIGNALLER_FOLLOW_ROLE", "0") == "1",
        }
    }
    fn root(&self) -> PathBuf {
        PathBuf::from("/sys/kernel/config/usb_gadget")
    }
    fn controller(&self) -> String {
        let role = read(
            Path::new("/sys/class/usb_role")
                .join(&self.switch)
                .join("role"),
        );
        if role.is_empty() && !self.follow && Path::new("/sys/class/udc").join(&self.udc).exists() {
            "device".into()
        } else {
            role
        }
    }
    fn partner(&self) -> String {
        let partner = self.port.with_file_name(format!(
            "{}-partner",
            self.port.file_name().unwrap().to_string_lossy()
        ));
        use std::os::unix::fs::MetadataExt;
        fs::metadata(&partner)
            .map(|m| format!("{}:{}", partner.display(), m.ino()))
            .unwrap_or_default()
    }
    fn service_for(mode: Mode) -> &'static str {
        match mode {
            Mode::Mtp => "usb-signaller-mtp-mode.service",
            Mode::Tethering => "usb-signaller-tethering-mode.service",
            Mode::HidTouch => "usb-signaller-touch-mode.service",
            Mode::MassStorage => "usb-signaller-storage-mode.service",
            Mode::Uvc => "usb-signaller-uvc-mode.service",
            _ => "usb-signaller-developer-mode.service",
        }
    }
    fn owned(&self) -> Result<Vec<PathBuf>> {
        let mut paths = Vec::new();
        for mode in GADGET_MODES {
            let path = self.root().join(mode.gadget().unwrap());
            if path.exists() {
                let binding = sysfs_read(path.join("UDC"))?;
                ensure!(
                    binding.is_empty() || binding == self.udc,
                    "Owned gadget bound to another controller: {binding}"
                );
                paths.push(path);
            }
        }
        Ok(paths)
    }
}
impl Backend for LinuxBackend {
    fn observe(&self) -> Result<Observation> {
        let partner = self.partner();
        let controller = self.controller();
        let data = selected_role(&read(self.port.join("data_role")));
        let mut actual = if controller == "host" && (!self.follow || data == "host") {
            "host_mode".to_string()
        } else {
            "charging_only".to_string()
        };
        let mut bound = false;
        let mut backend_ready = true;
        let policy = Path::new("/run/usb-signaller/tethering.ready").exists();
        for path in self.owned()? {
            if read(path.join("UDC")) != self.udc {
                continue;
            }
            bound = true;
            let config = path.join("configs/c.1");
            let ncm = config.join("ncm.usb0").exists();
            actual = if config.join("ffs.mtp").exists() {
                backend_ready = read(path.join("functions/ffs.mtp/ready")) == "1";
                if backend_ready {
                    "mtp_ffs_mode"
                } else {
                    "unknown_mode"
                }
            } else if ncm && path.ends_with("usb-signaller-tethering") && policy {
                "tethering_mode"
            } else if ncm && path.ends_with("usb-signaller-developer") && !policy {
                "developer_mode"
            } else if config.join("hid.touch").exists() {
                backend_ready = extra_ready("touch");
                if backend_ready {
                    "hid_touch_mode"
                } else {
                    "unknown_mode"
                }
            } else if config.join("mass_storage.disk").exists() {
                backend_ready = extra_ready("storage");
                if backend_ready {
                    "mass_storage_mode"
                } else {
                    "unknown_mode"
                }
            } else if config.join("uvc.video").exists() {
                backend_ready = extra_ready("uvc");
                if backend_ready {
                    "uvc_mode"
                } else {
                    "unknown_mode"
                }
            } else {
                "unknown_mode"
            }
            .into();
        }
        let firmware = entries("/sys/devices/platform/pmic-glink")
            .into_iter()
            .filter(|p| p.join("xiaomi/firmware_generation").exists())
            .map(|p| {
                format!(
                    "{}:{}",
                    read(p.join("xiaomi/firmware_generation")),
                    read(p.join("xiaomi/service_up"))
                )
            })
            .next()
            .unwrap_or_default();
        Ok(Observation {
            controller,
            data,
            partner,
            actual,
            bound,
            policy,
            firmware,
            backend_ready,
            read_only: Path::new("/sys/block/nbd0/pid").exists(),
            power: selected_role(&read(self.port.join("power_role"))),
            udc_state: read(Path::new("/sys/class/udc").join(&self.udc).join("state")),
        })
    }
    fn role(&mut self, mode: Mode, explicit: bool) -> Result<()> {
        if mode == Mode::Charging {
            return Ok(());
        }
        let target = if mode == Mode::Host { "host" } else { "device" };
        if !self.follow {
            let role = if mode == Mode::Host {
                crate::urs::URSRole::Host
            } else {
                crate::urs::URSRole::Device
            };
            if !crate::urs::discover_urss().is_empty() {
                crate::urs::URS::set_role(&role)?;
            }
            ensure!(
                mode != Mode::Host || self.controller() == "host",
                "No host role switch"
            );
            return Ok(());
        }
        ensure!(
            !self.observe()?.firmware.ends_with(":0"),
            "Charging/Type-C firmware is offline"
        );
        let partner = self.partner();
        if partner.is_empty() {
            ensure!(
                mode != Mode::Host,
                "No Type-C partner; host negotiation unavailable"
            );
            // Only an unconnected, unassigned controller may use the fallback.
            if self.controller() == "none" && self.partner().is_empty() {
                sysfs_write(
                    Path::new("/sys/class/usb_role")
                        .join(&self.switch)
                        .join("role"),
                    "device",
                )?;
            }
            ensure!(
                self.controller() == "device",
                "Firmware offline or peripheral fallback unavailable"
            );
            return Ok(());
        }
        if !explicit {
            // Startup and hotplug follow UCSI; they never request a role swap.
            return Ok(());
        }
        if selected_role(&read(self.port.join("data_role"))) != target {
            ensure!(
                self.partner() == partner,
                "Partner changed before role request"
            );
            sysfs_write(self.port.join("data_role"), target)
                .with_context(|| format!("Type-C rejected {target} data role"))?;
        }
        let until = Instant::now() + Duration::from_secs(2);
        loop {
            ensure!(
                self.partner() == partner,
                "Partner disconnected/changed during role request"
            );
            if selected_role(&read(self.port.join("data_role"))) == target
                && self.controller() == target
            {
                return Ok(());
            }
            ensure!(
                Instant::now() < until,
                "Timed out confirming Type-C and controller {target} roles"
            );
            thread::sleep(Duration::from_millis(50));
        }
    }
    fn teardown(&mut self) -> Result<()> {
        ensure!(
            !Path::new("/sys/block/nbd0/pid").exists(),
            "Connected NBD netboot keeps USB read-only"
        );
        // Touch needs to release contacts and UVC must close its V4L2 node
        // before unbind. MTP blocking endpoint reads must instead be cancelled
        // by unbind before waiting for its process; storage holds its inode
        // lock until the kernel has stopped serving it.
        let paths = self.owned()?;
        for mode in [Mode::HidTouch, Mode::Uvc, Mode::Developer, Mode::Tethering] {
            // These units are always defined by the module, including disabled backends.
            systemctl("stop", Self::service_for(mode))?;
        }
        if env("USB_SIGNALLER_ACM", "0") == "1" {
            systemctl("stop", "serial-getty@ttyGS0.service")?;
        }
        for path in &paths {
            if !read(path.join("UDC")).is_empty() {
                sysfs_write(path.join("UDC"), "\n")?;
            }
        }
        for mode in [Mode::Mtp, Mode::MassStorage] {
            systemctl("stop", Self::service_for(mode))?;
        }
        systemctl("stop", "usb-signaller-mtp-mount.service")?;
        for path in paths {
            let name = path.file_name().unwrap().to_str().unwrap();
            if let Some(kind) = GADGET_MODES
                .iter()
                .find(|m| m.gadget() == Some(name))
                .and_then(|m| m.extra())
            {
                extra_backend("cleanup", kind)?;
            } else {
                ConfigFsGadget::delete(name)?;
            }
        }
        Ok(())
    }
    fn install(&mut self, mode: Mode) -> Result<()> {
        if mode == Mode::Charging {
            return Ok(());
        }
        let state = self.observe()?;
        if !state.permits_gadget() {
            if !state.partner.is_empty() && state.controller == "host" && state.data == "host" {
                // A negotiated host partner at startup wins over the default.
                return Ok(());
            }
            bail!(
                "Type-C/controller role unavailable or inconsistent: {}/{}",
                state.data,
                state.controller
            );
        }
        ensure!(mode != Mode::Host, "Host role not confirmed");
        // Never steal a UDC from another gadget manager, including initrd.
        for path in entries(self.root()) {
            ensure!(
                read(path.join("UDC")) != self.udc,
                "UDC is busy: {}",
                path.display()
            );
        }
        if matches!(mode, Mode::Developer | Mode::Tethering) {
            ensure!(
                !Path::new("/sys/class/net/usb0").exists(),
                "usb0 is occupied by another device"
            );
        }
        if let Some(kind) = mode.extra() {
            extra_backend("prepare", kind)?;
            // Storage must open/lock its backing inode before USB sees the LUN.
            if mode == Mode::MassStorage {
                systemctl("start", Self::service_for(mode))?;
            }
            let now = self.observe()?;
            ensure!(
                now.permits_gadget()
                    && now.partner == state.partner
                    && now.firmware == state.firmware,
                "Connection/firmware changed during gadget preparation"
            );
            ConfigFsGadget::enable(mode.gadget().unwrap(), &self.udc)?;
            // HID and UVC character devices are created by function bind.
            if mode != Mode::MassStorage {
                systemctl("start", Self::service_for(mode))?;
            }
            let now = self.observe()?;
            ensure!(
                now.backend_ready
                    && now.actual == mode.name()
                    && now.permits_gadget()
                    && now.partner == state.partner
                    && now.firmware == state.firmware,
                "Gadget backend failed or connection changed during startup"
            );
            return Ok(());
        }
        let acm = mode == Mode::Developer && env("USB_SIGNALLER_ACM", "0") == "1";
        let (function, description, product, pid) = match mode {
            Mode::Developer => (
                "ncm.usb0",
                "Developer mode",
                if acm {
                    "NCM + ACM USB gadget (developer)"
                } else {
                    "NCM USB gadget (developer)"
                },
                if acm { 0x0104 } else { 0x0103 },
            ),
            Mode::Tethering => (
                "ncm.usb0",
                "Tethering mode",
                "NCM USB gadget (tethering)",
                0x0103,
            ),
            Mode::Mtp => ("ffs.mtp", "MTP mode", "FunctionFS USB gadget (MTP)", 0x0105),
            _ => unreachable!(),
        };
        let name = mode.gadget().unwrap();
        ConfigFsGadget::create(
            name,
            0x1d6b,
            pid,
            "Linux Foundation",
            product,
            &env("USB_SIGNALLER_SERIAL", "usb-signaller"),
            function,
            description,
            acm,
        )?;
        if mode == Mode::Mtp {
            systemctl("start", "usb-signaller-mtp-mount.service")?;
            systemctl("start", Self::service_for(mode))?;
            let until = Instant::now() + Duration::from_secs(2);
            while read(self.root().join(name).join("functions/ffs.mtp/ready")) != "1" {
                ensure!(Instant::now() < until, "FunctionFS endpoints not ready");
                thread::sleep(Duration::from_millis(25));
            }
        } else {
            systemctl("start", Self::service_for(mode))?;
            if mode == Mode::Tethering {
                let until = Instant::now() + Duration::from_secs(3);
                while !Path::new("/run/usb-signaller/tethering.prepared").exists() {
                    ensure!(Instant::now() < until, "Sharing policy failed to prepare");
                    thread::sleep(Duration::from_millis(25));
                }
            }
        }
        let now = self.observe()?;
        ensure!(
            now.permits_gadget() && now.partner == state.partner && now.firmware == state.firmware,
            "Connection/firmware changed during gadget creation"
        );
        ConfigFsGadget::enable(name, &self.udc)?;
        if mode != Mode::Mtp {
            ensure!(
                read(self.root().join(name).join("functions/ncm.usb0/ifname")) == "usb0",
                "NCM was assigned an unexpected interface"
            );
            let mac = env("USB_SIGNALLER_DEV_ADDR", "");
            ensure!(
                mac.is_empty() || read("/sys/class/net/usb0/address").eq_ignore_ascii_case(&mac),
                "NCM interface identity mismatch"
            );
        }
        if mode == Mode::Tethering {
            let until = Instant::now() + Duration::from_secs(3);
            while !Path::new("/run/usb-signaller/tethering.ready").exists() {
                ensure!(
                    Instant::now() < until,
                    "Sharing policy failed after NCM binding"
                );
                thread::sleep(Duration::from_millis(25));
            }
        }
        if acm {
            systemctl("start", "serial-getty@ttyGS0.service")?;
        }
        Ok(())
    }
}

struct Handle {
    sender: mpsc::SyncSender<Request>,
    status: Arc<Mutex<BTreeMap<String, String>>>,
}
enum Request {
    Mode(Mode),
    Reconcile,
    Stop,
}
static HANDLE: OnceLock<Handle> = OnceLock::new();
pub fn modes() -> String {
    env(
        "USB_SIGNALLER_MODES",
        "developer_mode,charging_only,host_mode",
    )
}
pub fn request(mode: &str) -> Result<String> {
    let mode = Mode::parse(mode)?;
    ensure!(
        modes().split(',').any(|m| m == mode.name()),
        "Backend is not enabled: {}",
        mode.name()
    );
    let handle = HANDLE.get().context("Manager not started")?;
    // A bounded queue keeps a flood of callers from postponing hotplug forever.
    // Acceptance is immediate; get_status exposes completion and any error.
    handle
        .sender
        .try_send(Request::Mode(mode))
        .context("USB manager busy; retry after querying get_status")?;
    Ok(mode.name().into())
}
pub fn reconcile() {
    if let Some(h) = HANDLE.get() {
        let _ = h.sender.try_send(Request::Reconcile);
    }
}
pub fn status() -> BTreeMap<String, String> {
    HANDLE.get().unwrap().status.lock().unwrap().clone()
}
fn spawn_worker<B: Backend + Send + 'static>(
    backend: B,
    default: Mode,
) -> (
    mpsc::SyncSender<Request>,
    Arc<Mutex<BTreeMap<String, String>>>,
    thread::JoinHandle<()>,
) {
    let (sender, receiver) = mpsc::sync_channel(1);
    let status = Arc::new(Mutex::new(BTreeMap::from([
        ("desired_mode".into(), default.name().into()),
        ("actual_mode".into(), "unknown_mode".into()),
        ("busy".into(), "true".into()),
    ])));
    let shared = status.clone();
    let worker = thread::spawn(move || {
        let status = shared;
        let mut engine = Engine {
            backend,
            desired: default,
            error: String::new(),
        };
        let mut last = Observation::default();
        let mut first = true;
        loop {
            let request = if first {
                None
            } else {
                receiver.recv_timeout(Duration::from_millis(500)).ok()
            };
            if matches!(request, Some(Request::Stop)) {
                let _ = engine.backend.teardown();
                break;
            }
            let observed = match engine.backend.observe() {
                Ok(s) => s,
                Err(e) => {
                    engine.error = format!("{e:#}");
                    Observation::default()
                }
            };
            // Enumeration alone is telemetry; it must not rebuild a gadget.
            let changed = first
                || observed.controller != last.controller
                || observed.data != last.data
                || observed.partner != last.partner
                || observed.firmware != last.firmware
                || observed.policy != last.policy
                || observed.backend_ready != last.backend_ready;
            let explicit = matches!(request, Some(Request::Mode(_)));
            let backend_stopped = !first
                && !explicit
                && last.backend_ready
                && !observed.backend_ready
                && observed.controller == last.controller
                && observed.data == last.data
                && observed.partner == last.partner
                && observed.firmware == last.firmware;
            if explicit || changed {
                let mode = if let Some(Request::Mode(m)) = request {
                    m
                } else if engine.desired == Mode::Host
                    && (observed.partner.is_empty()
                        || (!last.partner.is_empty() && observed.partner != last.partner))
                {
                    default
                } else {
                    engine.desired
                };
                {
                    let mut values = status.lock().unwrap();
                    values.insert("busy".into(), "true".into());
                    values.insert("desired_mode".into(), mode.name().into());
                }
                let result = if backend_stopped {
                    // An exited source is not fresh connection evidence. Leave
                    // the gadget unbound and wait for an explicit retry/hotplug.
                    (|| {
                        engine
                            .backend
                            .teardown()
                            .context("USB backend stopped; cleanup failed")?;
                        bail!("USB backend stopped unexpectedly; select a mode to retry")
                    })()
                } else {
                    engine.transition(mode, explicit)
                };
                if let Err(e) = result {
                    engine.error = format!("{e:#}");
                    eprintln!("USB transition: {}", engine.error);
                }
            }
            first = false;
            let snapshot = engine.backend.observe().unwrap_or(observed.clone());
            // Preserve a hotplug/SSR arriving during a transaction for the next
            // pass instead of treating the failed transaction as reconciliation.
            last = if snapshot.partner != observed.partner || snapshot.firmware != observed.firmware
            {
                observed
            } else {
                snapshot.clone()
            };
            let mut values = BTreeMap::new();
            for (key, value) in [
                ("desired_mode", engine.desired.name().into()),
                ("actual_mode", snapshot.actual.clone()),
                ("controller_role", snapshot.controller.clone()),
                ("data_role", snapshot.data.clone()),
                ("power_role", snapshot.power.clone()),
                ("connected", (!snapshot.partner.is_empty()).to_string()),
                ("bound", snapshot.bound.to_string()),
                (
                    "enumerated",
                    (snapshot.udc_state == "configured").to_string(),
                ),
                ("udc_state", snapshot.udc_state.clone()),
                ("firmware_generation", snapshot.firmware.clone()),
                ("last_error", engine.error.clone()),
                ("busy", "false".into()),
                ("vbus_verified", "false".into()),
                (
                    "tethering_upstream",
                    read("/run/usb-signaller/tethering.ready"),
                ),
            ] {
                values.insert(key.into(), value);
            }
            *status.lock().unwrap() = values;
        }
    });
    (sender, status, worker)
}
pub fn start(default: Mode) -> thread::JoinHandle<()> {
    let (sender, status, worker) = spawn_worker(LinuxBackend::new(), default);
    assert!(HANDLE.set(Handle { sender, status }).is_ok());
    worker
}
pub fn stop() {
    if let Some(h) = HANDLE.get() {
        let _ = h.sender.send(Request::Stop);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Default)]
    struct Fake {
        state: Observation,
        log: Vec<String>,
        fail: Option<Mode>,
        detach: bool,
        reject: bool,
    }
    impl Backend for Fake {
        fn observe(&self) -> Result<Observation> {
            Ok(self.state.clone())
        }
        fn teardown(&mut self) -> Result<()> {
            self.log.push("stop/unbind/delete".into());
            self.state.actual = "charging_only".into();
            Ok(())
        }
        fn role(&mut self, mode: Mode, _: bool) -> Result<()> {
            if self.reject && mode == Mode::Host {
                bail!("role rejected");
            }
            Ok(())
        }
        fn install(&mut self, mode: Mode) -> Result<()> {
            self.log.push(mode.name().into());
            if self.fail == Some(mode) {
                if self.detach {
                    self.state.partner.clear();
                    self.state.controller = "none".into();
                }
                bail!("injected create/FunctionFS/bind failure");
            }
            self.state.actual = mode.name().into();
            Ok(())
        }
    }
    fn engine() -> Engine<Fake> {
        Engine {
            backend: Fake {
                state: Observation {
                    controller: "device".into(),
                    data: "device".into(),
                    partner: "session1".into(),
                    actual: "developer_mode".into(),
                    ..Default::default()
                },
                ..Default::default()
            },
            desired: Mode::Developer,
            error: String::new(),
        }
    }
    #[test]
    fn connected_netboot_rejects_every_transition_before_mutation() {
        for mode in [
            Mode::Developer,
            Mode::Host,
            Mode::Charging,
            Mode::Mtp,
            Mode::Tethering,
            Mode::HidTouch,
            Mode::MassStorage,
            Mode::Uvc,
        ] {
            let mut e = engine();
            e.backend.state.read_only = true;
            assert!(e.transition(mode, true).is_err());
            assert!(e.backend.log.is_empty());
            assert_eq!(e.desired, Mode::Developer);
            assert_eq!(e.backend.state.actual, "developer_mode");
        }
    }
    #[test]
    fn same_name_is_deleted_before_recreation() {
        let mut e = engine();
        e.transition(Mode::Developer, true).unwrap();
        assert_eq!(e.backend.log, ["stop/unbind/delete", "developer_mode"]);
    }
    #[test]
    fn failed_partial_setup_restores_previous_mode() {
        let mut e = engine();
        e.backend.fail = Some(Mode::Mtp);
        assert!(e.transition(Mode::Mtp, true).is_err());
        assert_eq!(e.desired, Mode::Mtp);
        assert_eq!(e.backend.state.actual, "developer_mode");
        assert_eq!(
            e.backend.log,
            [
                "stop/unbind/delete",
                "mtp_ffs_mode",
                "stop/unbind/delete",
                "developer_mode"
            ]
        );
    }
    #[test]
    fn detach_during_failure_does_not_bind_rollback() {
        let mut e = engine();
        e.backend.fail = Some(Mode::Mtp);
        e.backend.detach = true;
        assert!(e.transition(Mode::Mtp, true).is_err());
        assert_eq!(e.backend.log.len(), 3);
        assert_eq!(e.backend.state.actual, "charging_only");
    }
    #[test]
    fn rejected_role_swap_is_reported_and_restores_data() {
        let mut e = engine();
        e.backend.reject = true;
        assert!(e.transition(Mode::Host, true).is_err());
        assert!(e.error.contains("rejected"));
        assert_eq!(e.backend.state.actual, "developer_mode");
    }
    #[test]
    fn role_parser_keeps_power_and_data_separate() {
        assert_eq!(selected_role("host [device]"), "device");
        assert_eq!(selected_role("source [sink]"), "sink");
    }
    #[derive(Clone)]
    struct Shared(Arc<Mutex<Fake>>);
    impl Backend for Shared {
        fn observe(&self) -> Result<Observation> {
            self.0.lock().unwrap().observe()
        }
        fn teardown(&mut self) -> Result<()> {
            self.0.lock().unwrap().teardown()
        }
        fn role(&mut self, mode: Mode, explicit: bool) -> Result<()> {
            self.0.lock().unwrap().role(mode, explicit)
        }
        fn install(&mut self, mode: Mode) -> Result<()> {
            thread::sleep(Duration::from_millis(10));
            self.0.lock().unwrap().install(mode)
        }
    }
    fn until(
        status: &Arc<Mutex<BTreeMap<String, String>>>,
        predicate: impl Fn(&BTreeMap<String, String>) -> bool,
    ) {
        let deadline = Instant::now() + Duration::from_secs(3);
        while !predicate(&status.lock().unwrap()) {
            assert!(
                Instant::now() < deadline,
                "worker did not settle: {:?}",
                status.lock().unwrap()
            );
            thread::sleep(Duration::from_millis(5));
        }
    }
    #[test]
    fn concurrent_requests_are_bounded_and_serialized() {
        let backend = Shared(Arc::new(Mutex::new(engine().backend)));
        let (sender, status, worker) = spawn_worker(backend.clone(), Mode::Developer);
        until(&status, |s| s.get("busy").is_some_and(|v| v == "false"));
        let held = backend.0.lock().unwrap();
        let gate = Arc::new(std::sync::Barrier::new(21));
        let mut callers = vec![];
        for _ in 0..20 {
            let sender = sender.clone();
            let gate = gate.clone();
            callers.push(thread::spawn(move || {
                gate.wait();
                sender.try_send(Request::Mode(Mode::Developer)).is_ok()
            }));
        }
        gate.wait();
        let accepted = callers
            .into_iter()
            .map(|t| t.join().unwrap())
            .filter(|accepted| *accepted)
            .count();
        assert!((1..=2).contains(&accepted));
        drop(held);
        sender.send(Request::Stop).unwrap();
        worker.join().unwrap();
        let fake = backend.0.lock().unwrap();
        // Each completed installation has exactly one immediately preceding cleanup.
        assert!(fake
            .log
            .chunks_exact(2)
            .all(|pair| pair == ["stop/unbind/delete", "developer_mode"]));
    }
    #[test]
    fn a_failed_transition_does_not_retry_without_new_evidence() {
        let backend = Shared(Arc::new(Mutex::new(engine().backend)));
        let (sender, status, worker) = spawn_worker(backend.clone(), Mode::Developer);
        until(&status, |s| s.get("busy").is_some_and(|v| v == "false"));
        backend.0.lock().unwrap().fail = Some(Mode::Mtp);
        sender.send(Request::Mode(Mode::Mtp)).unwrap();
        until(&status, |s| {
            s.get("last_error").is_some_and(|v| !v.is_empty())
        });
        let count = backend.0.lock().unwrap().log.len();
        thread::sleep(Duration::from_millis(1100));
        assert_eq!(backend.0.lock().unwrap().log.len(), count);
        sender.send(Request::Stop).unwrap();
        worker.join().unwrap();
    }
    #[test]
    fn backend_crash_cleans_up_without_restarting_the_failed_source() {
        let mut fake = engine().backend;
        fake.state.backend_ready = true;
        let backend = Shared(Arc::new(Mutex::new(fake)));
        let (sender, status, worker) = spawn_worker(backend.clone(), Mode::HidTouch);
        until(&status, |s| s.get("busy").is_some_and(|v| v == "false"));
        {
            let mut fake = backend.0.lock().unwrap();
            fake.state.backend_ready = false;
            fake.state.actual = "unknown_mode".into();
        }
        until(&status, |s| {
            s.get("last_error")
                .is_some_and(|v| v.contains("backend stopped"))
        });
        assert_eq!(status.lock().unwrap()["actual_mode"], "charging_only");
        let count = backend.0.lock().unwrap().log.len();
        thread::sleep(Duration::from_millis(1100));
        assert_eq!(backend.0.lock().unwrap().log.len(), count);
        sender.send(Request::Stop).unwrap();
        worker.join().unwrap();
    }
    #[test]
    fn firmware_restart_reconciles_once_and_clears_error() {
        let backend = Shared(Arc::new(Mutex::new(engine().backend)));
        let (sender, status, worker) = spawn_worker(backend.clone(), Mode::Developer);
        until(&status, |s| s.get("busy").is_some_and(|v| v == "false"));
        backend.0.lock().unwrap().state.firmware = "new-generation:1".into();
        sender.send(Request::Reconcile).unwrap();
        until(&status, |s| {
            s.get("firmware_generation")
                .is_some_and(|v| v == "new-generation:1")
        });
        assert!(status.lock().unwrap()["last_error"].is_empty());
        sender.send(Request::Stop).unwrap();
        worker.join().unwrap();
    }
}
