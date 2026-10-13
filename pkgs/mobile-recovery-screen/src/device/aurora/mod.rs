use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "aurora",
    title: "Aurora / Xiaomi 14 Ultra",
    warning: "Experimental recovery; partitioning destroys userdata",
    boot_system_label: "Boot system",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
