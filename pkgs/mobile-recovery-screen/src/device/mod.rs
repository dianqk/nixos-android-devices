//! Device-specific recovery content and display setup selected at build time.

#[cfg(not(any(
    feature = "device-polaris",
    feature = "device-asphalt",
    feature = "device-clover",
    feature = "device-sheng"
)))]
compile_error!("select one supported device feature");
#[cfg(any(
    all(
        feature = "device-polaris",
        any(
            feature = "device-asphalt",
            feature = "device-clover",
            feature = "device-sheng"
        )
    ),
    all(
        feature = "device-asphalt",
        any(feature = "device-clover", feature = "device-sheng")
    ),
    all(feature = "device-clover", feature = "device-sheng"),
))]
compile_error!("select only one device feature");
#[cfg(all(feature = "device-polaris", not(feature = "refresh-panel")))]
compile_error!("Polaris requires the refresh-panel capability");
#[cfg(all(feature = "device-clover", not(feature = "refresh-panel")))]
compile_error!("Clover requires the refresh-panel capability");
#[cfg(all(feature = "device-asphalt", not(feature = "backlight-control")))]
compile_error!("Y700 requires the backlight-control capability");
#[cfg(all(feature = "device-asphalt", not(feature = "ab-partitions")))]
compile_error!("Y700 requires the ab-partitions capability");
#[cfg(all(feature = "device-polaris", feature = "ab-partitions"))]
compile_error!("Polaris does not use A/B partitions");
#[cfg(all(feature = "device-clover", feature = "ab-partitions"))]
compile_error!("Clover does not use A/B partitions");
#[cfg(all(feature = "device-sheng", not(feature = "ab-partitions")))]
compile_error!("Sheng requires the ab-partitions capability");

#[cfg(feature = "device-asphalt")]
mod asphalt;
#[cfg(feature = "device-clover")]
mod clover;
#[cfg(feature = "device-polaris")]
mod polaris;
#[cfg(feature = "device-sheng")]
mod sheng;

#[cfg(feature = "device-asphalt")]
use asphalt as selected;
#[cfg(feature = "device-clover")]
use clover as selected;
#[cfg(feature = "device-polaris")]
use polaris as selected;
#[cfg(feature = "device-sheng")]
use sheng as selected;

#[cfg(feature = "backlight-control")]
pub(crate) struct BacklightSetting {
    pub path: &'static str,
    pub level: u32,
}

pub(crate) struct Item {
    pub label: &'static str,
    pub action: Option<&'static str>,
}

pub(crate) const RECOVERY_ITEMS: &[Item] = &[
    Item {
        label: "Show recovery log",
        action: None,
    },
    Item {
        label: "Boot NixOS",
        action: Some("reboot-system"),
    },
    Item {
        label: "Restart recovery",
        action: Some("reboot-recovery"),
    },
    Item {
        label: "Enter fastboot",
        action: Some("reboot-bootloader"),
    },
    Item {
        label: "Power off",
        action: Some("poweroff"),
    },
];

pub(crate) struct Profile {
    pub id: &'static str,
    pub title: &'static str,
    pub warning: &'static str,
    pub log_font_px: u32,
    pub boot_system_label: &'static str,
    pub items: &'static [Item],
    #[cfg(feature = "backlight-control")]
    pub backlight: Option<BacklightSetting>,
}

impl Profile {
    pub fn item_label(&self, item: &Item) -> &'static str {
        if item.action == Some("reboot-system") {
            self.boot_system_label
        } else {
            item.label
        }
    }
}

pub(crate) fn profile() -> &'static Profile {
    &selected::PROFILE
}
