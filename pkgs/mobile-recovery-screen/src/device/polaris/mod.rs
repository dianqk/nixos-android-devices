use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "polaris",
    title: "Polaris",
    warning: "Charging disabled; use short recovery sessions",
    boot_system_label: "Boot NixOS",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
