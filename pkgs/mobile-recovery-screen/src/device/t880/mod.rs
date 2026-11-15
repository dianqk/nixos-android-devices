use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "t880",
    title: "Alldocube iPlay 80 mini Ultra",
    warning: "Experimental recovery; partitioning destroys Android userdata",
    boot_system_label: "Boot system",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
