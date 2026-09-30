use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "polaris",
    title: "Polaris",
    warning: "Charging disabled; use short recovery sessions",
    log_font_px: 28,
    boot_system_label: "Boot NixOS",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
