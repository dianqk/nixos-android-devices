// Exercise the packaged D-Bus mode implementation without hardware/configfs.
mod dbus;
use std::sync::Mutex;
static ROLE: Mutex<String> = Mutex::new(String::new());
static WRITES: Mutex<usize> = Mutex::new(0);
static GADGETS: Mutex<usize> = Mutex::new(0);
static EVENTS: Mutex<Vec<&str>> = Mutex::new(Vec::new());
static STOP_FAILS: Mutex<bool> = Mutex::new(false);
mod service {
    pub fn service_stop(_: &str) -> anyhow::Result<()> {
        crate::EVENTS.lock().unwrap().push("stop");
        anyhow::ensure!(!*crate::STOP_FAILS.lock().unwrap(), "console stop failed");
        Ok(())
    }
    pub fn service_start_async(_: &str) -> anyhow::Result<()> {
        crate::EVENTS.lock().unwrap().push("start-async");
        Ok(())
    }
}
mod udc {
    #[derive(Debug, Clone, PartialEq)]
    pub enum UDCMode {
        Developer,
        Charging,
        Unknown,
    }
    pub struct Gadget {
        pub name: String,
    }
    pub struct UDC {
        pub name: String,
        pub mode: UDCMode,
        pub enabled: bool,
        pub gadget: Option<Gadget>,
    }
    pub fn discover_udcs() -> Vec<String> {
        vec!["test".into()]
    }
    impl UDC {
        pub fn load(name: &str) -> anyhow::Result<Self> {
            Ok(Self {
                name: name.into(),
                mode: UDCMode::Unknown,
                enabled: false,
                gadget: None,
            })
        }
        pub fn set_mode(mut self, mode: UDCMode) -> anyhow::Result<Self> {
            crate::EVENTS.lock().unwrap().push("gadget");
            *crate::GADGETS.lock().unwrap() += 1;
            self.mode = mode;
            Ok(self)
        }
    }
}
mod urs {
    #[derive(Debug, PartialEq)]
    pub enum URSRole {
        Host,
        Device,
        Unknown,
    }
    pub struct URS {
        pub name: String,
        pub role: URSRole,
        pub udc: Option<crate::udc::UDC>,
    }
    pub fn discover_urss() -> Vec<String> {
        vec!["test".into()]
    }
    impl URS {
        pub fn load(name: &str) -> anyhow::Result<Self> {
            let role = match crate::ROLE.lock().unwrap().as_str() {
                "host" => URSRole::Host,
                "device" => URSRole::Device,
                _ => URSRole::Unknown,
            };
            Ok(Self {
                name: name.into(),
                role,
                udc: None,
            })
        }
        pub fn set_role(role: &URSRole) -> anyhow::Result<Self> {
            crate::EVENTS.lock().unwrap().push("role");
            *crate::WRITES.lock().unwrap() += 1;
            *crate::ROLE.lock().unwrap() = if *role == URSRole::Host {
                "host"
            } else {
                "device"
            }
            .into();
            Self::load("test")
        }
    }
}
mod utils {
    pub fn string_to_udcmode(mode: &str) -> crate::udc::UDCMode {
        match mode {
            "developer_mode" => crate::udc::UDCMode::Developer,
            "charging_only" => crate::udc::UDCMode::Charging,
            _ => crate::udc::UDCMode::Unknown,
        }
    }
    pub fn udcmode_to_string(mode: crate::udc::UDCMode) -> &'static str {
        match mode {
            crate::udc::UDCMode::Developer => "developer_mode",
            crate::udc::UDCMode::Charging => "charging_only",
            _ => "unknown",
        }
    }
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let connection = zbus::Connection::session().await?;
    let emitter = zbus::object_server::SignalEmitter::new(&connection, "/com/meego/usb_moded")?;
    // Each process sets its environment before starting Tokio; no runtime mutation.
    let managed = std::env::var("USB_SIGNALLER_MANAGE_ROLE").map_or(true, |v| v != "0");
    let console = std::env::var("USB_SIGNALLER_ACM_SERVICE").is_ok();
    for role in ["host", "device", "none"] {
        for mode in ["developer_mode", "charging_only"] {
            EVENTS.lock().unwrap().clear();
            *ROLE.lock().unwrap() = role.into();
            *WRITES.lock().unwrap() = 0;
            *GADGETS.lock().unwrap() = 0;
            assert_eq!(
                dbus::UsbModedDBus.set_mode(mode, emitter.clone()).await?,
                mode
            );
            assert_eq!(*ROLE.lock().unwrap(), if managed { "device" } else { role });
            assert_eq!(*WRITES.lock().unwrap(), usize::from(managed));
            assert_eq!(*GADGETS.lock().unwrap(), 1);
            let mut expected = vec![];
            if console {
                expected.push("stop");
            }
            if managed {
                expected.push("role");
            }
            expected.push("gadget");
            if console && mode == "developer_mode" {
                expected.push("start-async");
            }
            assert_eq!(*EVENTS.lock().unwrap(), expected);
        }
    }
    EVENTS.lock().unwrap().clear();
    if !managed {
        assert!(
            dbus::UsbModedDBus
                .set_mode("host_mode", emitter.clone())
                .await
                .is_err()
        );
        assert_eq!(*WRITES.lock().unwrap(), 0);
        assert!(EVENTS.lock().unwrap().is_empty());
    } else {
        assert_eq!(
            dbus::UsbModedDBus
                .set_mode("host_mode", emitter.clone())
                .await?,
            "host_mode"
        );
        assert_eq!(
            *EVENTS.lock().unwrap(),
            if console {
                vec!["stop", "role"]
            } else {
                vec!["role"]
            }
        );
    }
    if console {
        EVENTS.lock().unwrap().clear();
        *STOP_FAILS.lock().unwrap() = true;
        assert!(
            dbus::UsbModedDBus
                .set_mode("developer_mode", emitter)
                .await
                .is_err()
        );
        assert_eq!(*EVENTS.lock().unwrap(), vec!["stop"]);
    }
    println!("role preservation and gadget setup passed (manage_role={managed})");
    Ok(())
}
