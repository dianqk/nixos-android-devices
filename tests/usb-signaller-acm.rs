// Manual dummy_hcd integration fixture. Never accepts a physical UDC.
mod configuration;
mod dbus;
mod gadget;
mod service;
mod sysfs;
mod udc;
mod urs;
mod utils;

use gadget::ConfigFsGadget;
use std::io::{self, Write};
use std::path::Path;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    anyhow::ensure!(args.len() == 3 && args[1].starts_with("dummy_udc."));
    anyhow::ensure!(args[2] == "0" || args[2] == "1");
    let acm = args[2] == "1";
    let name = "usb-signaller-acm-test";
    let base = Path::new("/sys/kernel/config/usb_gadget").join(name);
    anyhow::ensure!(!base.exists());
    let result = (|| -> anyhow::Result<()> {
        let gadget = ConfigFsGadget::create(name, 0x1d6b, if acm { 0x0104 } else { 0x0103 },
            "Local test", "NCM ACM integration test", "signaller-acm-test", "ncm.usb0", "Developer mode", acm)?;
        anyhow::ensure!(gadget.configs[0].functions.len() == if acm { 2 } else { 1 });
        if acm {
            // Exercise mode discovery with ACM before NCM in configfs.
            let link = base.join("configs/c.1/ncm.usb0");
            std::fs::remove_file(&link)?;
            let function = base.join("functions/ncm.usb0");
            std::fs::remove_dir(&function)?;
            std::fs::create_dir(&function)?;
            std::os::unix::fs::symlink(&function, link)?;
            anyhow::ensure!(ConfigFsGadget::load(name)?.configs[0].functions[0].name == "acm.console");
        }
        ConfigFsGadget::enable(name, &args[1])?;
        let observed = udc::UDC::load(&args[1])?;
        anyhow::ensure!(observed.mode == udc::UDCMode::Developer || observed.mode == udc::UDCMode::Tethering);
        println!("READY {:?}", observed.gadget.unwrap().configs[0].functions);
        io::stdout().flush()?;
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        anyhow::ensure!(line.trim() == "stop");
        Ok(())
    })();
    if base.exists() {
        let _ = ConfigFsGadget::disable(name);
        ConfigFsGadget::delete(name)?;
    }
    result
}
