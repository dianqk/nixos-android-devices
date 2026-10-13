fn main() {
    if let Err(e) = mobile_recovery_screen::daemon::storage::Config::load()
        .and_then(mobile_recovery_screen::daemon::engine::serve)
    {
        eprintln!("mobile-recovery-daemon: {e:#}");
        std::process::exit(1);
    }
}
