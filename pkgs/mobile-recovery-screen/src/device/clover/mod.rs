use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "clover",
    title: "Clover LTE",
    warning: "Unmount storage before leaving recovery",
    log_font_px: 28,
    boot_system_label: "Boot userdata",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
