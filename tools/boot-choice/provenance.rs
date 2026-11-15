// SPDX-License-Identifier: GPL-2.0-only
//! Volatile EFI metadata, not a device binding or write capability.
use crate::{context, owned};
include!(concat!(env!("OUT_DIR"), "/provenance_wire.rs"));
pub fn efivar_name() -> String { format!("{NAME}-{GUID}") }
pub fn decode(bytes: &[u8]) -> context::Result<context::Context> {
    if bytes.len() != 4 + SIZE || u32::from_le_bytes(bytes[..4].try_into().unwrap()) != ATTRIBUTES {
        return Err("volatile provenance attributes/length");
    }
    let c = context::decode(&bytes[4..])?;
    if !c.read_only && c.stored != c.selected { return Err("pending provenance is not booted state"); }
    Ok(c)
}
/// Additional consistency gate only. Caller must still establish actual target
/// controller, booted slot and current ESP/LoaderDevicePartUUID authority.
pub fn matches_image(c: &context::Context, image: &owned::Image) -> context::Result<()> {
    matches_fields(c, &image.generation, image.sequence, image.mode)
}
fn matches_fields(c: &context::Context, generation: &[u8;32], sequence: u64, mode: u32) -> context::Result<()> {
    if &c.generation != generation || c.sequence != sequence || c.stored != mode {
        return Err("stale provenance/image");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> Vec<u8> {
        let mut b=vec![0;100];b[..4].copy_from_slice(&ATTRIBUTES.to_le_bytes());
        for (at,n) in [(4,1u32),(8,96),(12,1),(28,1),(32,80),(76,1),(80,1),(88,1),(92,1)] {b[at..at+4].copy_from_slice(&n.to_le_bytes());}
        b[20..28].copy_from_slice(b"BCINTENT");b[36..68].fill(3);b[68..76].copy_from_slice(&7u64.to_le_bytes());
        let mut c=!0u32;for x in &b[20..] {c^=*x as u32;for _ in 0..8 {c=(c>>1)^(0xedb88320u32.wrapping_mul(c&1));}}
        b[96..100].copy_from_slice(&(!c).to_le_bytes());b
    }
    fn reseal(b: &mut [u8]) {
        b[96..100].fill(0);
        let mut c=!0u32;
        for x in &b[20..] {c^=*x as u32;for _ in 0..8 {c=(c>>1)^(0xedb88320u32.wrapping_mul(c&1));}}
        b[96..100].copy_from_slice(&(!c).to_le_bytes());
    }
    #[test] fn readonly_linux_with_android_default() {
        let mut b=fixture();b[76..80].fill(0);b[84..88].copy_from_slice(&2u32.to_le_bytes());
        reseal(&mut b);
        let c=decode(&b).unwrap();assert!(c.read_only);
        assert_eq!((c.stored,c.selected),(0,1));
        assert!(matches_fields(&c,&[3;32],7,0).is_ok());
        assert!(matches_fields(&c,&[3;32],7,1).is_err());
        b[80..84].fill(0);
        reseal(&mut b);
        assert!(decode(&b).is_err());
    }
    #[test] fn volatile_context_strict() {
        let good=fixture();let c=decode(&good).unwrap();assert_eq!((c.slot,c.sequence,c.stored),(1,7,1));
        assert!(matches_fields(&c,&[3;32],7,1).is_ok());
        assert!(matches_fields(&c,&[4;32],7,1).is_err());
        assert!(matches_fields(&c,&[3;32],8,1).is_err());
        assert!(matches_fields(&c,&[3;32],7,0).is_err());
        assert_eq!(efivar_name(),"AndroidDevicesBootContext-9fae4b51-9d56-4e38-a7c1-5164e84d6082");
        for i in 0..100 {let mut b=good.clone();b[i]^=1;assert!(decode(&b).is_err(),"byte{i}");}
        assert!(decode(&good[..99]).is_err());assert!(decode(&[]).is_err());
        let mut pending=good.clone();pending[80..84].fill(0);pending[84..88].copy_from_slice(&1u32.to_le_bytes());pending[96..100].fill(0);
        let mut sum=!0u32;for x in &pending[20..] {sum^=*x as u32;for _ in 0..8 {sum=(sum>>1)^(0xedb88320u32.wrapping_mul(sum&1));}}
        pending[96..100].copy_from_slice(&(!sum).to_le_bytes());
        assert!(context::decode(&pending[4..]).is_ok());assert!(decode(&pending).is_err());
        for attr in [0u32,2,4,7] {let mut b=good.clone();b[..4].copy_from_slice(&attr.to_le_bytes());assert!(decode(&b).is_err());}
    }
}
