//! Device-specific recovery content and display setup selected at build time.

#[cfg(not(any(
    feature = "device-polaris",
    feature = "device-asphalt",
    feature = "device-clover",
    feature = "device-sheng",
    feature = "device-aurora",
    feature = "device-marble",
    feature = "device-t880",
    feature = "device-dodge",
    feature = "device-unicorn"
)))]
compile_error!("select one supported device feature");
#[cfg(all(
    feature = "device-unicorn",
    any(
        feature = "device-polaris",
        feature = "device-asphalt",
        feature = "device-clover",
        feature = "device-sheng",
        feature = "device-aurora",
        feature = "device-marble",
        feature = "device-t880",
        feature = "device-dodge"
    )
))]
compile_error!("select only one device feature");
#[cfg(all(feature = "device-unicorn", not(feature = "ab-partitions")))]
compile_error!("Unicorn requires the ab-partitions capability");
#[cfg(feature = "device-unicorn")]
mod unicorn;
#[cfg(feature = "device-unicorn")]
use unicorn as selected;
#[cfg(all(
    feature = "device-dodge",
    any(
        feature = "device-polaris",
        feature = "device-asphalt",
        feature = "device-clover",
        feature = "device-sheng",
        feature = "device-aurora",
        feature = "device-marble",
        feature = "device-t880"
    )
))]
compile_error!("select only one device feature");
#[cfg(all(feature = "device-dodge", not(feature = "ab-partitions")))]
compile_error!("Dodge requires the ab-partitions capability");
#[cfg(feature = "device-dodge")]
mod dodge;
#[cfg(feature = "device-dodge")]
use dodge as selected;
#[cfg(all(
    feature = "device-t880",
    any(
        feature = "device-polaris",
        feature = "device-asphalt",
        feature = "device-clover",
        feature = "device-sheng",
        feature = "device-aurora"
    )
))]
compile_error!("select only one device feature");
#[cfg(all(feature = "device-t880", feature = "ab-partitions"))]
compile_error!("T880 reads its slot from misc, not from a boot argument");
#[cfg(feature = "device-t880")]
mod t880;
#[cfg(feature = "device-t880")]
use t880 as selected;
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
#[cfg(all(
    feature = "device-aurora",
    any(
        feature = "device-polaris",
        feature = "device-clover",
        feature = "device-asphalt",
        feature = "device-sheng"
    )
))]
compile_error!("select only one device feature");
#[cfg(all(
    feature = "device-marble",
    any(
        feature = "device-polaris",
        feature = "device-clover",
        feature = "device-asphalt",
        feature = "device-sheng",
        feature = "device-aurora",
        feature = "device-t880"
    )
))]
compile_error!("select only one device feature");
#[cfg(all(feature = "device-marble", not(feature = "ab-partitions")))]
compile_error!("Marble requires the ab-partitions capability");
#[cfg(feature = "device-marble")]
mod marble;
#[cfg(feature = "device-marble")]
use marble as selected;
#[cfg(all(feature = "device-aurora", not(feature = "ab-partitions")))]
compile_error!("Aurora requires the ab-partitions capability");
#[cfg(feature = "device-aurora")]
mod aurora;
#[cfg(feature = "device-aurora")]
use aurora as selected;

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

/// Item whose action first asks how much Android userdata to keep.
pub(crate) const PREPARE_INSTALL: &str = "prepare-install";

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
    // A/B storage: split userdata into the chosen Android size and Linux.
    #[cfg(all(
        any(feature = "ab-partitions", feature = "device-t880"),
        feature = "recovery-daemon"
    ))]
    Item {
        label: "Prepare Linux storage",
        action: Some(PREPARE_INSTALL),
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
