fn main() {
    if let Err(e) =
        mobile_recovery_screen::daemon::client::command(std::env::args().skip(1).collect())
    {
        eprintln!("recovery: {e:#}");
        std::process::exit(1);
    }
}
