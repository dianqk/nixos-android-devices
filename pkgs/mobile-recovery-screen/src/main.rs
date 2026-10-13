//! RAM recovery display. Only the existing guarded recovery CLI performs actions.
mod app;
mod canvas;
#[cfg(feature = "ab-partitions")]
mod capabilities;
mod device;
mod display;
mod input;
mod menu;
mod render;
#[cfg(not(feature = "recovery-daemon"))]
compile_error!("the recovery screen is a client of the recovery daemon");
#[path = "status_daemon.rs"]
mod status;

#[cfg(test)]
mod tests;

fn main() {
    if let Err(err) = app::run() {
        eprintln!("mobile-recovery-screen: {err}");
        std::process::exit(1);
    }
}
