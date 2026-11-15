// SPDX-License-Identifier: GPL-2.0-only
// Original implementation; no SunUEFI code copied.
pub const PAGE: usize = 4096;
pub const MAGIC: &[u8;8] = b"BOOTREQ1";
pub fn crc(p: &[u8]) -> u32 {
 let mut c = !0u32;
 for (i,b) in p.iter().enumerate() { c ^= if (60..64).contains(&i) {0} else {*b as u32};
  for _ in 0..8 { c = (c >> 1) ^ (0xedb88320u32.wrapping_mul(c & 1)); }
 } !c
}
pub fn parse(p: &[u8], generation: &[u8;32]) -> Option<(u64,u32)> {
 if p.len()!=PAGE || &p[..8]!=MAGIC || p[8..12]!=1u32.to_le_bytes() ||
 p[12..44]!=generation[..] || generation.iter().all(|v|*v==0) || p[64..].iter().any(|v|*v!=0) {return None}
 let seq=u64::from_le_bytes(p[44..52].try_into().ok()?);
 let mode=u32::from_le_bytes(p[52..56].try_into().ok()?);
 if seq==0 || mode>1 || p[56..60]!=[0;4] || u32::from_le_bytes(p[60..64].try_into().ok()?)!=crc(p) {return None} Some((seq,mode))
}
pub fn record(g: &[u8;32], seq:u64, mode:u32) -> [u8;PAGE] {
 assert!(seq>0 && mode<=1 && g.iter().any(|x|*x!=0));
 let mut p=[0;PAGE]; p[..8].copy_from_slice(MAGIC);p[8..12].copy_from_slice(&1u32.to_le_bytes());
 p[12..44].copy_from_slice(g);p[44..52].copy_from_slice(&seq.to_le_bytes());p[52..56].copy_from_slice(&mode.to_le_bytes());
 let c=crc(&p);p[60..64].copy_from_slice(&c.to_le_bytes());p
}
pub fn update(p: &mut [u8], g:&[u8;32], mode:u32) -> Result<(), &'static str> {
 if p.len()!=2*PAGE || mode>1 {return Err("bounds/mode")}
 let a=parse(&p[..PAGE],g);let b=parse(&p[PAGE..],g);
 if let (Some(a),Some(b))=(a,b) {if a.0==b.0 && a.1!=b.1 {return Err("sequence conflict")}}
 let seq=a.map_or(0,|v|v.0).max(b.map_or(0,|v|v.0)).checked_add(1).ok_or("sequence exhausted")?;
 let at=if a.is_none() || (b.is_some() && a.unwrap().0<=b.unwrap().0) {0} else {PAGE};
 p[at..at+PAGE].copy_from_slice(&record(g,seq,mode));Ok(())
}
#[cfg(test)] mod tests {use super::*;
 #[test] fn validation() {let g=[3;32];let p=record(&g,1,1);assert_eq!(parse(&p,&g),Some((1,1)));assert_eq!(parse(&p,&[4;32]),None);
 for i in 0..PAGE {let mut q=p;q[i]^=1;assert_eq!(parse(&q,&g),None,"byte {i}")}}
 #[test] fn redundancy() {let g=[2;32];let mut p=[0;8192];update(&mut p,&g,1).unwrap();update(&mut p,&g,0).unwrap();assert_eq!(parse(&p[PAGE..],&g),Some((2,0)));update(&mut p,&g,1).unwrap();assert_eq!(parse(&p[..PAGE],&g),Some((3,1)));p[..PAGE].copy_from_slice(&record(&g,u64::MAX,1));assert!(update(&mut p,&g,0).is_err());}
}
