fn main() {
    if let Err(error) = mobile_recovery_screen::host_key::prepare() {
        // SSH still starts and generates its ordinary RAM key. Never print key data.
        eprintln!("Recovery SSH identity: temporary (persistent storage unavailable: {error:#})");
    }
}
