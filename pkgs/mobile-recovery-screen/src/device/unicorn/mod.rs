use super::{Profile, RECOVERY_ITEMS};
pub(super) const PROFILE: Profile = Profile {
    id: "unicorn",
    title: "Xiaomi 12S Pro / Unicorn",
    warning: "Linux-only installation destroys all Android userdata",
    boot_system_label: "Boot NixOS",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
