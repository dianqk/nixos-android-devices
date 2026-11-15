// SPDX-License-Identifier: GPL-2.0-only
use std::{env, fs, path::PathBuf};
fn main() {
    println!("cargo:rerun-if-changed=context-wire.h");
    let header = fs::read_to_string("context-wire.h").unwrap();
    let mut output = String::new();
    for (key, ty) in [("NAME", "&str"), ("GUID", "&str"), ("SIZE", "usize"), ("ATTRIBUTES", "u32")] {
        let prefix = format!("#define BOOT_CHOICE_PROVENANCE_{key} ");
        let value = header.lines().find_map(|l| l.strip_prefix(&prefix)).unwrap();
        output.push_str(&format!("pub const {key}: {ty} = {value};\n"));
    }
    fs::write(PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("provenance_wire.rs"), output).unwrap();
    let path="../early-entry/runtime-template.h";
    println!("cargo:rerun-if-changed={path}");
    let header=fs::read_to_string(path).unwrap();let mut output=String::new();
    for key in ["BYTES","ENTRY","INVERSE","STORED"] {
        let prefix=format!("#define EG_RUNTIME_{key} ");
        let value=header.lines().find_map(|l|l.strip_prefix(&prefix)).unwrap();
        output.push_str(&format!("const EG_RUNTIME_{key}: usize = {value};\n"));
    }
    fs::write(PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("template_wire.rs"),output).unwrap();

}
