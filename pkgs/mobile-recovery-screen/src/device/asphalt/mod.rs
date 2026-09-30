use super::{BacklightSetting, Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "asphalt",
    title: "Y700",
    warning: "Unmount storage before leaving recovery",
    log_font_px: 32,
    boot_system_label: "Boot system",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: Some(BacklightSetting {
        path: "/sys/class/backlight/ktz8866-backlight/brightness",
        level: 400,
    }),
};
