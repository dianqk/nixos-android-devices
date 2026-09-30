//! Read-only A/B slot indicator for devices with slot-suffixed boot partitions.
use std::fs;

fn slot_from_cmdline(cmdline: &str) -> Option<&'static str> {
    cmdline.split_whitespace().find_map(|word| {
        let suffix = word
            .strip_prefix("androidboot.slot_suffix=")
            .or_else(|| word.strip_prefix("boot.slot_suffix="))?;
        match suffix {
            "_a" => Some("A"),
            "_b" => Some("B"),
            _ => None,
        }
    })
}

fn slot_from_bootconfig(bootconfig: &str) -> Option<&'static str> {
    bootconfig.lines().find_map(|line| {
        let (key, suffix) = line.split_once('=')?;
        if !matches!(key.trim(), "androidboot.slot_suffix" | "boot.slot_suffix") {
            return None;
        }
        match suffix.trim().trim_matches('"') {
            "_a" => Some("A"),
            "_b" => Some("B"),
            _ => None,
        }
    })
}

pub(crate) fn running_slot() -> Option<&'static str> {
    fs::read_to_string("/proc/cmdline")
        .ok()
        .and_then(|cmdline| slot_from_cmdline(&cmdline))
        .or_else(|| {
            fs::read_to_string("/proc/bootconfig")
                .ok()
                .and_then(|bootconfig| slot_from_bootconfig(&bootconfig))
        })
}

#[cfg(test)]
mod tests {
    use super::{slot_from_bootconfig, slot_from_cmdline};

    #[test]
    fn accepts_only_known_slot_suffixes() {
        assert_eq!(
            slot_from_cmdline("quiet androidboot.slot_suffix=_b"),
            Some("B")
        );
        assert_eq!(slot_from_cmdline("boot.slot_suffix=_a rootwait"), Some("A"));
        assert_eq!(slot_from_cmdline("androidboot.slot_suffix=unknown"), None);
        assert_eq!(slot_from_cmdline("androidboot.slot_suffix=_b-extra"), None);
        assert_eq!(
            slot_from_bootconfig("androidboot.slot_suffix = \"_b\""),
            Some("B")
        );
        assert_eq!(slot_from_bootconfig("boot.slot_suffix = _a"), Some("A"));
        assert_eq!(slot_from_bootconfig("boot.slot_suffix = _unknown"), None);
    }
}
