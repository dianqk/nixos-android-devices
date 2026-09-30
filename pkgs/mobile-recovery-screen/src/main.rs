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
mod status;

#[cfg(test)]
mod tests;

fn main() {
    if let Err(err) = app::run() {
        eprintln!("mobile-recovery-screen: {err}");
        std::process::exit(1);
    }
}
