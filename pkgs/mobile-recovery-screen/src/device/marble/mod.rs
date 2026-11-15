use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "marble",
    title: "Marble / Redmi Note 12 Turbo",
    warning: "Experimental recovery; partitioning erases Android userdata",
    boot_system_label: "Boot system",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
