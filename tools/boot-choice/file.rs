// SPDX-License-Identifier: GPL-2.0-only
// Host regular-file page transformer only. NOT a block-device backend.
#[path="format.rs"] mod format;
use std::{env,fs,io::Write};
fn main() {
 let a:Vec<String>=env::args().collect();assert_eq!(a.len(),5,"INPUT_PAGES OUTPUT_NEW GENERATION_HEX android|uboot");
 let meta=fs::symlink_metadata(&a[1]).unwrap();assert!(meta.file_type().is_file() && meta.len()==8192);
 assert_eq!(a[3].len(),64);let mut g=[0;32];for (i,v) in g.iter_mut().enumerate(){*v=u8::from_str_radix(&a[3][i*2..i*2+2],16).unwrap();}
 let mode=match a[4].as_str(){"android"=>0,"uboot"=>1,_=>panic!("mode")};
 let mut p=fs::read(&a[1]).unwrap();format::update(&mut p,&g,mode).unwrap();
 let mut out=fs::OpenOptions::new().write(true).create_new(true).open(&a[2]).unwrap();out.write_all(&p).unwrap();out.sync_all().unwrap();
}
