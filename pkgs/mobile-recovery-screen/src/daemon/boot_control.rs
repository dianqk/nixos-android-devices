// AOSP bootloader control metadata shared by recovery and installed tools.
use anyhow::{ensure, Result};
pub(crate) fn crc(b: &[u8]) -> u32 {
    let mut v = !0u32;
    for byte in b {
        v ^= u32::from(*byte);
        for _ in 0..8 {
            v = (v >> 1) ^ (0xedb88320u32 & (0u32.wrapping_sub(v & 1)));
        }
    }
    !v
}
/// One slot of the AOSP `bootloader_control` block (misc offset 2048) that
/// MediaTek LK_AB reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SlotInfo {
    pub priority: u8,
    pub tries: u8,
    pub successful: bool,
}
pub const BOOT_CONTROL_OFFSET: u64 = 2048;
/// Parse and verify an AOSP `bootloader_control` (magic, version, two slots, CRC).
pub fn boot_control(b: &[u8]) -> Result<[SlotInfo; 2]> {
    ensure!(b.len() >= 32, "short boot control");
    ensure!(
        u32::from_le_bytes(b[4..8].try_into()?) == 0x4241_4342 && b[8] == 1,
        "missing AOSP boot control in misc"
    );
    ensure!(b[9] & 7 == 2, "boot control does not describe two slots");
    ensure!(
        crc(&b[..28]) == u32::from_le_bytes(b[28..32].try_into()?),
        "boot control CRC mismatch"
    );
    let slot = |i: usize| {
        let v = u16::from_le_bytes([b[12 + 2 * i], b[13 + 2 * i]]);
        SlotInfo {
            priority: (v & 15) as u8,
            tries: ((v >> 4) & 7) as u8,
            successful: (v >> 7) & 1 == 1,
        }
    };
    Ok([slot(0), slot(1)])
}
/// The boot control with slot A's successful_boot set: priority, tries and
/// every other byte stay, the CRC is recomputed. None if already set.
pub fn mark_slot_a_successful(b: &[u8; 32]) -> Result<Option<[u8; 32]>> {
    let slots = boot_control(b)?;
    if slots[0].successful {
        return Ok(None);
    }
    ensure!(slots[0].priority > 0, "slot A has priority 0");
    let mut n = *b;
    n[12] |= 0x80;
    let crc = crc(&n[..28]);
    n[28..32].copy_from_slice(&crc.to_le_bytes());
    let marked = boot_control(&n)?;
    ensure!(
        marked[0]
            == SlotInfo {
                successful: true,
                ..slots[0]
            }
            && marked[1] == slots[1],
        "boot control marking changed another field"
    );
    Ok(Some(n))
}
/// Linux runs from slot A; Android on slot B must stay bootable.
pub fn check_slot_a(s: &[SlotInfo; 2]) -> Result<()> {
    ensure!(
        s[0].priority > s[1].priority,
        "boot control does not select slot A"
    );
    ensure!(
        s[1].priority > 0 && (s[1].successful || s[1].tries > 0),
        "Android slot B is not bootable; restore it before storage work"
    );
    Ok(())
}
