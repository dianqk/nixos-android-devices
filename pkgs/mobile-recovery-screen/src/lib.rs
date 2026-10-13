//! Shared recovery task service, protocol and checked storage primitives.
#[cfg(feature = "recovery-daemon")]
pub mod daemon;

#[cfg(feature = "host-key")]
pub mod host_key;
