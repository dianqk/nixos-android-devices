# Mobile initrd dependency collector

[中文](README.zh.md)

This wraps the pinned Nixpkgs `makeInitrdNGTool` with a small source patch.
The mobile systemd-initrd module passes this native build-host tool to
`makeInitrdNG`; systemd and device libraries are unchanged.

- Keep each `.note.dlopen` SONAME array as one alternatives group, selecting
  the first available name. This avoids requiring both OpenSSL
  3 and 4, both libbpf ABIs, and each supported libcrypt ABI. See
  [UAPI.12](https://uapi-group.org/specifications/specs/elf_dlopen_metadata/).
- Search an existing sibling after RUNPATH/RPATH directories. The pinned
  cross GCC libstdc++ only records glibc in RUNPATH, while libgcc_s.so.1 is
  beside it. Copy that dependency rather than suppressing its diagnostic.
  This is a collection fallback, not a change to runtime linker search paths.
- Keep each DT_NEEDED library independent and retain diagnostics when no
  matching file exists. Do not create false `.so.4` aliases to `.so.3`.

Six Rust regression tests cover preferred/fallback alternatives, unresolved
libraries, sibling lookup and RUNPATH precedence.
