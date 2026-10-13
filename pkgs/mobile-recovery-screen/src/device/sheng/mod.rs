use super::{Profile, RECOVERY_ITEMS};

pub(super) const PROFILE: Profile = Profile {
    id: "sheng",
    title: "Sheng / Xiaomi Pad 6S Pro",
    warning: "B-slot recovery; verify USB and display on device",
    boot_system_label: "Boot system",
    items: RECOVERY_ITEMS,
    #[cfg(feature = "backlight-control")]
    backlight: None,
};
